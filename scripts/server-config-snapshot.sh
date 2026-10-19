#!/bin/bash
# Fotografia della configurazione del server che NON sta su GitHub, per il disaster recovery.
# Crea in /root/server-snapshots: server-config_<ts>.tar.gz (config, .env, segreti, inventario)
# e machineledger-uploads_<ts>.tar.gz. Contiene segreti: cartella 700, i file vanno solo su Drive CIFRATO.
# Stampa i due percorsi creati (uno per riga). Tiene in locale solo gli ultimi 2 snapshot.
set -u
umask 077
OUT=/root/server-snapshots
TS=$(date +%Y%m%d_%H%M%S)
W=$(mktemp -d /root/.snapshot-work.XXXXXX)
mkdir -p "$OUT" "$W/_inventario"; chmod 700 "$OUT"
INV="$W/_inventario"

# ---- inventario (come era configurato il server) ----
{ lsb_release -ds 2>/dev/null; uname -r; docker --version; nginx -v 2>&1; certbot --version 2>&1; rclone version | head -1; } > "$INV/versioni.txt" 2>&1
crontab -l > "$INV/crontab-root.txt" 2>&1
ufw status verbose > "$INV/ufw-status.txt" 2>&1
fail2ban-client status > "$INV/fail2ban-status.txt" 2>&1
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}\t{{.Status}}' > "$INV/docker-ps.txt" 2>&1
docker images --format 'table {{.Repository}}\t{{.Tag}}\t{{.Size}}' > "$INV/docker-images.txt" 2>&1
docker network ls > "$INV/docker-networks.txt" 2>&1
docker volume ls > "$INV/docker-volumes.txt" 2>&1
dpkg-query -W -f='${Package} ${Version}\n' > "$INV/pacchetti-apt.txt" 2>&1
systemctl list-timers --all --no-pager > "$INV/timers.txt" 2>&1
ip -br addr > "$INV/rete.txt" 2>&1
{ echo "# modelli Ollama presenti (si riscaricano con: docker exec global-ollama ollama pull <nome>)"; docker exec global-ollama ollama list 2>/dev/null | awk 'NR>1{print $1}'; } > "$INV/ollama-modelli.txt"
# utenti MySQL e permessi (i dump dei singoli DB non li contengono): contiene hash delle password
ROOTPW=$(docker exec manualswebapp-db-prod printenv MYSQL_ROOT_PASSWORD 2>/dev/null)
if [ -n "$ROOTPW" ]; then
  # elenco utenti su file (il ciclo legge da fd 3: i docker exec interni non devono consumare lo stdin)
  docker exec manualswebapp-db-prod mysql -uroot -p"$ROOTPW" -N -e "SELECT CONCAT(user,'|',host) FROM mysql.user WHERE user NOT IN ('mysql.infoschema','mysql.session','mysql.sys','root')" 2>/dev/null > "$W/utenti.txt"
  while IFS='|' read -r -u 3 u h; do
    docker exec manualswebapp-db-prod mysql -uroot -p"$ROOTPW" -N -e "SHOW CREATE USER '$u'@'$h'; SHOW GRANTS FOR '$u'@'$h';" 2>/dev/null </dev/null | sed 's/$/;/'
  done 3< "$W/utenti.txt" > "$INV/mysql-utenti-e-permessi.sql"
  rm -f "$W/utenti.txt"
else
  echo "ATTENZIONE: password root MySQL non letta" > "$INV/mysql-utenti-e-permessi.sql"
fi
[ -s "$INV/mysql-utenti-e-permessi.sql" ] || echo "ATTENZIONE: nessun utente MySQL esportato" >&2

# ---- file di configurazione ----
FILES="/etc/nginx /etc/letsencrypt /etc/ufw /etc/fail2ban/jail.local /etc/fail2ban/jail.d /etc/cron.d /etc/docker \
/etc/logrotate.d/docker-containers /etc/systemd/journald.conf.d /etc/apt/apt.conf.d/52unattended-upgrades-local \
/etc/systemd/system/apt-daily.timer.d /etc/systemd/system/apt-daily-upgrade.timer.d /etc/ssh/sshd_config.d /etc/sysctl.d /root/.secrets"
DEPLOY=$(find /var/www/production -maxdepth 4 \( -name ".env" -o -name "parameters.yml" -o -name "docker-compose*.yml" \) -not -path "*/node_modules/*" -not -path "*/vendor/*" 2>/dev/null)
CFG="$OUT/server-config_$TS.tar.gz"
tar -czf "$CFG" --ignore-failed-read -C / $(for f in $FILES $DEPLOY; do echo "${f#/}"; done) -C "$W" _inventario 2>/dev/null
RC=$?

# ---- allegati machineledger (non coperti da backup-db.sh) ----
ML="$OUT/machineledger-uploads_$TS.tar.gz"
if [ -d /var/www/production/machineledger-prod/uploads ]; then
  tar -czf "$ML" -C /var/www/production/machineledger-prod/uploads . 2>/dev/null || RC=1
else
  echo "ATTENZIONE: uploads machineledger non trovati" >&2; ML=""
fi
rm -rf "$W"
# tieni solo gli ultimi 2 snapshot in locale
for pat in "server-config_*.tar.gz" "machineledger-uploads_*.tar.gz"; do ls -t $OUT/$pat 2>/dev/null | tail -n +3 | xargs -r rm -f; done
[ -s "$CFG" ] || exit 1
echo "$CFG"; [ -n "$ML" ] && echo "$ML"
exit $RC
