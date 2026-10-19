#!/bin/bash

# Rileva dinamicamente la cartella root del progetto
# (Dato che lo script si trova in app/scripts/, la root è due cartelle più su)
PROJECT_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# Configuration
BACKUP_DIR="$PROJECT_ROOT/backups"
ENV_SUFFIX="prod"
RETENTION_DAYS=7
# Copie a lunga scadenza: domenica -> settimanale, giorno 1 del mese -> mensile.
# Sono hardlink dei dump giornalieri (nessuno spazio extra finché il giornaliero esiste).
WEEKLY_RETENTION_DAYS=28
MONTHLY_RETENTION_DAYS=93
# Upload di manualsweb (allegati): archivio completo ogni domenica, ne teniamo 4.
UPLOADS_DIR="${UPLOADS_DIR:-$PROJECT_ROOT/../manualsweb-prod/uploads}"
UPLOADS_RETENTION_DAYS=28
# Minimo accettabile per considerare un dump valido (byte, dopo gzip): sotto questa
# soglia trattiamo il backup come fallito anche se i comandi non hanno ritornato errore.
MIN_BACKUP_SIZE=1024
# Database da salvare, tutti ospitati nello stesso container MySQL condiviso.
# Aggiungere qui i nomi degli altri DB quando i relativi applicativi vanno in produzione.
DATABASES=("manualsdb" "machineledgerweb_db" "cometo_db" "brc_db" "schenk_db" "tkse_torino_db" "timweb_db" "varinelli_db" "flexlink_db" "simagtorino_db" "erowa_db" "cefla_db" "ionefit_db" "falcon-conveyors_db" "st1995_it_db" "app_st1995_it_db" "bbwa_db")

mkdir -p "$BACKUP_DIR"

# Carica variabili da .env se presente (in particolare MYSQL_ROOT_PASSWORD e ENV_SUFFIX)
if [ -f "$PROJECT_ROOT/.env" ]; then
    export $(grep -v '^#' "$PROJECT_ROOT/.env" | xargs)
    ENV_SUFFIX="${ENV_SUFFIX:-prod}"
fi

if [ -z "$MYSQL_ROOT_PASSWORD" ]; then
    echo "❌ MYSQL_ROOT_PASSWORD non trovata in $PROJECT_ROOT/.env, impossibile fare il backup."
    exit 1
fi

CONTAINER_NAME="manualswebapp-db-$ENV_SUFFIX"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OVERALL_STATUS=0

for DB_NAME in "${DATABASES[@]}"; do
    BACKUP_FILE="$BACKUP_DIR/${DB_NAME}_$TIMESTAMP.sql.gz"

    echo "🚀 Starting backup of database '$DB_NAME' from container '$CONTAINER_NAME'..."
    echo "📂 Saving to: $BACKUP_FILE"

    # --no-tablespaces evita di richiedere il privilegio PROCESS (causa del bug
    # storico per cui il dump falliva silenziosamente pur senza dati utili).
    docker exec "$CONTAINER_NAME" mysqldump --no-tablespaces -uroot -p"$MYSQL_ROOT_PASSWORD" "$DB_NAME" 2>"$BACKUP_DIR/.last_error" | gzip > "$BACKUP_FILE"
    DUMP_STATUS=${PIPESTATUS[0]}

    if [ "$DUMP_STATUS" -ne 0 ]; then
        echo "❌ Backup di '$DB_NAME' fallito (mysqldump exit code $DUMP_STATUS):"
        cat "$BACKUP_DIR/.last_error"
        rm -f "$BACKUP_FILE"
        OVERALL_STATUS=1
        continue
    fi

    BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE")
    if [ "$BACKUP_SIZE" -lt "$MIN_BACKUP_SIZE" ]; then
        echo "❌ Backup di '$DB_NAME' sospetto: solo $BACKUP_SIZE byte (minimo atteso $MIN_BACKUP_SIZE). Tenuto per ispezione, ma segnalato come errore."
        OVERALL_STATUS=1
        continue
    fi

    echo "✅ Backup di '$DB_NAME' completato ($(du -h "$BACKUP_FILE" | cut -f1))"
done
rm -f "$BACKUP_DIR/.last_error"

echo "🧹 Cleaning up backups older than $RETENTION_DAYS days..."
for DB_NAME in "${DATABASES[@]}"; do
    find "$BACKUP_DIR" -name "${DB_NAME}_*.sql.gz" -mtime +"$RETENTION_DAYS" -delete
done

# --- Copie settimanali / mensili (hardlink dei dump di oggi) ---
DAY_OF_WEEK=$(date +%u)   # 7 = domenica
DAY_OF_MONTH=$(date +%d)
promote() {
    local DEST="$1"
    mkdir -p "$DEST"
    for DB_NAME in "${DATABASES[@]}"; do
        SRC="$BACKUP_DIR/${DB_NAME}_$TIMESTAMP.sql.gz"
        [ -f "$SRC" ] && ln -f "$SRC" "$DEST/"
    done
}
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    echo "📅 Copia settimanale in $BACKUP_DIR/weekly"
    promote "$BACKUP_DIR/weekly"
fi
if [ "$DAY_OF_MONTH" -eq 01 ]; then
    echo "🗓️  Copia mensile in $BACKUP_DIR/monthly"
    promote "$BACKUP_DIR/monthly"
fi
[ -d "$BACKUP_DIR/weekly" ] && find "$BACKUP_DIR/weekly" -name "*.sql.gz" -mtime +"$WEEKLY_RETENTION_DAYS" -delete
[ -d "$BACKUP_DIR/monthly" ] && find "$BACKUP_DIR/monthly" -name "*.sql.gz" -mtime +"$MONTHLY_RETENTION_DAYS" -delete

# --- Upload (solo la domenica) ---
if [ "$DAY_OF_WEEK" -eq 7 ]; then
    UPLOADS_BACKUP_DIR="$BACKUP_DIR/uploads"
    mkdir -p "$UPLOADS_BACKUP_DIR"
    if [ -d "$UPLOADS_DIR" ]; then
        UPLOADS_FILE="$UPLOADS_BACKUP_DIR/uploads_$TIMESTAMP.tar.gz"
        echo "🚀 Backup upload: $UPLOADS_DIR -> $UPLOADS_FILE"
        if tar -czf "$UPLOADS_FILE" -C "$UPLOADS_DIR" . 2>"$UPLOADS_BACKUP_DIR/.last_error"; then
            echo "✅ Backup upload completato ($(du -h "$UPLOADS_FILE" | cut -f1))"
        else
            echo "❌ Backup upload fallito:"
            cat "$UPLOADS_BACKUP_DIR/.last_error"
            rm -f "$UPLOADS_FILE"
            OVERALL_STATUS=1
        fi
        rm -f "$UPLOADS_BACKUP_DIR/.last_error"
        find "$UPLOADS_BACKUP_DIR" -name "uploads_*.tar.gz" -mtime +"$UPLOADS_RETENTION_DAYS" -delete
    else
        echo "⚠️ Cartella upload non trovata: $UPLOADS_DIR (backup upload saltato)"
        OVERALL_STATUS=1
    fi
fi

if [ "$OVERALL_STATUS" -eq 0 ]; then
    echo "✨ Tutti i backup completati con successo."
else
    echo "⚠️ Uno o più backup sono falliti, controllare il log sopra."
fi

exit $OVERALL_STATUS
