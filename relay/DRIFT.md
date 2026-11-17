# Relayn i drift (F7)

Hur relayn körs på en riktig VPS: härdning, TLS, uppdateringar och
övervakning utan IP-adresser. Att sätta upp den första gången står i
[`docs/prototyp.md`](../docs/prototyp.md) och i [README.md](README.md).
Claude hyr ingen server och hanterar inga lösenord eller nycklar
(`CLAUDE.md`, "Aldrig"): stegen görs av ägaren.

Inget här är provat på en riktig server (G2). Kommandona gäller Debian 13
eller Ubuntu 24.04 och är **ej verifierade** där. Kommandona på servern körs
som root: skriv `sudo -i` först när du har loggat in som din vanliga
användare.

## 1. Servern

1. **En vanlig användare med SSH-nyckel först.** Skapa en användare med
   `sudo`, lägg din publika nyckel i dess `~/.ssh/authorized_keys` och logga
   in med den i ett nytt fönster innan du stänger av något. Annars kan du
   låsa ute dig själv.
2. **Inloggning bara med SSH-nyckel.** Skriv `PasswordAuthentication no` och
   `PermitRootLogin no` i en egen fil, `/etc/ssh/sshd_config.d/10-sha.conf`:
   filerna där läses före `sshd_config`, och molnavbilder har ofta en egen
   (till exempel `50-cloud-init.conf`) som annars vinner. Kontrollera med
   `sshd -T | grep -E "passwordauthentication|permitrootlogin"` och starta
   om `ssh`.
3. **Brandvägg:** 22 (SSH), 80 (bara för certifikatet, avsnitt 3) och 443
   (HTTPS) in.
   ```sh
   apt install ufw
   ufw default deny incoming
   ufw allow 22/tcp
   ufw allow 80/tcp
   ufw allow 443/tcp
   ufw logging off
   ufw enable
   ```
   Port 80 måste vara öppen för att certbot ska kunna förnya certifikatet
   automatiskt. nginx svarar där bara på certbots utmaning (avsnitt 3).
4. **Säkerhetsuppdateringar automatiskt:** `apt install unattended-upgrades`
   och `dpkg-reconfigure unattended-upgrades`.
5. **Klockan:** `timedatectl` ska visa `System clock synchronized: yes`. Den
   behövs för TLS-certifikatet och för tiderna i loggarna. Relayn räknar
   själv ut när paket går ut med en klocka som inte påverkas av ändringar.
6. **Loggar som kan innehålla IP-adresser:** SSH loggar inloggningar med
   adress i journald (`journalctl -u ssh`), och på Ubuntu 24.04 även i
   `/var/log/auth.log` (rsyslog). Där finns din egen adress, men också
   adresser från okända som försöker logga in. De som använder appen syns
   inte där. Kontrollera också brandväggens logg (avstängd ovan) och
   leverantörens nätloggar.

## 2. Relayn som tjänst

Bygg på din dator, med samma Go som i CI (`relay/go.mod`, `ci.yml`), för
serverns processor (`amd64` för de flesta VPS:er, `arm64` för ARM) och
utan C-bibliotek, så att filen fungerar på servern oavsett din dator. Har
servern ARM: byt `GOARCH=amd64` mot `GOARCH=arm64`.

```sh
cd relay && CGO_ENABLED=0 GOOS=linux GOARCH=amd64 GOTOOLCHAIN=local \
  go build -trimpath -o relay . && go version -m relay
```

Kopiera filen till `/usr/local/bin/sha-relay` och skapa
`/etc/systemd/system/sha-relay.service`:

```ini
[Unit]
Description=SHA relay
Wants=network-online.target
After=network-online.target

[Service]
ExecStart=/usr/local/bin/sha-relay -addr 127.0.0.1:8080 -trusted-proxies 127.0.0.1 -max-total-mib 256
# Go:s skräpsamlare låter minnet växa till ungefär det dubbla av det som
# används. Gränsen här får Go att städa i tid, långt under MemoryMax, så att
# relayn svarar 507 i stället för att stoppas av kärnan (ej mätt).
Environment=GOMEMLIMIT=512MiB
Restart=on-failure
DynamicUser=yes
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictAddressFamilies=AF_INET AF_INET6
RestrictNamespaces=yes
LockPersonality=yes
MemoryDenyWriteExecute=yes
SystemCallArchitectures=native
# Paketen ligger i RAM (-max-total-mib 256 ovan). Lämna gott om marginal:
# varje paket tar mer minne än sin storlek (relay/README.md). Ej mätt.
MemoryMax=900M

[Install]
WantedBy=multi-user.target
```

