#!/bin/bash
# Controllo di sicurezza settimanale, con esito su Telegram (tg-notify, come watchdog e daily-report).
#
# Controlla cio' che gira davvero in produzione:
#  - librerie con vulnerabilita' note dentro i container: composer audit (manualsweb, site),
#    npm audit --omit=dev (manualswebapp, machine-ledger), solo gravita' alta e critica;
#  - aggiornamenti di sicurezza del sistema e riavvio richiesto;
#  - versione di PHP e di Node nei container rispetto all'ultima patch della stessa serie.
#
# Avvisa in dettaglio solo le NOVITA' rispetto all'esecuzione precedente (stato in
# /var/lib/security-audit/known.txt); le altre settimane manda una riga "nessuna novita'".
# Non corregge nulla da solo: le correzioni passano da staging e poi produzione, con l'ok
# del responsabile.
#
# Installazione: /root/security-audit.sh, cron domenica 07:30 UTC (dopo offsite 06:00 e
# daily-report 07:00). Log: /var/log/security-audit.log. Prova senza Telegram: --dry-run.

set -u
STATE=/var/lib/security-audit
mkdir -p "$STATE"
KNOWN="$STATE/known.txt"
touch "$KNOWN"
DRY_RUN=0; [ "${1:-}" = "--dry-run" ] && DRY_RUN=1
CUR=$(mktemp); ERR=$(mktemp)
trap 'rm -f "$CUR" "$ERR"' EXIT

log() { echo "[$(date '+%F %T')] $*"; }
# Una riga per problema: CHIAVE<TAB>testo leggibile. La chiave decide se e' "nuovo".
add() { printf '%s\t%s\n' "$1" "$2" >> "$CUR"; }

