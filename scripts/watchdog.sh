#!/bin/bash
# Controlli critici ogni 5 minuti, con avviso Telegram solo quando qualcosa cambia:
# "❌" quando un problema compare, "✅ risolto" quando sparisce.
# Correzioni automatiche solo dove sono sicure:
# - container fermo da almeno 2 giri (≥5 min, per non interferire coi deploy): un tentativo di avvio;
# - file PHP negli upload: spostato in quarantena (/root/quarantena), non eseguibile.
# Stato in /var/lib/watchdog (un file per problema aperto). Log: /var/log/watchdog.log
# Cron: */5 * * * *

set -u
STATE=/var/lib/watchdog
mkdir -p "$STATE/open" "$STATE/count"
NOW=$(date +%s)
declare -A PROB=()          # chiave -> messaggio dei problemi presenti ora

notify() { /usr/local/bin/tg-notify "$1" >/dev/null 2>&1 || true; echo "[$(date '+%F %T')] $1"; }
# contatore di giri consecutivi per una chiave (azzerato quando la condizione sparisce)
bump() { local f="$STATE/count/$1"; local n=$(( $(cat "$f" 2>/dev/null || echo 0) + 1 )); echo $n > "$f"; echo $n; }
clear_count() { rm -f "$STATE/count/$1"; }

# --- siti: due tentativi a 10 s di distanza prima di considerarli giù ---
for U in https://www.manualsweb.it/login https://www.manualswebapp.it https://cometo.manualswebapp.it \
         https://st1995.it https://app.st1995.it/login https://machineledgerweb.com; do
  C=$(curl -s -o /dev/null -m 30 -w '%{http_code}' "$U")
  if ! [[ "$C" =~ ^[23] ]]; then
    sleep 10; C=$(curl -s -o /dev/null -m 30 -w '%{http_code}' "$U")
  fi
  K="sito_$(echo "$U" | tr -c 'a-zA-Z0-9' '_')"
  [[ "$C" =~ ^[23] ]] || PROB[$K]="Sito $U non risponde (codice $C)"
done

# --- container ---
while read -r NAME STATUS; do
  K="container_$NAME"
  case "$STATUS" in
    Up*unhealthy*) PROB[$K]="Container $NAME unhealthy" ;;
    Up*) clear_count "$K" ;;
    Restarting*) PROB[$K]="Container $NAME in crash (si riavvia di continuo)" ;;
    *)
      N=$(bump "$K")
      if [ "$N" -ge 2 ] && [ ! -e "$STATE/count/$K.tried" ]; then
        touch "$STATE/count/$K.tried"
        if docker start "$NAME" >/dev/null 2>&1 && sleep 15 && docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
          notify "🔧 Container $NAME era fermo: riavviato in automatico, ora è attivo."
          clear_count "$K"; rm -f "$STATE/count/$K.tried"
          continue
        fi
        PROB[$K]="Container $NAME fermo: riavvio automatico FALLITO ($STATUS)"
      elif [ "$N" -ge 2 ]; then
        PROB[$K]="Container $NAME fermo ($STATUS)"
      fi
      ;;
  esac
done < <(docker ps -a --format '{{.Names}} {{.Status}}')
# pulizia dei tentativi per container tornati su
for T in "$STATE"/count/container_*.tried; do
  [ -e "$T" ] || continue
  B=$(basename "$T" .tried); [ -e "$STATE/count/$B" ] || rm -f "$T"
done

# --- disco ---
DISCO=$(df --output=pcent / | tail -1 | tr -dc '0-9')
[ "$DISCO" -ge 90 ] && PROB[disco]="Disco al ${DISCO}%"

# --- errori 5xx negli ultimi 5 minuti ---
SINCE=$(date -d '-5 min' '+%d/%b/%Y:%H:%M')
N5=$(awk -v s="$SINCE" '{t=substr($4,2,17)} t>=s && $9 ~ /^5/' /var/log/nginx/access.log | wc -l)
if [ "$N5" -ge 10 ]; then
  TOP=$(awk -v s="$SINCE" '{t=substr($4,2,17)} t>=s && $9 ~ /^5/ {print $9, $7}' /var/log/nginx/access.log \
        | cut -c1-70 | sort | uniq -c | sort -rn | head -3 | awk '{$1=$1"×"; print}' | paste -sd ';' -)
  PROB[errori5xx]="$N5 errori 5xx negli ultimi 5 minuti → $TOP"
fi

# --- file PHP negli upload: quarantena immediata ---
UPL="/var/www/production/*/uploads /var/www/production/*/web/uploads"
{
  find $UPL -type f \( -iname '*.php*' -o -iname '*.phtml' -o -iname '*.phar' -o -iname '*.pht' \
       -o -name '.htaccess' -o -name '.user.ini' \) 2>/dev/null
  find $UPL -type f -mmin -15 -size -5M -exec grep -l -m1 -F '<?php' {} + 2>/dev/null
} | sort -u | while read -r F; do
  Q=/root/quarantena/$(date +%Y%m%d-%H%M%S)$F
  mkdir -p "$(dirname "$Q")"
  if mv "$F" "$Q" && chmod 000 "$Q"; then
    notify "🚨 File sospetto (PHP) negli upload, spostato in quarantena:
$F
→ $Q
Se è un falso allarme, per rimetterlo: mv '$Q' '$F' && chmod 644 '$F'
Se non lo è: scrivimi subito, va controllato come è arrivato."
  else
    notify "🚨 File sospetto (PHP) negli upload: $F — quarantena FALLITA, controllare subito."
  fi
done

# --- IP bannati da fail2ban per troppe richieste (può essere un utente vero) ---
LAST=$(cat "$STATE/f2b-last" 2>/dev/null || echo "$NOW")   # primo giro: niente storico
grep -h "\[nginx-limit-req\] Ban " /var/log/fail2ban.log 2>/dev/null | awk '{print $1, $2, $NF}' | while read -r D T IP; do
  TS=$(date -d "$D ${T%,*}" +%s 2>/dev/null) || continue
  [ "$TS" -gt "$LAST" ] && [ "$TS" -le "$NOW" ] || continue
  notify "⛔ IP $IP bloccato per 15 minuti (troppe richieste). Se è un utente o l'ufficio, per sbloccarlo:
fail2ban-client set nginx-limit-req unbanip $IP"
done
echo "$NOW" > "$STATE/f2b-last"

# --- confronto con lo stato precedente: avvisa solo i cambiamenti ---
for K in "${!PROB[@]}"; do
  if [ ! -e "$STATE/open/$K" ]; then
    echo "${PROB[$K]}" > "$STATE/open/$K"
    notify "❌ ${PROB[$K]}"
  fi
done
for F in "$STATE"/open/*; do
  [ -e "$F" ] || continue
  K=$(basename "$F")
  if [ -z "${PROB[$K]+x}" ]; then
    notify "✅ Risolto: $(cat "$F")"
    rm -f "$F"
  fi
done
