# Piano di migrazione produzione: Plesk → Hetzner

Ultimo aggiornamento: 2026-10-16. Se riprendi questo lavoro senza il contesto della conversazione originale, leggi prima la checklist qui sotto — è pensata per essere autosufficiente.

---

## ⏩ RIPRENDERE DA QUI (stato al 09/10/2026, sera)

- **✅ 19/10 — NUOVO CLIENTE `bbwa` (B&B WATERJET ABRASIVE Srl) attivo in staging e PRODUZIONE** (manualsweb `1f94605`, manualswebapp `7438b3a`). Nome azienda riconosciuto da `waterjet` (non contiene "bbwa"): `ManualeListener`/`PdfEtichettaController` (manualsweb) e `companyNameMatch: ['bbwa','waterjet']` (manualswebapp). Sezioni manuale = standard 22 voci (come Cometo), manifest/icone predefiniti. Fatto: config.yml (gruppo_admin/manuale_bbwa), sonata_layout.html.twig (4 blocchi + CSS), UserAdmin (CLIENT_ROLE_KEYS + scelta ruoli), ManualeAdmin (2 elenchi ruoli), QR/etichetta; manualswebapp tenants.js/ts + `bbwa_db` in backup-db.sh. **`app:add-tenant`**: nuova opzione `--db-password` (stessa password su staging/prod, scritta in `tenants.js`; salvata in `/root/.secrets/bbwa-db.pass`, 600) e ora crea anche l'utenza **super admin nel DB condiviso `manualsdb`** (il login del gestionale avviene lì; mancava: "password errata" con password giusta). Script di appoggio in scratchpad: `bbwa-add-tenant.sh`, `bbwa-secret.sh` (blocco secret senza doppioni), `bbwa-manualsdb-user.sh` (solo per staging, già superato dal comando). Secret `STAGING_`/`PROD_TENANT_DATABASES_YAML` aggiornati dall'utente. Credenziali provvisorie già cambiate dall'utente. Guida: `manualsweb/ONBOARDING_NUOVO_CLIENTE.md` riscritta (punti hardcoded, doppia utenza, secret senza doppioni, guardia sottodomini). Backup notturno include `bbwa_db` dal 20/10.
- **✅ 19/10 — controllo post-weekend + 2 sistemazioni**: server ok (uptime 10gg, disco 50%/218GB liberi, tutti i container up, siti 200, 0 errori app 24h, aggiornamenti notturni ok senza reboot, backup notturni 16/16, backup domenica 18/10 ok: set weekly + `uploads_20261018` 848MB, prune Docker domenica ha liberato 61GB, indicizzazione AI ok, certificati 75-87gg, fail2ban attivo). (a) **st1995app main=staging (`a085f24a`) in prod**: `/` da non loggati dà 302 al login (non più 500: attivo `^/ ROLE_USER` in security.yml, era commentato in main), remember_me `%secret%`, rotazione log, Dockerfile archive.debian.org; verificato in prod. (b) **journald** limitato: `/etc/systemd/journald.conf.d/size.conf` `SystemMaxUse=200M`, `MaxRetentionSec=2month` (da 798MB a 182MB). Ancora aperti: backup offsite (Drive collega), UptimeRobot+healthchecks.io, cliente `bbwa`. Tutti i container PHP hanno ora rotazione log (`rotating_file` 7gg, solo errori).
- **✅ 16/10 sera — rilasciato in PRODUZIONE (manualsweb `55f7499` + manualswebapp `b3c737b`, main=staging)**: (1) **Mail ordinazione ricambi**: nuovo campo `manuale.mail_ordinazione_ricambi` (migration `Version20261016170000`, applicata a tutti i tenant), admin Sonata, segnaposto `##MAIL_ORDINAZIONE_RICAMBI##` sostituito in PdfExternalController (50 punti), api.js (3) e ManualViewer. Dati Cometo: script `cometo-mail-placeholder.sh` (preview/apply, backup) eseguito in prod: 49 manuali con `a.tocchetti@cometo.eu`, 109 paragrafi di `introduzione_translation` (le mail `a.colafabio`/`a.tocchetti`, testo+mailto) sostituiti col segnaposto; backup `/root/cometo-mail-placeholder-prod-20261016_155020.sql.gz`; PDF prod man. 136 verificato. Per altri clienti: scrivere il segnaposto nell'editor + compilare il campo. (2) **Copertina PDF**: margini ridotti (`ANNO` resta in pagina 1). (3) **Homepage manualswebapp**: «Data e versione» sotto il nome del manuale, solo se valorizzata, per tutti i clienti. (4) **Guardia sottodomini** (`middleware/tenantHost.js`): `*.manualswebapp.it` e `*.manualswebapp.stagingrail.com` accettano solo sottodomini in `config/tenants.js` (+alias, `www`, apex); gli altri → 404 con pagina «Indirizzo non valido» (JSON per /api). Provato in prod: pippo→404, clienti/www/apex→200. (`a.b.` fallisce al TLS: wildcard a un livello.) Fresia (subdomain null) ora non passa.
- **📌 NUOVO CLIENTE `bbwa` (da fare)**: oltre ai passi di `manualsweb/ONBOARDING_NUOVO_CLIENTE.md` (`app:add-tenant bbwa`, secret `*_TENANT_DATABASES_YAML`, `tenants.js`/`tenants.ts` in manualswebapp, `bbwa_db` in `backup-db.sh`) NON in guida ma necessari nel gestionale manualsweb: `app/config/config.yml` blocchi `gruppo_admin_bbwa` e `gruppo_manuale_bbwa` (menu/sezioni, copiare da cliente modello es. cometo), `sonata_layout.html.twig` 2 blocchi `elseif` (ROLE_BBWA_SUPER_ADMIN / SONATA_ADMIN) + CSS, `UserAdmin.php` `CLIENT_ROLE_KEYS`, `ManualeListener.php` (URL QR code) e `PdfEtichettaController.php` (sottodominio etichetta). Dopo il deploy di `tenants.js` il sottodominio `bbwa.manualswebapp.it` diventa raggiungibile (la guardia lo blocca prima). Servono: nome azienda, cliente modello per le sezioni, logo/icone (opzionale). Password root MySQL non in chat.
- **16/10 sera — log Symfony + fix Dockerfile (da chiudere)**: `app/config/config_prod.yml` di manualsweb, site, st1995app → `fingers_crossed` `action_level: error`, `excluded_404s: ['^/']` (NB: `excluded_http_codes` NON esiste in Symfony 3.4: rompe cache:clear, già corretto), `nested` = `rotating_file` `max_files: 7`. Motivo: `site-app-prod` aveva `var/logs/prod.json` da 735MB (dal 17/06, action_level info), manualsweb 13MB in 3 gg. Fix **Dockerfile** dei 3 progetti PHP (`php:7.4-apache` = Debian 11 EOL: `deb.debian.org` dava 404 sui .deb → build falliva): `sed` delle sources su `archive.debian.org` + `Check-Valid-Until false` (provato su container usa e getta). Stato: site main=staging (`6b26fd8`), manualsweb main=staging (`308f4c2`), **st1995app solo staging (`a085f24a`) — main NON toccato (2 commit «fix» in staging non ancora in prod, da decidere con l'utente)**. Remote di site e st1995app cambiati da HTTPS a SSH (`git@github-personal:`). **DA VERIFICARE (17/10)**: deploy finiti, container ricreati (manualsweb-app-prod era ancora del 13/10), config senza errori (`php bin/console about --env=prod`), file `var/logs/prod-AAAA-MM-GG.json` presente, siti 200. Nota: `app.st1995.it` dà 500 su `/` da non loggati (`TimeSpentRepository::getWeekSpent()` con User null, DefaultController r.18): preesistente, da valutare.
- **📌 PROSSIMA SETTIMANA — monitoraggio/alert (gratis)**: (1) utente crea account **UptimeRobot** + **healthchecks.io** (io non posso registrare account); (2) UptimeRobot: monitor HTTP su manualsweb.it, www.manualswebapp.it, st1995.it, app.st1995.it, machine-ledger + scadenza certificati; (3) script bash in cron ogni 15 min sul server (disco >80%, memoria, container fermi, backup notturno vecchio/fallito, `/var/run/reboot-required`) che pinga healthchecks.io (/fail con dettaglio; assenza di ping = server giù); URL di ping salvati su server via `pbpaste|ssh` in `/root/.secrets/`, mai in chat; (4) stessi ping per backup offsite. Scelta: niente container di monitoraggio sullo stesso server (muore con lui); Netdata solo se servono grafici storici. Insieme al backup offsite su Google Drive del collega (vedi voce sopra, guida già pronta).
- **16/10 — fix doppia codifica `cometo_db`**: campo `manuale_translation.area_di_lavorazione` aveva testo UTF-8 ri-codificato (Ø→`Ã˜`, ÷→`Ã·`) in 62 righe, già presente nel dump Plesk (non causato dalla migrazione; ereditato da manuali clonati). Corretto in prod con `CONVERT(CAST(CONVERT(col USING latin1) AS BINARY) USING utf8mb4)` solo sulle righe con byte C3 83/C3 82 e conversione lossless; 62 aggiornate, 0 residue; backup pre-fix `/root/manuale_translation_cometo_prefix-20261016_144739.sql.gz`. Altri tenant DB: 0 righe affette. Origine della scrittura errata non trovata: se ricompare su manuali nuovi, indagare.
- **16/10 sera — firewall + offsite backup (stato)**: firewall Hetzner `firewall-1` confermato dall'utente (inbound solo TCP 22/80/443, outbound tutto, applicato a 1 risorsa). Verificato via ssh: sshd `passwordauthentication no`, `permitrootlogin prohibit-password`; fail2ban sshd attivo (215 ban totali); le porte Docker 3000/3001/5002/5003/8080-8085 sono pubblicate su 0.0.0.0 ma bloccate dal firewall Hetzner, 3306 non in ascolto (opzionale: legarle a 127.0.0.1). 2FA già attiva sugli account (Hetzner/CF/GitHub, confermato dall'utente). **Backup offsite: RIMANDATO a settimana prossima** (decisione utente). Scelta: rclone → Google Drive **di un collega** (non dell'utente), cifrato con rclone crypt, domenica 06:00 UTC, retention 4 settimane. Pronti: rclone 1.60.1 installato sul server, `/root/offsite-backup.sh` (chmod 700, NON schedulato, richiede i remote `gdrive` e `gdrive-crypt` non ancora creati), guida per il collega https://claude.ai/artifact/9s93GiNdzSurHfAtczLq3b. Da fare: sessione di ~10 min col collega (`rclone authorize "drive"` sul suo PC, token incollato nel prompt di `ssh -t root@178.104.187.53 rclone config`, scope `drive.file`; poi `gdrive-crypt` su `gdrive:backup-hetzner`), salvare `rclone.conf` (chiavi di cifratura) nel password manager dell'utente, test manuale, cron + eventuale ping healthchecks.io (`HC_URL` in `/root/.secrets/offsite.env`).
- **st1995.it + www + app: MIGRATI su Hetzner** (09/10). Cert LE ok, DB del sito sistemato (vedi sotto). Posta M365 intatta.
  - ⚠️ **DA FARE (utente)**: aggiornare secret GitHub repo `st1995-site`: `PROD_DATABASE_USER=st1995`, `PROD_DATABASE_PASSWORD` = valore in `/root/.secrets/site-prod-db.env`. Poi eventualmente rilanciare il deploy main e ricontrollare il sito.
- **16/10 mattina — dopo il flip**: (1) merge+push main di manualswebapp con `backup-db.sh` nuovo (`7ad7638`, main=staging) deployato; backup lanciato a mano: 16/16 DB OK (inclusi st1995_it_db e app_st1995_it_db). Ramo domenica/primo-mese provato con copia dello script (DAY_OF_WEEK=7, DAY_OF_MONTH=01): weekly/ 16 file, monthly/ 16 file, uploads/ tar 805MB → funzionano (resta un set weekly+monthly+uploads del 16/10 di prova, valido). (2) Hardening verificato: ufw attivo (22/80/443), porte Docker/MySQL NON raggiungibili da internet (nc dall'esterno), SSH solo chiave, fail2ban + unattended-upgrades attivi, 45 pacchetti in sospeso, nessun reboot richiesto. Bot: scansioni /.env, /.git/config da 34.152.4.105 e altri → tutti 404. Resta: firewall Hetzner Cloud (da console), Cloudflare proxy (passo separato). (3) Resta da fare: pulizia credenziali (password MySQL st1995 + secret GitHub; Roll token CF → AGGIORNARE `/root/.secrets/cloudflare-prod.ini` altrimenti il rinnovo certbot di gennaio fallisce; Global API Key; file FTP Plesk solo alla dismissione), backup offsite, zona CF st1995.it, 45 aggiornamenti apt.
- **16/10 — credenziali**: token CF `migrazione-hetzner` (id 7cc7ea9f…) ruotato con Roll dall'utente e aggiornato su `/root/.secrets/cloudflare-prod.ini` (via pbpaste|ssh con validazione API, valore mai in chat; primo tentativo aveva scritto per errore il testo del comando → corretto al secondo). Token verificato active, vede solo manualsweb.it/manualswebapp.it. Dry-run rinnovo manualswebapp.it OK; manualsweb.it in verifica. Token staging `cloudflare.ini` (id 766ac89a…): da chiarire se passato in chat. Zona CF `st1995.it`: già inesistente (verificato nella lista domini: restano manualswebapp.it, manualsweb.it, stagingrail.com). Apt: 45 aggiornamenti non di sicurezza (apparmor, netplan, grub, …), nessuno critico → rimandati a finestra tranquilla. Restano: Global API Key (utente), password MySQL st1995 + secret GitHub, firewall Hetzner Cloud, backup offsite.
- **Decisione utente 16/10: cambio password MySQL `st1995` RIMANDATO** (DB non sensibile, 3306 non esposta). Se mai: usare `ALTER USER … RETAIN CURRENT PASSWORD` → aggiornare secret GitHub `PROD_DATABASE_PASSWORD` di st1995-site (valore via `ssh … | pbcopy`, password esadecimale) → Re-run workflow deploy → `DISCARD OLD PASSWORD`. La password vive in: MySQL, `/var/www/production/site-prod/.env`, parameters.yml dentro il container, secret GitHub. Global API Key CF già cambiata dall'utente il 16/10.
- **16/10 — aggiornamenti notturni**: server in UTC (Italia = +2h). Creati `/etc/apt/apt.conf.d/52unattended-upgrades-local` (aggiunge origine `-updates`, Automatic-Reboot-Time 01:00; Docker/containerd esclusi), override timer `apt-daily.timer.d` (00:00 e 12:00) e `apt-daily-upgrade.timer.d` (00:30 UTC). Prossimo giro sab 17/10 00:32 UTC; riavvio solo se serve (01:00 UTC, prima di backup 04:00 e indexing 02:00). Dry-run: installerebbe i 45 pacchetti (apparmor, netplan, grub, cloud-init…). Backup config originale `/root/50unattended-upgrades.bk-20261016`. Rollback: cancellare i 3 file e `systemctl daemon-reload`. Da controllare dopo il primo giro: `/var/log/unattended-upgrades/unattended-upgrades.log`. Dry-run certbot rinnovo manualsweb.it e manualswebapp.it OK col token nuovo.
- **Decisioni utente 16/10 (sera)**: token CF di staging (`cloudflare.ini`) lasciato com'è per ora; firewall Hetzner Cloud già presente (nulla da fare). RESTANO: (a) backup offsite (Storage Box/S3) da decidere; (b) controllare sab 17/10 il log `/var/log/unattended-upgrades/` e dom 18/10 i backup (primo giro weekly+uploads); (c) Cloudflare proxy opzionale (passo separato); (d) dismissione Plesk dopo 2-4 settimane stabili: conservare dump `tkse_db`, cancellare `/root/.secrets/plesk-ftp*.env`, poi Roll/cleanup residui.
- **✅ 16/10 ~08:43 FLIP FATTO**: record A su CF (API, il click da Chrome falliva per conflitto estensione con il pannello Edit aperto) `manualsweb.it`, `manualswebapp.it`, `*.manualswebapp.it` → 178.104.187.53 (erano 176.221.55.118; ids: e35b6efc… / 1a5c8345… / f5670c23…). DNS-only, TTL auto (300s). Propagato su CF/1.1.1.1/8.8.8.8. Test: tutti i domini e 12 sottodomini tenant 200/302, cert valido, nessun errore nginx/app. ROLLBACK = rimettere A a 176.221.55.118 (Plesk intatto). Prossimo: monitoraggio, test funzionale utente, poi lista "COSE DA FARE DOPO IL PASSAGGIO".
- **16/10 Giorno X — import dump**: dump (cartella locale `dump-db/`, sul server `/root/plesk-import/2026-10-16/`) importati con `run-import-20261016.sh` (13 tenant + manualsdb, log `import-prod-20261016.log`); allegati con `sync_plesk_uploads.sh` (log `sync-prod-20261016.log`). ESCLUSI: `st1995_it_db` (Hetzner più aggiornato del dump Plesk: service 5 vs 4, service_translation 7 vs 5, machine 1 vs 0), `app_st1995_it_db` (già identico per conteggi), `leonardo_db` (vuoto), `tkse_db` (cliente vecchio, forse non serve più: decisione utente 16/10; tenere il dump 250MB come archivio prima di dismettere Plesk). Su Plesk cambiati rispetto al 05/10 solo cometo, manualsweb_db, simagtorino.
- **📋 COSE DA FARE DOPO IL PASSAGGIO (lista unica, 16/10)**:
  1. **Push/merge script backup**: commit `7ad7638` su `staging` di manualswebapp (`scripts/backup-db.sh`: +st1995_it_db/app_st1995_it_db, copie settimanali/mensili, tar upload). Pushare staging, poi merge → main (il deploy riavvia il container app); lanciare lo script una volta a mano e verificare i 16 DB + cartelle weekly/monthly/uploads.
  2. **Pulizia disco**: build cache Docker = 320GB (306GB recuperabili), vedi sotto; `docker builder prune`; valutare cron mensile. Disco 83%.
  3. Hardening server (firewall, SSH key-only + fail2ban, aggiornamenti automatici).
  4. Backup offsite (Storage Box/S3): DA DECIDERE con l'utente (costo).
  5. Snapshot/Backups Hetzner Cloud: verificare nella console se attivi.
  6. Cloudflare proxy (opzionale, passo separato — timeout 100s vs PDF 120s, nginx real_ip, chiusura IP origine).
  7. Pulizia credenziali: cambio password MySQL `st1995`, Roll token CF + Global API Key, cancellare `/root/.secrets/plesk-ftp*.env`, zona CF `st1995.it` inutilizzata.
  8. Verificare `brc_db` (9.5K) e `machineledgerweb_db` (12K) quasi vuoti; Plesk dismesso dopo 2-4 settimane stabili.
- **Pulizia disco eseguita 16/10**: `docker builder prune -f --filter until=168h` → recuperati ~119GB, disco 358GB→239GB (83%→56%, 194GB liberi). Restano ~190GB di build cache (ultima settimana). **Ollama è USATO**: embeddings (`/api/embed`) dal cron di indicizzazione `index-manual.js` (02:00 prod) e chatbot → NON rimuovere. Log: nessuna rotazione configurata (json-file illimitato, niente `/etc/docker/daemon.json`); `global-ollama` ha un log da 1.5GB. TODO: `log-opts max-size/max-file` (daemon.json richiede restart docker; oppure `logging:` nei compose, effettivo al prossimo `up -d`) e prune cache schedulato (cron settimanale `docker builder prune -f --filter until=168h`).
- **Pulizia disco 16/10, esito finale**: disco 358GB→226GB (83%→53%, 207GB liberi). Cron root domenica 05:00 `docker builder prune -a -f --filter until=24h` (log `/var/log/docker-prune.log`, backup crontab `/root/crontab.bk-20261016`); logrotate `/etc/logrotate.d/docker-containers` (daily, 3 rotazioni, maxsize 50M, copytruncate, nessun restart); log ollama troncato (1.5G→0). Restano ~174GB di build cache considerata "recente" da Docker (<24h): `docker builder prune -a -f` senza filtro la libererebbe, costo = deploy successivo più lento (rebuild layer da zero). Non urgente.
- **Analisi disco (16/10)**: 358GB usati su 451. `/var/lib/containerd` = 320GB → **build cache Docker 320GB (424 voci, 306GB recuperabili)**; immagini attive 12 (~38GB reali); volumi 20GB (MySQL); `/var/www` 11GB; log 747MB. Non è dati: è cache di build accumulata dai deploy. `docker builder prune` non tocca immagini, container né volumi.
- **DA FARE dopo il passaggio (decisione 16/10)**: hardening server Hetzner — firewall (Hetzner/ufw: solo 22/80/443), SSH solo con chiave + fail2ban, aggiornamenti automatici di sicurezza, backup DB (vedi sotto). Poi, come passo separato, valutare Cloudflare in proxy (attenzione: timeout 100s vs PDF 120s, nginx real_ip, chiusura accesso diretto all'IP origine). Cloudflare SSL Full(strict)/Always HTTPS/TLS1.2 già impostati su entrambe le zone il 16/10.
- **Backup Hetzner verificati (16/10 via ssh, regola permessi aggiunta dall'utente)**: cron root `0 4 * * *` → `/var/www/production/manualswebapp-prod/app/scripts/backup-db.sh`, log `/var/log/manuals-backup-prod.log`, 14 DB OK ogni notte, retention 7gg, 6.6GB in `.../manualswebapp-prod/backups` (stesso server, disco 83% = 75GB liberi). LACUNE: `st1995_it_db` NON incluso nello script; nessuna copia offsite; `uploads/` non incluso; nessun backup mensile/settimanale. brc_db (9.5K) e machineledgerweb_db (12K) sono quasi vuoti: verificare se è normale.
- **Backup — modifiche pronte (16/10)**: commit su `staging` di manualswebapp (NON pushato, NON su main): `scripts/backup-db.sh` aggiunge DB `st1995_it_db` + `app_st1995_it_db`, copie settimanali/mensili (hardlink) e tar degli upload di manualsweb ogni domenica (ultimi 4). Va in prod con il merge staging→main di manualswebapp DOPO il passaggio (il deploy riavvia il container app). Dopo il primo deploy: lanciare lo script a mano una volta e verificare. Punto 3 (copia offsite, Storage Box/S3): da decidere dall'utente.
- **15/10 sera — NS cambiati, zone CF Active, B2 cert FATTI**: certificati LE emessi (DNS-01, propagation 60s, scadenza 2027-01-13): `manualswebapp.it` (+ `*.manualswebapp.it`) e `manualsweb.it` (+ www) in `/etc/letsencrypt/live/<nome>/`. Con propagation 10s il primo tentativo era fallito (secondary validation). **Vhost 443 ATTIVATI 15/10** (backup `/etc/nginx/sites-available/prod-manualsweb{,app}.pre-ssl`; diff verificato: solo 443 + X-Forwarded-* + redirect 80→301; test locale con --resolve: manualsweb.it 302→/login, manualswebapp.it e cometo.manualswebapp.it 200, cert verificati). PROSSIMO: A5 (CF SSL Full strict, Always HTTPS, Min TLS 1.2 — da dashboard, il token non ha permessi) → A7 test browser con /etc/hosts → giorno X (dump DB freschi, sync allegati, flip IP).
- **15/10 — export zone Register ricevuto (screenshot + TXT)**: confrontato con CF. manualswebapp.it: tutto coperto (wildcard `*` A). manualsweb.it: su Register ci sono ~69 record in più rispetto a CF (`authsmtp` e ~66 CNAME vecchi tenant leonardo/cometo/schenck/varinelli…): **decisione utente 15/10: non servono** (manualsweb.it è solo gestionale, niente sottodomini; la posta non è usata su manualsweb/manualswebapp, solo su st1995.it che è già altrove). Nessun import in CF necessario. Zone CF = Register per tutto ciò che serve → **via libera al cambio NS dato** (da comunicare all'azienda).
- **manualsweb.it + manualswebapp.it**: in attesa che l'azienda cambi i NS a Cloudflare. Il 09/10 l'azienda ha chiesto conferma (Register cancella le zone al cambio): zone confrontate (CF = Register, esclusi 4 vecchi sottodomini Plesk di manualsweb.it), backup in `dns-backup-register-20261009.txt`. Risposta inviata chiedendo **export/screenshot delle zone Register** → quando arriva: confrontarlo col backup e con CF, poi dare il via.
- Dopo il cambio NS (zone CF "Active"): B2 (cert DNS-01 + vhost 443 in `/root/nginx-ssl-ready/`) → A5 → giorno X (B4–B6).
- **Plesk, hotfix 08/10**: `/app/routes/api.js` della sottoscrizione manualswebapp.it patchato (link allegati fissi a `https://www.manualsweb.it`, prima sui sottodomini diventavano `https://<tenant>/...`). Backup `/app/routes/api.js.bk-20261008`; originale e copia sorgente Plesk in `/root/plesk-import/manualswebapp-plesk-20261008/`. FTP sottoscrizione app in `/root/.secrets/plesk-ftp-app.env`. NB: il codice Node su Plesk diverge da `main` (server.js, auth.js, ai.js, database.js; manca config/tenants.js) → mai copiarci file di main.
- Azioni bloccate dal classificatore auto mode (push main, certbot, scritture in prod/Plesk, password DB): preparare il comando/script e farlo lanciare all'utente con `!`.

## 📍 DOVE SIAMO (29/09/2026) — storico

**Obiettivo**: il giorno X, alla stessa ora, **tutti e 3 i domini** (manualsweb.it, manualswebapp.it, st1995.it + app.st1995.it) passano da Plesk a Hetzner **insieme**.
- manualsweb.it + manualswebapp.it → DNS su Cloudflare; il giorno X cambiamo noi l'IP su Cloudflare.
- st1995.it → DNS resta dall'azienda (per la posta Microsoft 365, niente Cloudflare), ma il sito **si sposta lo stesso**: il giorno X l'azienda cambia 3 record (st1995.it, www, app → 178.104.187.53).

**In attesa di**: l'utente manda (29/09) la mail all'azienda che gestisce i domini, con:
1. subito: NS di manualsweb.it e manualswebapp.it → `jade`/`martin.ns.cloudflare.com` (non sposta nulla, i record CF puntano ancora a Plesk);
2. giorno X concordato: i 3 record di st1995.it, lasciando intatti MX/SPF/autodiscover/ftp;
3. avvisarci a punto 1 fatto, proporre giorno/ora, non cancellare zone/Plesk.
Al 29/09 i NS sono ancora `ns1/ns2.plaindns.net` su tutti e 3.

**05/10/2026**: NS ancora plaindns su tutti e 3. Importati in prod (`manualswebapp-db-prod`) i 13 dump Plesk del 05/10 (cartella locale `bk-db/`, sul server `/root/plesk-import/2026-10-05/`, log `/root/plesk-import/import-prod-20261005.log`); `manualsweb_db` → `manualsdb`; `leonardo_db` saltato (vuoto su Plesk, 0 tabelle). Backup dei DB prod pre-import in `/root/plesk-import/pre-import-20261005/`. Upload risincronizzati il 05/10 (8 file nuovi, 883MB, log `/root/plesk-import/sync-prod-20261005.log`). Zone CF verificate il 05/10: esistono, "pending", NS jade/martin — mail per il cambio NS inviata dall'utente il 05/10. Al giorno X servirà comunque un altro export fresco.

**DECISIONE 05/10 (supera "giorno X insieme" per st1995)**: st1995.it + www + app si spostano **SUBITO**, non al giorno X (sito statico, dati non urgenti; unico vincolo: la posta M365 deve restare intatta). Mail inviata all'azienda il 05/10 con: (1) NS manualsweb/manualswebapp → jade/martin; (2) i 3 record st1995 → 178.104.187.53 senza toccare MX, TXT (SPF + MS=ms97421390), CNAME autodiscover, SRV `_autodiscover._tcp` → `ms-it.securemail.pro`, ftp. Al 05/10 17:05 nessun cambio fatto. **06/10: ancora nessun cambio** (NS plaindns sul registro .it per tutti e 3; st1995/www/app ancora → 176.221.55.118; MX/TXT/autodiscover/SRV invariati). **07/10: ancora nessun cambio** (stessa verifica, anche interrogando direttamente il registro .it e ns1.plaindns.net). **08/10 15:09: ancora nessun cambio** (stesse verifiche: NS plaindns sul registro .it, record st1995 → 176.221.55.118, posta M365 invariata). **09/10 ~17:40: l'azienda ha cambiato i 3 record di st1995.it** → st1995/www/app = 178.104.187.53 (TTL 900), ftp/MX/TXT/autodiscover/SRV invariati (verificato). HTTP 200 su Hetzner; **09/10 certbot --nginx fatto** (cert LE st1995.it+www+app, scade 2027-01-07, rinnovo automatico; deployato in prod-site e prod-st1995-app): HTTP→301 HTTPS, HTTPS 200 su tutti e 3 (app/ = 500 come già su Plesk, /login 200). **st1995 MIGRATO.** 09/10 pomeriggio: st1995.it mostrava "Access denied for user ''" → secret GitHub PROD_DATABASE_USER del repo st1995-site conteneva una password (con `#`, in YAML diventa vuoto) e la password non era quella di `st1995`. Fix: nuova password (hex) a st1995@% in manualswebapp-db-prod, parameters.yml del container + .env aggiornati (backup /root/site-prod-*.bk-20261009-155029), valori in `/root/.secrets/site-prod-db.env`. **DA FARE: aggiornare i secret GitHub PROD_DATABASE_USER=st1995 / PROD_DATABASE_PASSWORD del repo st1995-site**, altrimenti il prossimo deploy prod rompe di nuovo. L'azienda chiede conferma prima del cambio NS di manualsweb/manualswebapp (Register cancella le zone): confronto zone fatto il 09/10, backup in `dns-backup-register-20261009.txt`. **Quando l'utente avvisa**: verificare `dig A st1995.it` → 178.104.187.53, poi `certbot --nginx -d st1995.it -d www.st1995.it -d app.st1995.it`; verificare MX invariato. app.st1995.it su Hetzner ha dati staging di agosto (eventuale export Plesk dopo, non urgente). manualsweb/manualswebapp restano con il giorno X (flip IP su CF) dopo B2/A7.

**Prossimo passo quando l'azienda conferma il punto 1** (zona CF "Active"): B2 = certbot DNS-01 per manualsweb.it e manualswebapp.it (+wildcard) → attivare i vhost pronti in `/root/nginx-ssl-ready/` (README coi comandi) → impostare CF SSL Full (strict).

**Giorno X** (sequenza B4→B7): export DB da Plesk ("Esporta dump", lo fa l'utente — 14 DB manualsweb; per app.st1995.it/st1995.it chiarire se servono, sono in un'altra sottoscrizione non visibile dal nostro FTP) → io li scarico via FTP e importo → sync finale upload → flip IP su CF + l'azienda cambia i record st1995 → certbot --nginx per st1995 → test.

**Domande aperte per l'utente**: app.st1995.it su Plesk è usata (dati nuovi dopo agosto)? Chi ha ricreato le zone CF il 23/09 (irrilevante, solo per sapere)?

**Da fare a fine migrazione**: cambiare la password MySQL di `st1995` (prod, passata in chat il 09/10) e aggiornare secret GitHub + `/root/.secrets/site-prod-db.env`; Roll token Cloudflare (passato in chat) e aggiornare `/root/.secrets/cloudflare-prod.ini`; cancellare `/root/.secrets/plesk-ftp.env` e `/root/.secrets/plesk-ftp-app.env` (FTP sottoscrizione manualswebapp.it, aggiunto 08/10) alla dismissione di Plesk; rigenerare Global API Key CF; cancellare zona CF `st1995.it` inutilizzata (se ancora esiste).

---

## ✅ CHECKLIST OPERATIVA (aggiornata 2026-09-25)

Il cambio DNS lo esegue l'azienda che gestisce i domini (via libera dato dall'utente il 25/09). Tutto quello che non dipende dal DNS va chiuso **prima**.

**Decisione 25/09: `st1995.it` resta FUORI da Cloudflare** (per non rischiare nulla sulla posta Microsoft 365). Il DNS resta su plaindns (`ns1/ns2.plaindns.net`); si cambiano solo i record web verso Hetzner. Cloudflare solo per `manualsweb.it` e `manualswebapp.it`. La zona `st1995.it` su Cloudflare (id `395ea28ff0279ec5666abc82efe9df14`) resta "pending" e inutilizzata → si può cancellare.

### Controlli già fatti il 25/09
- DNSSEC: **non attivo** su nessuno dei 3 domini (nessun record DS) → il cambio NS non richiede di disattivarlo prima.
- Zona `st1995.it` su plaindns (TTL 900s = 15 min): `st1995.it` A → 176.221.55.118; `www`, `app` (e `ftp`) sono **CNAME → `plesk.areasispac.it`** (→ `posta.areasispac.it` → 176.221.55.118). La posta è su Microsoft 365 (MX/SPF/autodiscover) e non si tocca.
- Hetzner risponde in HTTP (porta 80) con Host reale: 200 su tutti gli host. `app.st1995.it/` dà 500 sulla home ma **lo fa identico anche su Plesk** (è un comportamento esistente, `/login` = 200).
- ⚠️ **HTTPS (443) su Hetzner per questi 4 domini (risolto per manualsweb/manualswebapp con A3-A4; per st1995 con certbot dopo il cambio) oggi risponde machine-ledger** (vhost di default, cert `machineledgerweb.com`, `X-Powered-By: Express`). Se al cutover Cloudflare è in modalità SSL "Full"/"Full (strict)" senza i blocchi SSL già attivi, **gli utenti vedrebbero machine-ledger**. I blocchi `listen 443` vanno messi **prima** del cambio NS.

- ⚠️ **`manualsweb.it` su Hetzner oggi mostra la pagina "Welcome to nginx"**: in `sites-enabled/` `prod-manualsweb` (e `manualsweb.stagingrail.com`) sono **copie** e non symlink, ferme al 04/08 con il dominio placeholder `quello-che-vuoi-tu.it`. La versione corretta (07/08, con `manualsweb.it` + rate-limit su `/login`) è in `sites-available/` ma non è mai stata attivata. Però la versione in `sites-available` **non ha `client_max_body_size 100m`** → va aggiunto prima di fare il symlink, altrimenti gli upload >1MB falliscono (413).
- Versioni in produzione su Hetzner allineate a `main`: manualsweb 24/09, manualswebapp 10/09, site 17/06, st1995-app 06/08 (date di creazione dei container).

- L'FTP `admin_st1995` è la sottoscrizione Plesk di **manualsweb.it** (`httpdocs/` = manualsweb). st1995.it e app.st1995.it sono in un'altra sottoscrizione, non visibile da questo FTP.
- Su Plesk esistono 4 siti-sottodominio (`cometo.mtf55-2-104`, `cometo.mtf77-102`, `cometo.svo1000h5pnbc5-061`, `orm.2912-23` .manualsweb.it): contengono **solo la pagina di default di Plesk** → non si migrano, dopo il cambio NS smetteranno di risolvere (nessun impatto).
- **Export DB da Plesk**: Plesk → Database → (DB) → "Esporta dump" salva lo zip nella home FTP (`/<db>_<data>.sql.zip`, vedi quelli del 06/08). Da lì si scaricano via FTP direttamente sul server Hetzner con lftp (credenziali in `/root/.secrets/plesk-ftp.env`), senza passaggi a mano.

### Zone Cloudflare attuali (⚠️ ricreate il 23/09 — le zone di agosto non esistono più)
Le zone di agosto sono sparite (Cloudflare cancella le zone "pending" mai attivate). Il 23/09 sono state ricreate con l'import automatico da Plesk:
- `manualsweb.it` → zone id `a6263083df451ff7419d5f55944acf04`
- `manualswebapp.it` → zone id `b4affa6c8a2dc979e4ae63840d63e5ef`
Tutti i record puntano **ancora a Plesk** (176.221.55.118), DNS-only, compresi quelli email (MX `mail.register.it`, `pop`, `autoconfig`, SRV `_autodiscover._tcp`, SPF). Nameserver: `jade`/`martin.ns.cloudflare.com`.

### Strategia: "prima i nameserver, poi l'IP"
1. L'azienda cambia i NS a Cloudflare quando vuole: **impatto zero**, i record puntano ancora a Plesk.
2. Zona attiva → emettiamo i certificati Let's Encrypt via DNS-01 (anche wildcard) **mentre il traffico va ancora su Plesk**, e attiviamo i blocchi 443 su nginx.
3. Al momento scelto da noi (dopo sync finale dati): su Cloudflare cambiamo gli A di `manualsweb.it`, `manualswebapp.it`, `*.manualswebapp.it` → 178.104.187.53 (www/ftp sono CNAME e seguono). Effetto in pochi minuti. Rollback = rimettere 176.221.55.118.

### A. Preparazione (prima del cambio NS)
- [x] A0. (fatto 25/09 — backup in `/root/nginx-backup-20260925.tgz`, vecchie copie in `/root/nginx-old-copies/`) Sistemare vhost manualsweb (prod + staging): aggiungere `client_max_body_size 100m` in `sites-available`, sostituire le copie in `sites-enabled` con symlink, `nginx -t`, reload. Verificare che `manualsweb.it` risponda l'app (porta 8081).
- [x] A1. SPF di manualswebapp.it: già presente nella zona CF (ricreata il 23/09, vedi sotto).
- [x] A2. Token CF scoped a manualsweb.it + manualswebapp.it salvato in `/root/.secrets/cloudflare-prod.ini` (25/09, verificato attivo). certbot 4.0 + plugin dns-cloudflare presenti.
- [x] A2b. Aggiunto `*.manualswebapp.it` A 176.221.55.118 DNS-only nella zona CF (25/09): mancava, e al cambio NS i sottodomini tenant (cometo, brc, cefla, erowa, falcon-conveyors, flexlink, ionefit, simagtorino, varinelli, schenck, tkse, …) sarebbero spariti.
- [ ] A3. (non più necessario: con la strategia "NS prima, IP dopo" si usano certificati Let's Encrypt via DNS-01, validi sia proxied che DNS-only)
- [x] A4. (preparati 25/09 in `/root/nginx-ssl-ready/`, con README dei comandi; NON attivi) Preparare i blocchi `listen 443 ssl` per `prod-manualsweb` e `prod-manualswebapp` (attivabili solo dopo aver ottenuto i cert in B5).
- [ ] A5. Dopo l'attivazione delle zone: SSL/TLS = **Full (strict)** (oggi "full"), Always Use HTTPS = on, Min TLS 1.2.
- [ ] A7. Test nel browser con `/etc/hosts` locale → 178.104.187.53 per i 7 host: login, dati, upload/download.
- [x] A8. (fatto 25/09: 45 file nuovi, 814MB → 883MB, log `/root/plesk-import/sync-prod-20260925.log`; su Plesk c'è attività reale dopo agosto → al giorno X servono **export DB freschi**) Sync upload di anticipo (delta grande dopo 7 settimane): `PLESK_FTP_PASS=... /root/plesk-import/sync_plesk_uploads.sh /var/www/production/manualsweb-prod/uploads`.
- [ ] A9. Verificare che su Plesk non siano stati fatti deploy/modifiche al codice dopo il 06/08 e che `main` su Hetzner sia allineato (manualsweb, manualswebapp, site, app).
- [ ] A10. Concordare con l'azienda: registrar di manualsweb.it/manualswebapp.it, giorno/ora (fascia a basso traffico), ordine (prima manualsweb.it + manualswebapp.it, poi st1995.it).
- [ ] A11. Chiedere all'azienda, per st1995.it (su plaindns), di preparare questa modifica — **senza toccare MX/TXT/autodiscover**:
      - `st1995.it` A 176.221.55.118 → **178.104.187.53**
      - `www.st1995.it` CNAME plesk.areasispac.it → **A 178.104.187.53**
      - `app.st1995.it` CNAME plesk.areasispac.it → **A 178.104.187.53**
      - `ftp.st1995.it`: lasciare com'è finché Plesk serve.

### B. Giorno del cambio — per ciascun gruppo di domini
- [ ] B1. L'azienda cambia NS di manualsweb.it + manualswebapp.it → `jade`/`martin.ns.cloudflare.com` (nessun impatto). Attesa: `dig +short NS manualsweb.it` → cloudflare, zona "Active".
- [ ] B2. Cert LE: `certbot certonly --dns-cloudflare --dns-cloudflare-credentials /root/.secrets/cloudflare-prod.ini -d manualsweb.it -d www.manualsweb.it` e `... -d manualswebapp.it -d '*.manualswebapp.it'` → attivare blocchi 443 (A4) → `nginx -t` → reload. Poi A5.
- [ ] B3. Test con `/etc/hosts` (A7) anche in HTTPS.
- [ ] B4. Giorno X: export freschi DB da phpMyAdmin → `import_plesk_db.sh`; sync finale upload.
- [ ] B5. Su Cloudflare: A `manualsweb.it`, `manualswebapp.it`, `*.manualswebapp.it` → 178.104.187.53. (Eventuale proxied=on solo per gli host principali, non per il wildcard.)
- [ ] B6. Test funzionale sui domini reali + email manualsweb.it (register.it).
- [x] B7. (FATTO 09/10, anticipato rispetto al giorno X) st1995.it (fuori da CF) — **stesso giorno X di B5, in concomitanza** (decisione utente 29/09): l'azienda cambia i record di A11 → `certbot --nginx -d st1995.it -d www.st1995.it -d app.st1995.it` → test.

### C. Dopo
- [ ] C1. Monitoraggio log per qualche giorno.
- [ ] C2. Rollback se serve: manualsweb → l'azienda rimette `ns1/ns2.plaindns.net`; st1995 → rimettere A/CNAME originali di A11 (Plesk resta acceso e intatto).
- [ ] C3. Dopo 2-4 settimane stabili: dismissione Plesk per quell'app.
- [ ] C4. Rigenerare la Global API Key Cloudflare (usata per creare le zone, accesso totale).

---

## 🗄️ SCALETTA CUTOVER ORIGINALE (06/08 — SUPERATA dalla checklist sopra: zone id, strategia e st1995 fuori da CF sono cambiati)

**Stato di partenza**: tutti i dati (DB + upload) e il codice dei 4 progetti sono già pronti su Hetzner, in produzione, verificati. Le zone DNS su Cloudflare esistono già con tutti i record pronti. **L'unica cosa che manca è lo switch DNS vero e proprio** (cambio nameserver) più la generazione dei certificati SSL che ne dipende. Fino a quando non si fa lo switch, Plesk resta la produzione reale e non c'è alcun rischio nel procedere con questa scaletta con calma.

### Ordine consigliato
Non fare tutti e 4 i domini insieme. Prima un pilota per validare il meccanismo, poi gli altri:
1. **`manualsweb.it` + `manualswebapp.it` insieme** (condividono i dati, sono i più testati)
2. **`st1995.it` + `app.st1995.it`** (stesso dominio/zona, farli insieme)

### Per ogni dominio, in questo ordine:

**1. Ultimo sync dati (solo manualsweb/manualswebapp — gli altri due sono già "a specchio" 1:1 con staging, non serve)**
```bash
ssh root@178.104.187.53
PLESK_FTP_PASS='<password FTP Plesk>' /root/plesk-import/sync_plesk_uploads.sh /var/www/production/manualsweb-prod/uploads
# per i DB, ripetere import_plesk_db.sh per ogni dump se il cliente ha fatto nuovi export da Plesk nel frattempo
# (i dump vecchi sono in /root/plesk-import/*.sql — se sono cambiati dati sul Plesk reale, servono export freschi via phpMyAdmin)
```

**2. Cambio nameserver al registrar del dominio** (non necessariamente lo stesso pannello di Plesk — verificare dove è registrato ciascun dominio) → puntare a:
```
jade.ns.cloudflare.com
martin.ns.cloudflare.com
```
ID delle zone già create su Cloudflare (account `stefano.bondesani@gmail.com`):
- `manualsweb.it` → zone id `85520a32a0d5f634f9b3570a0e0cb45a`
- `manualswebapp.it` → zone id `6a7541a892079d3a2350784650da272b`
- `st1995.it` (copre anche `app.st1995.it`) → zone id `395ea28ff0279ec5666abc82efe9df14`

**3. Attesa propagazione DNS** — verificare con `dig +short NS manualsweb.it` finché non risponde con i nameserver Cloudflare (di solito minuti/ore, in rari casi fino a 24-48h).

**4. Generazione certificato SSL** (solo dopo che il DNS risolve verso Hetzner, altrimenti Let's Encrypt non riesce a validare):
- Per `manualswebapp.it`: certificato **wildcard** via DNS-01 (`certbot --dns-cloudflare`), stesso procedimento già fatto per `stagingrail.com` (vedi memoria `cloudflare_wildcard_subdomains.md` per il pattern esatto, o replicare i comandi usati lì).
- Per `manualsweb.it`, `st1995.it`, `app.st1995.it`: certificato singolo, anche via `certbot --dns-cloudflare` o webroot/http-01 standard.
- **Nota**: il file `/root/.secrets/cloudflare.ini` sul server ha un token scoped **solo** a `stagingrail.com` — per le nuove zone serve un token nuovo (o allargare lo scope di quello esistente dal pannello Cloudflare) prima di poter usare `certbot --dns-cloudflare` su questi domini.

**5. Verifica funzionale sul dominio reale**: login, dati, upload/download file. Per `manualsweb.it` e `st1995.it` **verificare anche che l'email continui a funzionare** (hanno record MX reali già replicati su Cloudflare: `mail.register.it` per manualsweb.it, Microsoft 365 per st1995.it).

**6. Monitoraggio primi giorni**, poi si può considerare Plesk dismesso per quell'app (non cancellare subito, tenerlo come rete di sicurezza per un po').

### Container/vhost coinvolti sul server Hetzner (178.104.187.53)
| Dominio | Container app prod | Vhost nginx |
|---|---|---|
| manualsweb.it | `manualsweb-app-prod` | `prod-manualsweb` → `manualsweb.it www.manualsweb.it` ✅ |
| manualswebapp.it | `manualswebapp-app-prod` | `prod-manualswebapp` → `manualswebapp.it www.manualswebapp.it` ✅ |
| st1995.it | `site-app-prod` | `prod-site` → `st1995.it www.st1995.it` ✅ |
| app.st1995.it | `st1995app-prod` | `prod-st1995-app` → `app.st1995.it` ✅ |

Tutti e 4 i vhost hanno già il dominio reale corretto configurato (verificato il 06/08) — non serve toccare nginx al momento del cutover, solo aggiungere il blocco SSL una volta ottenuto il certificato.

---

## Stato riassuntivo per progetto (tutto verificato il 2026-08-06)

| Progetto | DB produzione | Upload produzione | Codice deployato | DNS |
|---|---|---|---|---|
| manualsweb + manualswebapp | ✅ 14/14 DB con dati reali da Plesk | ✅ sincronizzati (814MB) | ✅ `main` aggiornato, verificato con `app:migrate-tenants` | ⏳ zona CF pronta, nameserver non ancora cambiati |
| site (st1995.it) | ✅ copiato da staging (nessuna divergenza confermata dal cliente) | ⚠️ da verificare se esiste una cartella upload separata | (nessuna automazione migration da rifare, già a posto) | ⏳ zona CF pronta |
| st1995-app (app.st1995.it) | ✅ creato da zero + copiato da staging, password rigenerata | n/d | ✅ deploy rifatto per allineare la password | ⏳ stessa zona di st1995.it |
| machine-ledger | ✅ già live | ✅ già live | ✅ già live | ✅ già in produzione reale (machineledgerweb.com) |

---

## Dettaglio lavoro svolto (cronologia, per riferimento)

### 1. manualsweb + manualswebapp

Condividono lo stesso container MySQL (`manualswebapp-db-{staging|prod}`); `manualswebapp` non ha un proprio DB.

**Staging**: tutti i 13 DB tenant + `manualsdb` importati da dump reali Plesk (phpMyAdmin export → scp → `import_plesk_db.sh`), `fresia` escluso (cliente eliminato). Baseline `migration_versions` (41 versioni) ripristinata su tutti. Upload sincronizzati via FTP (`sync_plesk_uploads.sh`, delta-based). Routing multi-tenant (username `admin_<cliente>` → DB del cliente, indipendente dal sottodominio) verificato nel codice e nei log reali.

**Produzione**: stesso lavoro replicato — DB+utente `falcon-conveyors_db` creato, tutti i 13 DB tenant + `manualsdb` importati (814MB upload sincronizzati), secret GitHub `PROD_TENANT_DATABASES_YAML` creato, vhost `prod-manualsweb` corretto (dominio placeholder → `manualsweb.it`), script di backup aggiornato con i 13 DB tenant, merge `staging`→`main` (24 commit, fast-forward) deployato. **Problema trovato e risolto**: `fresia_db` in produzione era completamente vuoto (0 tabelle) e ha fatto fallire il primo deploy (`app:migrate-tenants` provava a eseguire le migration da zero) — risolto clonando lo schema da `cometo_db` + baseline `migration_versions`, deploy rilanciato con successo. Verificato: 14/14 target puliti.

### 2. site
DB produzione (`st1995_it_db`) era completamente vuoto — non un problema di migration, i dati non erano mai stati portati su Hetzner per prod. Il cliente ha confermato nessuna divergenza tra staging e produzione, quindi copiato schema+dati direttamente da `manualswebapp-db-staging` a `manualswebapp-db-prod` (mysqldump container-to-container). Verificato: 11 tabelle, 7 migration tracciate, identico a staging.

### 3. machine-ledger
Già completamente migrato e live in produzione. Nessuna azione necessaria.

### 4. st1995-app
Confermato dal cliente essere il progetto giusto. DB produzione (`app_st1995_it_db`) non esisteva affatto — creato da zero, popolato copiando da staging. Password nuova generata per l'utente MySQL `appst1995` (impossibile leggere quella esistente, i secret GitHub non sono leggibili all'indietro), salvata nel secret `PROD_DATABASE_PASSWORD`, deploy rilanciato. Verificato: 9 tabelle, 7 utenti, app risponde 200 senza errori.

### Zone Cloudflare
Create via Global API Key (i token scoped non avevano permesso di creare zone, provato più volte senza successo — la creazione zone richiede la Global API Key, non un token custom). Nameserver assegnati: `jade.ns.cloudflare.com` / `martin.ns.cloudflare.com` (stessi di stagingrail.com).

Record creati (pattern replicato da stagingrail.com: host principali proxied, wildcard DNS-only):
- `manualsweb.it` / `www.manualsweb.it` → A 178.104.187.53, proxied
- `manualswebapp.it` / `www.manualswebapp.it` → A 178.104.187.53, proxied
- `*.manualswebapp.it` → A 178.104.187.53, **DNS-only** (necessario per certificati SSL individuali via DNS-01)
- `st1995.it` / `www.st1995.it` / `app.st1995.it` → A 178.104.187.53, proxied

Record email replicati (controllati via `dig` cosa risolve oggi su Plesk, per non rompere la posta al cutover):
- `manualsweb.it`: MX → `mail.register.it`, SPF `v=spf1 include:spf.webapps.net ~all`
- `st1995.it`: **Microsoft 365** — MX → `st1995-it.mail.protection.outlook.com`, SPF `v=spf1 include:spf.protection.outlook.com -all`, TXT verifica MS `MS=ms97421390`, CNAME `autodiscover.st1995.it` → `autodiscover.outlook.com`. Da riverificare vicino al cutover se sono stati aggiunti record DKIM (selector1/selector2._domainkey) nel frattempo — oggi assenti.
- `manualswebapp.it`: nessuna email configurata.

**Nota di sicurezza**: la Global API Key usata per creare le zone ha accesso completo all'account Cloudflare. Consigliato rigenerarla dal pannello quando non serve più per altre creazioni di zone.

---

## Note operative

- **Nessun accesso SSH a Plesk** (176.221.55.118): i DB si esportano solo manualmente via phpMyAdmin (zip, poi trasferiti a mano); i file invece hanno accesso FTP diretto (utente `admin_st1995`), sincronizzabili in automatico con `lftp mirror --only-newer`.
- **Script riutilizzabili**, entrambi su `/root/plesk-import/` sul server Hetzner:
  - `import_plesk_db.sh <container> <dump_file.sql> <target_db>` — importa un dump + ripristina la baseline `migration_versions` (41 versioni, in `/root/plesk-import/migration_baseline.txt`).
  - `sync_plesk_uploads.sh <local_target_dir>` — sync delta via FTP (richiede `PLESK_FTP_PASS` in env).
- **Credenziali** (dal 25/09 salvate sul server, root-only, non in questo file): FTP Plesk in `/root/.secrets/plesk-ftp.env` (lo script `sync_plesk_uploads.sh` la legge da solo, basta lanciarlo senza variabili); token Cloudflare in `/root/.secrets/cloudflare-prod.ini`. **A fine migrazione**: cancellare `plesk-ftp.env` alla dismissione di Plesk, fare Roll del token Cloudflare e aggiornare il file.
- Alcune azioni di scrittura dirette sul container/percorsi "prod" vengono bloccate dal classificatore di sicurezza dell'ambiente Claude Code per default — richiedono conferma esplicita dell'utente per essere eseguite (già ottenuta e usata in questa sessione per import DB/deploy).