```sh
systemctl daemon-reload
systemctl enable --now sha-relay
systemctl status sha-relay
```

Relayn skriver inga filer. Dess loggrader (start, räknare var 15:e minut)
innehåller varken adresser eller brevlåde-ID (`relay/README.md`,
"Loggning") och hamnar i journald: `journalctl -u sha-relay`.

## 3. TLS

Certifikatet måste komma från en publik CA: appen litar bara på
telefonens egna CA:er.

certbot behöver port 80 för sin utmaning, och nginx-exemplet i
`relay/README.md` pekar på certifikatfiler som inte finns förrän det första
certifikatet är hämtat. Gör därför så här:

1. Installera och stäng av nginx standardsida och åtkomstloggen för allt:
   ```sh
   apt install nginx certbot
   rm /etc/nginx/sites-enabled/default
   ```
   I `/etc/nginx/nginx.conf`: byt `error_log …;` högst upp i filen
   (utanför `http { … }`) mot `error_log /dev/null crit;`. Inuti
   `http { … }`: byt `access_log …;` mot `access_log off;`, och ett
   `error_log …;` där, om det finns, mot `error_log /dev/null crit;`.
2. Lägg till ett block för port 80 som bara svarar på certbots utmaning, i
   `/etc/nginx/sites-enabled/acme.conf`:
   ```nginx
   server {
       listen 80;
       listen [::]:80;
       access_log off;
       error_log /dev/null crit;
       location /.well-known/acme-challenge/ { root /var/www/acme; }
       location / { return 444; }
   }
   ```
   `mkdir -p /var/www/acme && nginx -t && systemctl reload nginx`

   Port 80 var redan öppen när nginx installerades, så standardsidan kan ha
   hunnit logga adresser från dem som söker igenom nätet. Radera de loggarna
   nu: `rm -f /var/log/nginx/*`
3. Hämta certifikatet utan att certbot ändrar nginx:
   ```sh
   certbot certonly --webroot -w /var/www/acme -d relay.example.se
   ```
4. Lägg nu in blocket för port 443 från `relay/README.md` (med din domän),
   och kör `nginx -t && systemctl reload nginx`.
5. Förnyelsen: certbot lägger själv in en timer. Låt certbot ladda om nginx
   efter en förnyelse, och prova med brandväggen som den är:
   ```sh
   echo 'deploy-hook = systemctl reload nginx' >> /etc/letsencrypt/cli.ini
   systemctl list-timers | grep certbot
   certbot renew --dry-run --run-deploy-hooks
   ```
   `--run-deploy-hooks` gör att provet också laddar om nginx. Utan den
   flaggan hoppar `--dry-run` över omladdningen.

Går förnyelsen inte igenom slutar certifikatet att gälla efter 90 dagar, och
då når appen inte relayn: appen litar bara på publika CA:er.

## 4. Uppdateringar

- **Relayn:** bygg en ny fil (avsnitt 2), kopiera den och kör
  `systemctl restart sha-relay`. **En omstart raderar alla paket som inte
  har hämtats** (0002, fråga f): avsändarens app har redan visat dem som
  skickade. Gör det när få skriver, och säg till de som provar.
- **Go:** följ Gos säkerhetsutgåvor och bygg om. Dependabot följer inte Go
  själv.
- **nginx och systemet:** kommer med `unattended-upgrades`.

## 5. Övervakning utan IP-adresser

- **Är den uppe?** Från din dator eller en tjänst som bara anropar
  `https://relay.example.se/healthz` och väntar sig `ok`. Tjänsten ser bara
  serverns adress, inte användarnas.
- **Hur mår den?** Räknarraden var 15:e minut i `journalctl -u sha-relay`:
  sparade och hämtade paket och avvisade anrop per orsak (`rejected_rate`
  för spamgränsen, `rejected_full` för fulla brevlådor). Många `rejected_rate` tyder på delade IP-adresser (0002,
  fråga e).
- **Minne:** `systemctl status sha-relay` visar minnet. Når det `MemoryMax`
  stoppas tjänsten och startas om, och alla paket som inte har hämtats
  försvinner. Med `GOMEMLIMIT` och `-max-total-mib 256` ska relayn i stället
  svara 507 när den är full; det är **ej mätt**.
- **Inga IP-adresser** i något av detta. Lägg inte till verktyg som läser
  nginx- eller brandväggsloggar.

## 6. Säkerhetskopior

Inga: relayn har inget tillstånd att spara. Spara bara
`/etc/systemd/system/sha-relay.service` och nginx-konfigurationen.

## 7. De öppna frågorna i 0002

Svaren och förslagen för version 1 står i
[0008](../docs/decisions/0008-oppna-fragor-i-0002.md).