# --- librerie PHP (composer audit nei container) ---
for APP in manualsweb:manualsweb-app-prod site:site-app-prod; do
  NAME=${APP%%:*}; C=${APP#*:}
  if ! OUT=$(docker exec -w /var/www/html "$C" composer audit --locked --no-interaction --format=json 2>/dev/null) && [ -z "$OUT" ]; then
    echo "$NAME: composer audit non eseguito" >> "$ERR"; continue
  fi
  echo "$OUT" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    print(f"ERR\t{name}: risposta di composer audit non leggibile"); sys.exit()
for pkg, advs in (d.get("advisories") or {}).items():
    advs = list(advs.values()) if isinstance(advs, dict) else advs
    for a in advs:
        sev = (a.get("severity") or "n/d").lower()
        if sev in ("low", "medium", "moderate"):
            continue
        aid = a.get("cve") or a.get("advisoryId")
        title = (a.get("title") or "")[:90]
        print(f"php:{name}:{pkg}:{aid}\t{name}: {pkg} - {sev} - {title}")
' "$NAME"
done | while IFS=$'\t' read -r K T; do [ "$K" = ERR ] && echo "$T" >> "$ERR" || add "$K" "$T"; done

# --- librerie Node (npm audit nei container) ---
for APP in manualswebapp:manualswebapp-app-prod machine-ledger:machineledger-app-prod; do
  NAME=${APP%%:*}; C=${APP#*:}
  OUT=$(docker exec "$C" npm audit --omit=dev --json 2>/dev/null)
  if [ -z "$OUT" ]; then echo "$NAME: npm audit non eseguito" >> "$ERR"; continue; fi
  echo "$OUT" | python3 -c '
import json, sys
name = sys.argv[1]
try:
    d = json.load(sys.stdin)
except Exception:
    print(f"ERR\t{name}: risposta di npm audit non leggibile"); sys.exit()
for pkg, v in (d.get("vulnerabilities") or {}).items():
    if v.get("severity") not in ("high", "critical"):
        continue
    titles = [x.get("title", "") for x in v.get("via", []) if isinstance(x, dict)]
    fix = v.get("fixAvailable")
    fixtxt = "correzione compatibile" if fix is True else ("solo con versione maggiore" if fix else "nessuna correzione")
    rng = v.get("range") or ""
    sev = v["severity"]
    title = (titles[0] if titles else "")[:80]
    print(f"node:{name}:{pkg}:{rng}\t{name}: {pkg} - {sev} - {title} ({fixtxt})")
' "$NAME"
done | while IFS=$'\t' read -r K T; do [ "$K" = ERR ] && echo "$T" >> "$ERR" || add "$K" "$T"; done

# --- sistema ---
apt-get update -qq >/dev/null 2>&1
SEC=$(apt list --upgradable 2>/dev/null | grep -c -i -- '-security')
[ "$SEC" -gt 0 ] && add "os:security:$SEC" "Server: $SEC aggiornamenti di sicurezza in attesa (unattended-upgrades dovrebbe installarli)"
[ -f /var/run/reboot-required ] && add "os:reboot" "Server: riavvio richiesto ($(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null | cut -c1-80))"

# --- PHP e Node: ultima patch della stessa serie ---
# Ogni container separatamente: il 23/11 site era rimasto a 8.5.12 mentre manualsweb era a 8.5.13.
for APP in manualsweb:manualsweb-app-prod site:site-app-prod; do
  NAME=${APP%%:*}; C=${APP#*:}
  PHPV=$(docker exec "$C" php -r 'echo PHP_VERSION;' 2>/dev/null)
  if [ -z "$PHPV" ]; then echo "$NAME: versione PHP non letta" >> "$ERR"; continue; fi
  SERIE=${PHPV%.*}
  LATEST=$(curl -fsS -m 20 "https://www.php.net/releases/index.php?json&version=$SERIE" 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin).get("version",""))' 2>/dev/null)
  if [ -z "$LATEST" ]; then echo "PHP: versione piu' recente non verificata (php.net)" >> "$ERR"
  elif [ "$LATEST" != "$PHPV" ]; then add "php-version:$NAME:$LATEST" "PHP: $NAME a $PHPV, disponibile $LATEST (rifare il deploy di $NAME: la build scarica l'ultima patch)"; fi
done
NODEV=$(docker exec manualswebapp-app-prod node -v 2>/dev/null)
if [ -n "$NODEV" ]; then
  MAJ=${NODEV%%.*}
  LATEST=$(curl -fsS -m 20 https://nodejs.org/dist/index.json 2>/dev/null | python3 -c '
import json, sys
maj = sys.argv[1]
rel = [r for r in json.load(sys.stdin) if r["version"].startswith(maj + ".")]
if rel:
    sec = [r for r in rel if r.get("security")]
    print(rel[0]["version"], sec[0]["version"] if sec else "")
' "$MAJ" 2>/dev/null)
  read -r NODE_LATEST NODE_SEC <<< "$LATEST"
  if [ -z "$NODE_LATEST" ]; then echo "Node: versione piu' recente non verificata (nodejs.org)" >> "$ERR"
  elif [ -n "$NODE_SEC" ] && [ "$(printf '%s\n%s\n' "${NODEV#v}" "${NODE_SEC#v}" | sort -V | head -1)" != "${NODE_SEC#v}" ]; then
    add "node-version:$NODE_SEC" "Node: nei container $NODEV, rilascio di sicurezza $NODE_SEC (aggiornare FROM node nei Dockerfile di manualswebapp e machine-ledger)"
  fi
fi

# --- confronto con la settimana precedente ---
sort -u -o "$CUR" "$CUR"
NEW=$(cut -f1 "$CUR" | grep -vxF -f <(cut -f1 "$KNOWN") || true)
GONE=$(cut -f1 "$KNOWN" | grep -vxF -f <(cut -f1 "$CUR") || true)
TOT=$(wc -l < "$CUR")

MSG=""
if [ -n "$NEW" ]; then
  MSG="🔐 Controllo sicurezza settimanale: $(echo "$NEW" | wc -l) novità"$'\n'
  while IFS= read -r K; do MSG+="• $(awk -F'\t' -v k="$K" '$1==k {print $2}' "$CUR")"$'\n'; done <<< "$NEW"
fi
[ -n "$GONE" ] && MSG+="✅ Risolti dalla settimana scorsa: $(echo "$GONE" | wc -l)"$'\n'
[ -s "$ERR" ] && MSG+="⚠️ Controlli non riusciti: $(tr '\n' ';' < "$ERR")"$'\n'
[ -z "$MSG" ] && MSG="🔐 Controllo sicurezza settimanale: nessuna novità"
[ "$TOT" -gt 0 ] && MSG+="(aperti in totale: $TOT)"

log "esito: totale $TOT, nuovi $(echo -n "$NEW" | grep -c . || true), risolti $(echo -n "$GONE" | grep -c . || true)"
cat "$CUR" | sed 's/^/  /'
[ -s "$ERR" ] && sed 's/^/  ERRORE: /' "$ERR"

if [ "$DRY_RUN" -eq 1 ]; then
  echo "--- messaggio (dry-run, non inviato) ---"; echo "$MSG"
else
  /usr/local/bin/tg-notify "$MSG" || log "invio Telegram fallito"
  cp "$CUR" "$KNOWN"
fi
