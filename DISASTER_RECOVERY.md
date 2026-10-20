# Disaster recovery – ricostruire tutto su un server nuovo

Ultimo aggiornamento: 19/10/2026. Server attuale: Hetzner 178.104.187.53 (Ubuntu, fuso UTC).
Questa guida NON contiene password: dove servono, indica dove trovarle.

## 0. Cosa è salvato e dove

| Cosa | Dove sta | Note |
|---|---|---|
| Codice applicazioni (manualsweb, manualswebapp, site, st1995-app, machine-ledger, appoffline) | GitHub (stefabonde/…) | tutto pushato; branch main = staging, prod via workflow |
| Dump DB (16 DB, giornalieri/settimanali/mensili) | server `/var/www/production/manualswebapp-prod/backups` + copia settimanale su Google Drive (cifrata) | Drive: da attivare (vedi §7) |
| Allegati manualsweb (uploads, ~850 MB) | idem, `uploads_*.tar.gz` | |
| Config server (nginx, letsencrypt, `/root/.secrets`, `.env`, parameters.yml, docker-compose, utenti MySQL, uploads machineledger) | `server-config_*.tar.gz` e `machineledger-uploads_*.tar.gz`, creati dallo script `scripts/server-config-snapshot.sh`, caricati su Drive insieme al backup | contiene segreti: solo su Drive cifrato |
| Script server, crontab, questa guida | cartella `infra/` (locale; vedi §8: da mettere in un repo privato) | |
| GitHub Secrets (REMOTE_HOST, SSH key, password DB, JWT, …) | NON leggibili da GitHub: inventario nel password manager | vedi §2 |
| `rclone.conf` (token Drive + password cifratura) | password manager + copia offline | senza questo i backup su Drive NON si aprono |

## 1. Account esterni da non perdere (con 2FA e codici di recupero)
GitHub, Hetzner, Cloudflare (DNS dei domini), registrar (Register), Google (Drive dei backup), password manager.

## 2. Inventario segreti da custodire nel password manager
- GitHub Secrets per ogni repo/ambiente: `*_REMOTE_HOST`, `*_REMOTE_USER`, chiave SSH di deploy (privata), password/nome/utente DB (PROD_ e STAGING_), `JWT_SECRET`, `INTERNAL_SYNC_SECRET`, `*_TENANT_DATABASES_YAML`, ecc. (elenco esatto: GitHub → repo → Settings → Secrets; annotarlo ora e tenerlo aggiornato)
- Token API Cloudflare (file `/root/.secrets/cloudflare*.ini`, anche nello snapshot)
- Password root MySQL (`MYSQL_ROOT_PASSWORD` nei `.env`, anche nello snapshot)
- `rclone.conf`
- Chiave SSH personale per accedere al server

## 3. Se cambi PC (il server non è toccato)
1. Installa git, Docker (opz.), rclone (`brew install rclone`).
2. Genera/ripristina la chiave SSH, aggiungila su GitHub e sul server (`~/.ssh/authorized_keys`), configura `~/.ssh/config` (host `github-personal`).
3. `git clone git@github-personal:stefabonde/<repo>.git` per i 6 repo.
4. Per leggere i backup da Drive: salva `rclone.conf` in `~/.config/rclone/rclone.conf` (da password manager), poi `rclone lsd gdrive-crypt:` e `rclone copy gdrive-crypt:<data>/uploads ~/ripristino-uploads`.

## 4. Server perso: ricostruzione completa
Tempo stimato: mezza giornata. Prima di iniziare abbassa il TTL dei record DNS A a 300 (se ancora possibile).

### 4.1 Nuovo server
1. Hetzner: crea server Ubuntu (stessa taglia o superiore), aggiungi la tua chiave SSH, abilita firewall: 22, 80, 443.
2. Aggiornamenti: `apt update && apt -y upgrade`; installa `docker.io docker-compose-plugin nginx certbot python3-certbot-dns-cloudflare python3-certbot-nginx fail2ban ufw unattended-upgrades rclone cron`; `ufw allow OpenSSH; ufw allow 80; ufw allow 443; ufw enable`.

### 4.2 Recupero backup
1. Su una macchina con rclone + `rclone.conf`: `rclone copy gdrive-crypt:<data più recente> ./ripristino` (contiene `db/`, `uploads/`, `config/`).
2. Copia sul server (`scp -r ripristino root@NUOVO:/root/`).

### 4.3 Configurazione server
1. `tar xzf server-config_*.tar.gz -C /root/ripristino-config` ed esamina il contenuto.
2. Ripristina: `/etc/nginx` (sites-available + link in sites-enabled), `/etc/letsencrypt` (certificati e rinnovi), `/root/.secrets`, crontab (`crontab-root.txt`), `/etc/logrotate.d`, `/etc/systemd/journald.conf.d`, sysctl/ssh drop-in.
3. Ricrea la rete Docker condivisa: `docker network create manualsnet; docker network create shared-ai-net`.
4. Se i certificati non si ripristinano: `certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare.ini -d '*.manualswebapp.it' -d manualswebapp.it …` (uno per dominio; i domini sono in `/etc/nginx/sites-enabled`).

