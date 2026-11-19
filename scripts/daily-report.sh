#!/bin/bash
# Rapporto giornaliero del server su Telegram: "tutto ok" oppure l'elenco dei problemi.
# Controlla: backup notturno dei DB, indicizzazioni, container, disco, siti,
# certificati, riavvio richiesto, servizi systemd falliti.
# Cron: ogni giorno 07:00 UTC (dopo backup 04:00 e copia offsite della domenica 06:00).

set -u
TODAY=$(date +%Y%m%d)
B=/var/www/production/manualswebapp-prod/backups
BACKUP_LOG=/var/log/manuals-backup-prod.log
PROBLEMI=()
INFO=()

# --- backup notturno dei DB ---
RUN=$(awk -v d="_${TODAY}_" 'index($0, d) {f=1} f' "$BACKUP_LOG")
N_DUMP=$(ls "$B"/*_"${TODAY}"_*.sql.gz 2>/dev/null | wc -l)
ESITO=$(cat /var/lib/watchdog/backup-esito 2>/dev/null)   # scritto da /root/backup-with-retry.sh
if [ -z "$RUN" ] || [ "$N_DUMP" -eq 0 ]; then
  PROBLEMI+=("Backup DB: nessun backup di stanotte")
elif [ "$ESITO" = "$TODAY fallito" ]; then
  PROBLEMI+=("Backup DB: fallito anche al secondo tentativo")
elif [ "$ESITO" = "$TODAY ok-al-secondo" ]; then
  INFO+=("Backup DB: riuscito al secondo tentativo")
elif echo "$RUN" | grep -q "❌"; then
  PROBLEMI+=("Backup DB: errori → $(echo "$RUN" | grep "❌" | head -3 | tr '\n' ' ')")
elif ! echo "$RUN" | grep -q "Tutti i backup completati"; then
  PROBLEMI+=("Backup DB: non risulta concluso")
else
  INFO+=("Backup DB: $N_DUMP dump, $(du -ch "$B"/*_"${TODAY}"_*.sql.gz | tail -1 | cut -f1)")
fi

# --- backup sospetti: dump molto più piccolo di ieri o DB sparito ---
YDAY=$(date -d yesterday +%Y%m%d)
for P in "$B"/*_"${YDAY}"_*.sql.gz; do
  [ -e "$P" ] || continue
  DB=$(basename "$P" | sed -E "s/_${YDAY}_[0-9]{6}\.sql\.gz$//")
  F=$(ls "$B"/"${DB}"_"${TODAY}"_*.sql.gz 2>/dev/null | head -1)
  if [ -z "$F" ]; then PROBLEMI+=("Backup $DB: c'era ieri, manca oggi"); continue; fi
  S0=$(stat -c %s "$P"); S1=$(stat -c %s "$F")
  if [ "$S0" -gt 102400 ] && [ $((S1 * 100 / S0)) -lt 70 ]; then
    PROBLEMI+=("Backup $DB: $(numfmt --to=iec "$S1") contro $(numfmt --to=iec "$S0") di ieri (-$((100 - S1 * 100 / S0))%)")
  fi
done

# --- errori dei siti ieri (log nginx del giorno prima) ---
NGX=/var/log/nginx/access.log.1
if [ "$(head -1 "$NGX" | cut -d[ -f2 | cut -d: -f1)" = "$(date -d yesterday +%d/%b/%Y)" ]; then
  N5=$(awk '$9 ~ /^5/' "$NGX" | wc -l)
  N429=$(awk '$9 == 429' "$NGX" | wc -l)
  if [ "$N5" -ge 5 ] || awk '$9 ~ /^50[234]$/ {f=1} END {exit !f}' "$NGX"; then
    TOP=$(awk '$9 ~ /^5/ {print $9, $7}' "$NGX" | cut -c1-70 | sort | uniq -c | sort -rn | head -3 | awk '{$1=$1" ×"; print}' | paste -sd ';' -)
    PROBLEMI+=("Siti ieri: $N5 errori 5xx → $TOP")
  fi
  INFO+=("Siti ieri: $N5 errori 5xx, $N429 richieste bloccate (429)")
fi

# --- file PHP negli upload (possibile backdoor) ---
UPL="/var/www/production/*/uploads /var/www/production/*/web/uploads"
SOSPETTI=$(find $UPL -type f \( -iname '*.php*' -o -iname '*.phtml' -o -iname '*.phar' -o -iname '*.pht' \
            -o -name '.htaccess' -o -name '.user.ini' \) 2>/dev/null | head -5)
# solo "<?php": "<?=" (3 byte) compare per caso nei dati compressi delle immagini (falso allarme 05/11)
RECENTI=$(find $UPL -type f -mtime -2 -size -5M -exec grep -l -m1 -F '<?php' {} + 2>/dev/null | head -5)
[ -n "$SOSPETTI$RECENTI" ] && PROBLEMI+=("File PHP negli upload: $(echo $SOSPETTI $RECENTI | tr ' ' '\n' | sort -u | paste -sd ' ' -)")

# --- indicizzazioni notturne (chatbot) ---
for L in /var/log/manuals-indexing-prod.log /var/log/rapportini-indexing-prod.log; do
  NOME=$(basename "$L" .log)
  if [ "$(date -r "$L" +%Y%m%d 2>/dev/null)" != "$TODAY" ]; then
    PROBLEMI+=("Indicizzazione $NOME: non eseguita stanotte")
  elif ! tail -3 "$L" | grep -q "Processo globale completato"; then
    PROBLEMI+=("Indicizzazione $NOME: non conclusa")
  fi
done

# --- container ---
GIU=$(docker ps -a --format '{{.Names}} {{.Status}}' | grep -v ' Up ' | cut -d' ' -f1 | tr '\n' ' ')
N_UP=$(docker ps -q | wc -l)
UNHEALTHY=$(docker ps --filter health=unhealthy --format '{{.Names}}' | tr '\n' ' ')
[ -n "$GIU" ] && PROBLEMI+=("Container fermi: $GIU")
[ -n "$UNHEALTHY" ] && PROBLEMI+=("Container unhealthy: $UNHEALTHY")
INFO+=("Container attivi: $N_UP")

# riavvii automatici (crash) rispetto a ieri; ricreazioni nelle ultime 24h (deploy)
STATE=/var/lib/daily-report; mkdir -p "$STATE"
docker inspect -f '{{.Name}} {{.RestartCount}}' $(docker ps -aq) | sed 's#^/##' | sort > "$STATE/restarts.new"
if [ -f "$STATE/restarts" ]; then
  CRASH=$(join "$STATE/restarts" "$STATE/restarts.new" | awk '$3 > $2 {print $1 " (" $3 - $2 "×)"}' | paste -sd ' ' -)
  [ -n "$CRASH" ] && PROBLEMI+=("Container riavviati da soli: $CRASH")
fi
mv "$STATE/restarts.new" "$STATE/restarts"
LIMITE=$(date -d '-24 hours' +%s)
NUOVI=$(docker ps --format '{{.Names}}' | while read -r C; do
  [ "$(date -d "$(docker inspect -f '{{.State.StartedAt}}' "$C")" +%s)" -gt "$LIMITE" ] && echo "$C"
done | paste -sd ' ' -)
[ -n "$NUOVI" ] && INFO+=("Container ripartiti nelle ultime 24h (deploy?): $NUOVI")

# memoria esaurita
OOM=$(journalctl -k --since '-24 hours' --no-pager 2>/dev/null | grep -ciE 'out of memory|oom-kill')
[ "$OOM" -gt 0 ] && PROBLEMI+=("Memoria esaurita: $OOM processi terminati dal kernel nelle ultime 24h")

# --- accessi SSH nelle ultime 24h (gli IP nuovi hanno già avuto l'avviso immediato) ---
N_SSH=$(journalctl -u ssh --since '-24 hours' --no-pager 2>/dev/null | grep -c 'Accepted')
N_DEPLOY=$(awk -v t="$LIMITE" '$1 > t' /var/lib/ssh-login-watch/deploy-logins 2>/dev/null | wc -l)
INFO+=("SSH 24h: $N_SSH accessi, di cui $N_DEPLOY da GitHub (deploy)")

# --- disco e memoria ---
DISCO=$(df --output=pcent / | tail -1 | tr -dc '0-9')
[ "$DISCO" -ge 80 ] && PROBLEMI+=("Disco al ${DISCO}%")
INFO+=("Disco: ${DISCO}%")

# --- siti ---
SITI_OK=0; SITI_TOT=0
for U in https://www.manualsweb.it/login https://www.manualswebapp.it https://cometo.manualswebapp.it \
         https://st1995.it https://app.st1995.it/login https://machineledgerweb.com; do
  SITI_TOT=$((SITI_TOT + 1))
  C=$(curl -s -o /dev/null -m 20 -w '%{http_code}' "$U")
  if [[ "$C" =~ ^[23] ]]; then SITI_OK=$((SITI_OK + 1)); else PROBLEMI+=("Sito $U → $C"); fi
done
INFO+=("Siti: $SITI_OK/$SITI_TOT ok")

# --- certificati ---
MIN_GG=9999
for C in /etc/letsencrypt/live/*/cert.pem; do
  GG=$(( ( $(date -d "$(openssl x509 -enddate -noout -in "$C" | cut -d= -f2)" +%s) - $(date +%s) ) / 86400 ))
  [ "$GG" -lt 20 ] && PROBLEMI+=("Certificato $(basename "$(dirname "$C")") scade tra $GG giorni")
  [ "$GG" -lt "$MIN_GG" ] && MIN_GG=$GG
done
INFO+=("Certificati: il primo scade tra $MIN_GG giorni")

# --- sistema ---
[ -f /var/run/reboot-required ] && PROBLEMI+=("Riavvio richiesto dagli aggiornamenti")
FAILED=$(systemctl --failed --no-legend --plain | awk '{print $1}' | grep -v '^cloud-init-hotplugd' | tr '\n' ' ')
[ -n "$FAILED" ] && PROBLEMI+=("Servizi falliti: $FAILED")

# --- messaggio ---
if [ ${#PROBLEMI[@]} -eq 0 ]; then
  MSG="✅ Server Hetzner: tutto ok ($(date +%d/%m))"$'\n'
  for I in "${INFO[@]}"; do MSG+="• $I"$'\n'; done
else
  MSG="⚠️ Server Hetzner: ${#PROBLEMI[@]} problemi ($(date +%d/%m))"$'\n'
  for P in "${PROBLEMI[@]}"; do MSG+="❌ $P"$'\n'; done
  for I in "${INFO[@]}"; do MSG+="• $I"$'\n'; done
fi
echo "$MSG"
[ "${DRY:-0}" = 1 ] || /usr/local/bin/tg-notify "$MSG"   # DRY=1: solo a schermo
