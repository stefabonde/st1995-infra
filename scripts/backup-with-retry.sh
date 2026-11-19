#!/bin/bash
# Backup notturno dei DB con un secondo tentativo automatico dopo 10 minuti.
# Avvisa su Telegram solo se il primo tentativo fallisce (esito del secondo).
# Esito in /var/lib/watchdog/backup-esito (letto dal rapporto delle 07:00).
# Cron: 0 4 * * * (al posto della chiamata diretta a backup-db.sh)

set -u
SCRIPT=/var/www/production/manualswebapp-prod/app/scripts/backup-db.sh
LOG=/var/log/manuals-backup-prod.log
ESITO=/var/lib/watchdog/backup-esito
mkdir -p /var/lib/watchdog

if "$SCRIPT" >> "$LOG" 2>&1; then
  echo "$(date +%Y%m%d) ok" > "$ESITO"; exit 0
fi

echo "[$(date '+%F %T')] backup fallito al primo tentativo: rilancio tra 10 minuti" >> "$LOG"
sleep 600
if "$SCRIPT" >> "$LOG" 2>&1; then
  echo "$(date +%Y%m%d) ok-al-secondo" > "$ESITO"
  /usr/local/bin/tg-notify "🔧 Backup notturno dei DB: il primo tentativo è fallito, il secondo è riuscito. Nessuna azione necessaria."
  exit 0
fi
echo "$(date +%Y%m%d) fallito" > "$ESITO"
/usr/local/bin/tg-notify "❌ Backup notturno dei DB FALLITO due volte. Vedere $LOG. Scrivimi: oggi non c'è un backup valido."
exit 1
