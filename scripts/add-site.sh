#!/bin/bash
# add-site.sh - Aggiunge un nuovo sito Docker su Nginx e installa il certificato

if [ -z "$1" ] || [ -z "$2" ]; then
    echo "🔴 Uso palese: sudo ./add-site.sh <dominio.com> <porta_docker>"
    echo "Esempio: sudo ./add-site.sh mio-sito.it 8080"
    exit 1
fi

DOMAIN=$1
PORT=$2
CONF_PATH="/etc/nginx/sites-available/$DOMAIN"
LINK_PATH="/etc/nginx/sites-enabled/$DOMAIN"

echo "🟢 1. Creazione file per $DOMAIN sulla porta $PORT..."

# Scrive il file di configurazione
cat <<EOF > $CONF_PATH
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:$PORT;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
    }
}
EOF

echo "🟢 2. Abilitazione del sito..."
ln -sf $CONF_PATH $LINK_PATH

echo "🟢 3. Verifica Nginx e riavvio..."
nginx -t
if [ $? -eq 0 ]; then
    systemctl reload nginx

    echo "🟢 4. Generazione certificato SSL Let's Encrypt..."
    certbot --nginx -d $DOMAIN --non-interactive --redirect

    echo "✅ Fatto! Il sito è online in HTTPS: https://$DOMAIN"
else
    echo "🔴 Errore Nginx. Il sito NON è stato attivato."
fi
