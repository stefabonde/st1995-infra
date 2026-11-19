#!/bin/bash
# Copia settimanale dei backup su Google Drive, cifrata con rclone crypt.
# Prende l'ultimo set settimanale (16 dump DB) e l'ultimo archivio upload creati
# dallo script backup-db.sh (domenica 04:00 UTC) e li carica in una cartella datata.
# Mantiene le ultime 4 settimane (cancellazione definitiva, senza cestino Drive).
#
# Config: remote rclone "gdrive-crypt:" (crypt sopra "gdrive:backup-hetzner").
# Opzionale: /root/.secrets/offsite.env con HC_URL=<url ping healthchecks.io>

set -u
set -o pipefail   # un errore di rclone non deve essere nascosto da | tail
B=/var/www/production/manualswebapp-prod/backups
REMOTE="gdrive-crypt:"
DATE=$(date +%Y-%m-%d)
RETENTION_DAYS=28
MAX_AGE_HOURS=48
LOG_TAG="[offsite $(date +%F_%T)]"
FAIL=0

[ -f /root/.secrets/offsite.env ] && . /root/.secrets/offsite.env
HC_URL="${HC_URL:-}"

say() { echo "$LOG_TAG $*"; }
ping_hc() { [ -n "$HC_URL" ] && curl -fsS -m 10 --retry 3 -o /dev/null "$HC_URL$1" || true; }
notify() { /usr/local/bin/tg-notify "$1" >/dev/null 2>&1 || true; }

ping_hc "/start"

# --- file da caricare: l'ultimo set settimanale e l'ultimo archivio upload ---
LATEST_DB=$(ls -t "$B"/weekly/*.sql.gz 2>/dev/null | head -1)
LATEST_UP=$(ls -t "$B"/uploads/uploads_*.tar.gz 2>/dev/null | head -1)
if [ -z "$LATEST_DB" ] || [ -z "$LATEST_UP" ]; then
  say "ERRORE: set settimanale o archivio upload non trovati in $B"
  notify "❌ Copia offsite su Drive: backup settimanale non trovato"; ping_hc "/fail"; exit 1
fi
TS=$(basename "$LATEST_DB" | sed -E 's/.*_([0-9]{8}_[0-9]{6})\.sql\.gz/\1/')
AGE_H=$(( ( $(date +%s) - $(stat -c %Y "$LATEST_DB") ) / 3600 ))
if [ "$AGE_H" -gt "$MAX_AGE_HOURS" ]; then
  say "ERRORE: l'ultimo set settimanale ha $AGE_H ore (max $MAX_AGE_HOURS): il backup di domenica è fallito?"
  notify "❌ Copia offsite su Drive: il backup di domenica è vecchio di $AGE_H ore"; ping_hc "/fail"; exit 1
fi
say "Carico set DB $TS ($(ls "$B"/weekly/*_${TS}.sql.gz | wc -l) file) + $(basename "$LATEST_UP")"

COMMON="--drive-use-trash=false --transfers 1 --drive-chunk-size 16M --retries 3 --low-level-retries 10 --stats-one-line -v"

# se Google limita il caricamento (rateLimitExceeded, 08/11) secondo giro dopo 30 minuti:
# rclone copy riprende solo i file mancanti. PIPESTATUS: esito di rclone, non di tail.
copia() {
  local DA=$1 A=$2 INC=$3
  for GIRO in 1 2; do
    rclone copy "$DA" "$A" --include "$INC" $COMMON 2>&1 | tail -3
    [ "${PIPESTATUS[0]}" -eq 0 ] && return 0
    [ "$GIRO" -eq 1 ] && { say "copia verso $A non riuscita: riprovo tra 30 minuti"; sleep 1800; }
  done
  return 1
}
copia "$B/weekly" "$REMOTE$DATE/db" "*_${TS}.sql.gz" || FAIL=1
copia "$B/uploads" "$REMOTE$DATE/uploads" "$(basename "$LATEST_UP")" || FAIL=1

# --- verifica: checksum dei file cifrati su Drive ---
# cryptcheck confronta i checksum (MD5 di Drive) dei file cifrati con quelli locali
if ! rclone cryptcheck "$B/weekly" "$REMOTE$DATE/db" --include "*_${TS}.sql.gz" --one-way 2>&1 | tail -2; then FAIL=1; fi
if ! rclone cryptcheck "$B/uploads" "$REMOTE$DATE/uploads" --include "$(basename "$LATEST_UP")" --one-way 2>&1 | tail -2; then FAIL=1; fi

# --- retention: elimina cartelle più vecchie di 28 giorni (definitivo) ---
rclone delete "$REMOTE" --min-age "${RETENTION_DAYS}d" --drive-use-trash=false 2>&1 | tail -2
rclone rmdirs "$REMOTE" --leave-root --drive-use-trash=false 2>&1 | tail -2

say "Cartelle presenti su Drive (cifrate/decifrate): $(rclone lsd "$REMOTE" 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')"
say "Spazio usato: $(rclone size "$REMOTE" 2>/dev/null | tr '\n' ' ')"

STAT=$(rclone size "$REMOTE$DATE" 2>/dev/null)
N=$(echo "$STAT" | grep "Total objects" | cut -d: -f2 | cut -d"(" -f1 | xargs)
SIZE=$(echo "$STAT" | grep "Total size" | cut -d: -f2 | cut -d"(" -f1 | xargs)
if [ "$FAIL" -eq 0 ]; then say "OK"; notify "✅ Copia offsite su Drive ok ($DATE): $N file cifrati, $SIZE, verifica senza differenze"; ping_hc ""; exit 0; else say "ERRORE: controllare il log"; notify "❌ Copia offsite su Drive FALLITA ($DATE): vedere /var/log/offsite-backup.log"; ping_hc "/fail"; exit 1; fi
