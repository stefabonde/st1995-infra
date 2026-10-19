#!/bin/bash
# Copia settimanale dei backup su Google Drive, cifrata con rclone crypt.
# Prende l'ultimo set settimanale (16 dump DB) e l'ultimo archivio upload creati
# (più, via server-config-snapshot.sh, configurazione del server e allegati machineledger)
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

ping_hc "/start"

# --- file da caricare: l'ultimo set settimanale e l'ultimo archivio upload ---
LATEST_DB=$(ls -t "$B"/weekly/*.sql.gz 2>/dev/null | head -1)
LATEST_UP=$(ls -t "$B"/uploads/uploads_*.tar.gz 2>/dev/null | head -1)
if [ -z "$LATEST_DB" ] || [ -z "$LATEST_UP" ]; then
  say "ERRORE: set settimanale o archivio upload non trovati in $B"
  ping_hc "/fail"; exit 1
fi
TS=$(basename "$LATEST_DB" | sed -E 's/.*_([0-9]{8}_[0-9]{6})\.sql\.gz/\1/')
AGE_H=$(( ( $(date +%s) - $(stat -c %Y "$LATEST_DB") ) / 3600 ))
if [ "$AGE_H" -gt "$MAX_AGE_HOURS" ]; then
  say "ERRORE: l'ultimo set settimanale ha $AGE_H ore (max $MAX_AGE_HOURS): il backup di domenica è fallito?"
  ping_hc "/fail"; exit 1
fi
say "Carico set DB $TS ($(ls "$B"/weekly/*_${TS}.sql.gz | wc -l) file) + $(basename "$LATEST_UP")"

COMMON="--drive-use-trash=false --transfers 2 --drive-chunk-size 64M --retries 3 --low-level-retries 10 --stats-one-line -v"

rclone copy "$B/weekly" "$REMOTE$DATE/db" --include "*_${TS}.sql.gz" $COMMON 2>&1 | tail -3 || FAIL=1
rclone copy "$B/uploads" "$REMOTE$DATE/uploads" --include "$(basename "$LATEST_UP")" $COMMON 2>&1 | tail -3 || FAIL=1

# --- verifica: checksum dei file cifrati su Drive ---
# cryptcheck confronta i checksum (MD5 di Drive) dei file cifrati con quelli locali
if ! rclone cryptcheck "$B/weekly" "$REMOTE$DATE/db" --include "*_${TS}.sql.gz" --one-way 2>&1 | tail -2; then FAIL=1; fi
if ! rclone cryptcheck "$B/uploads" "$REMOTE$DATE/uploads" --include "$(basename "$LATEST_UP")" --one-way 2>&1 | tail -2; then FAIL=1; fi

# --- disaster recovery: configurazione del server (nginx, cron, certificati, segreti, utenti MySQL, inventario)
#     e allegati di machineledger, non coperti dal backup-db.sh ---
SNAP_FILES=$(/root/server-config-snapshot.sh 2>/var/log/offsite-snapshot.err)
if [ -z "$SNAP_FILES" ]; then
  say "ERRORE: snapshot configurazione server non creato ($(tail -1 /var/log/offsite-snapshot.err 2>/dev/null))"; FAIL=1
else
  [ -s /var/log/offsite-snapshot.err ] && say "avvisi snapshot: $(tr '\n' ' ' < /var/log/offsite-snapshot.err)"
  SNAP_DIR=$(dirname "$(echo "$SNAP_FILES" | head -1)")
  for f in $SNAP_FILES; do
    rclone copy "$SNAP_DIR" "$REMOTE$DATE/config" --include "$(basename "$f")" $COMMON 2>&1 | tail -2 || FAIL=1
    if ! rclone cryptcheck "$SNAP_DIR" "$REMOTE$DATE/config" --include "$(basename "$f")" --one-way 2>&1 | tail -2; then FAIL=1; fi
  done
  say "Config server caricata: $(echo "$SNAP_FILES" | xargs -n1 basename | tr '\n' ' ')"
fi

# --- retention: elimina cartelle più vecchie di 28 giorni (definitivo) ---
rclone delete "$REMOTE" --min-age "${RETENTION_DAYS}d" --drive-use-trash=false 2>&1 | tail -2
rclone rmdirs "$REMOTE" --leave-root --drive-use-trash=false 2>&1 | tail -2

say "Cartelle presenti su Drive (cifrate/decifrate): $(rclone lsd "$REMOTE" 2>/dev/null | awk '{print $NF}' | tr '\n' ' ')"
say "Spazio usato: $(rclone size "$REMOTE" 2>/dev/null | tr '\n' ' ')"

if [ "$FAIL" -eq 0 ]; then say "OK"; ping_hc ""; exit 0; else say "ERRORE: controllare il log"; ping_hc "/fail"; exit 1; fi