Rate limit nginx e monitoraggio: copie di riferimento in `server-config/nginx/` (-> `/etc/nginx/conf.d/`) e `server-config/netdata/` (-> `/opt/netdata/`, poi `docker compose up -d`; pannello solo via tunnel SSH `ssh -L 19999:localhost:19999 root@<server>` -> http://localhost:19999). Le location con `limit_req` nei vhost (login, pdf/etichette, offline) sono nello snapshot nginx.

### 4.4 Applicazioni
Cartelle attese: `/var/www/production/{manualsweb-prod,manualswebapp-prod,site-prod,st1995-app-prod,machineledger-prod}` (+ staging se serve).
1. Posiziona i file `.env`, `parameters.yml`, `docker-compose*.yml` dallo snapshot (percorsi originali conservati).
2. Aggiorna i GitHub Secrets `*_REMOTE_HOST` con il nuovo IP, e metti la chiave pubblica di deploy in `authorized_keys` del nuovo server.
3. Rilancia i workflow di deploy (GitHub → Actions → Run workflow, o push su main) per ogni repo: ricostruiscono le immagini e avviano i container. Per il primo avvio dei container DB, se i workflow non lo fanno, `docker compose up -d` nelle cartelle.
4. Container Ollama (AI): `docker run -d --name global-ollama --network shared-ai-net -v ollama:/root/.ollama --restart unless-stopped ollama/ollama` e poi `docker exec global-ollama ollama pull <modello>` (il modello è in `OLLAMA_MODEL` nel `.env`). Poi reindicizza: `docker exec manualswebapp-app-prod node scripts/index-manual.js all-clients all` e `index-rapportini.js`.

### 4.5 Database
1. Con i container DB attivi, ricrea utenti e permessi: `docker exec -i manualswebapp-db-prod mysql -uroot -p<ROOT> < _inventario/mysql-utenti-e-permessi.sql`.
2. Per ogni dump in `db/`: crea il DB se manca e ripristina: `zcat <db>_<ts>.sql.gz | docker exec -i manualswebapp-db-prod mysql -uroot -p<ROOT> <db>`. DB attesi: `manualsdb` (login gestionale condiviso) + un `<cliente>_db` per ciascun cliente + DB del sito/st1995/machineledger secondo il set di 16 file.
3. Verifica con login a un gestionale e conteggio righe di qualche tabella.

### 4.6 Allegati
- manualsweb: estrai `uploads_*.tar.gz` nella cartella uploads dell'app (stesso percorso dell'archivio originale; controlla con `tar tzf` la radice) e verifica permessi per `www-data`.
- machineledger: estrai `machineledger-uploads_*.tar.gz` in `/var/www/production/machineledger-prod/uploads`.

- manualsweb, app offline: la cartella `/var/www/production/manualsweb-prod/manuale-offline` (programma Electron + risorse, ~200 MB) NON è in Git (.gitignore) e NON è nei backup, per scelta: si ricostruisce dal repo `appoffline`. Procedura: nel repo `npm install`, `npx vue-cli-service build`, poi `npx electron-builder --win dir -c.win.signAndEditExecutable=false` (da Mac; senza l'ultima opzione fallisce per rcedit/wine). Il risultato è in `dist_electron/win-unpacked`: copiarlo in `manuale-offline/` sul server con `resources/app/{dist,electron,...}` e `app-update.yml`, `elevate.exe`, `flags`, `sql.js` in `resources/`, e `chown -R www-data:www-data` (il controller scrive lì dentro). Verifica: `/download-offline/<azienda>/<id>` deve scaricare lo zip. Per aggiornare solo l'app basta sostituire `resources/app/dist` e `resources/app/electron/main.js` (copia di sicurezza fuori dalla cartella, perché viene zippata).

### 4.7 DNS e verifica
1. Cloudflare: punta i record A al nuovo IP (wildcard `*.manualswebapp.it` inclusa), TTL 300.
2. Controlli: `curl -I https://<cliente>.manualswebapp.it/`, login gestionale, un PDF (`/pdf/external/cometo/it/136/1`), `https://app.st1995.it/login`, sottodominio inesistente → 404 "Indirizzo non valido".
3. Reinstalla i cron (backup-db 04:00, indicizzazioni AI 02:00/03:30, prune Docker domenica 05:00, backup offsite domenica 06:00) e `fail2ban`.
4. Rilancia un backup e un offsite per verificare che la catena funzioni sul server nuovo.

## 5. Cose NON recuperabili dai backup (da rifare a mano)
- Repo/workflow GitHub non pushati (oggi tutto pushato: verificare `git status` prima di fidarsi).
- Segreti GitHub se non inventariati.
- Account esterni persi senza 2FA/recovery.

## 6. Test periodico consigliato
Almeno una volta (poi ogni 6 mesi): ripristino di prova su server Hetzner temporaneo (poche ore, pochi centesimi) seguendo questa guida, correggendo qui ciò che manca. Rimandato dall'utente a data da definire.

## 7. Stato backup offsite (19/10/2026)
- Cifratura rclone crypt su Google Drive: configurata. Blocco: quota API condivisa di rclone → serve ID client OAuth proprio (Google Cloud, Drive API, scope `drive.file`, app "In produzione"). In sospeso, riprendere la settimana del 26/10.
- Script pronti in `infra/scripts/` (`offsite-backup.sh` include lo snapshot config). Cron previsto: domenica 06:00 UTC, retention 4 settimane.

## 8. Da fare per rendere questa guida a prova di perdita PC
Questa cartella `infra/` esiste solo sul Mac e non è in un repo Git. Creare un repo GitHub **privato** (es. `st1995-infra`) e pushare `infra/` + `MIGRAZIONE_PRODUZIONE.md`. Nessun segreto contenuto (verificato sugli script).

## 9. Alert Netdata (Telegram)
Bot `st1995_server_alert_bot` (token in BotFather / password manager, NON in git). Config in `server-config/netdata/`: `health_alarm_notify.conf` (sostituire `__TOKEN__`) e `health.d/custom-*.conf` vanno in `/etc/netdata/` del container (volume `netdataconfig`), poi `docker exec netdata netdatacli reload-health`. Soglie (override in `health.d/custom-*.conf`): disco, RAM e CPU (media 10 min) avviso al 70%, critico al 90%; container fermo/unhealthy.
