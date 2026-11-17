# Relayn i drift (F7)

Hur relayn körs på en riktig VPS: härdning, TLS, uppdateringar och
övervakning utan IP-adresser. Att sätta upp den första gången står i
[`docs/prototyp.md`](../docs/prototyp.md) och i [README.md](README.md).
Claude hyr ingen server och hanterar inga lösenord eller nycklar
(`CLAUDE.md`, "Aldrig"): stegen görs av ägaren.

Inget här är provat på en riktig server (G2). Kommandona gäller Debian 13
eller Ubuntu 24.04 och är **ej verifierade** där.

## 1. Servern

1. **Inloggning bara med SSH-nyckel.** I `/etc/ssh/sshd_config`:
   `PasswordAuthentication no` och `PermitRootLogin no`. Starta om `ssh`.
2. **Brandvägg:** bara 22 (SSH) och 443 (HTTPS) in.
   ```sh
   ufw default deny incoming
   ufw allow 22/tcp
   ufw allow 443/tcp
   ufw enable
   ```
   Port 80 behövs bara om certbot använder HTTP-utmaningen; öppna den då
   bara under förnyelsen, eller använd DNS-utmaningen.
3. **Säkerhetsuppdateringar automatiskt:** `apt install unattended-upgrades`
   och `dpkg-reconfigure unattended-upgrades`.
4. **Klockan:** `timedatectl` ska visa `System clock synchronized: yes`.
   Brevlåde-ID:n byts varje UTC-dygn; appen hämtar dagens och gårdagens.
5. **Loggar som kan innehålla IP-adresser:** `auth.log` (SSH), brandväggens
   logg och leverantörens nätloggar. SSH-inloggningar är ägarens egna, men
   kontrollera att inget loggar trafiken till port 443 (`ufw logging off`).

## 2. Relayn som tjänst

Bygg på din dator, med samma Go som i CI (`relay/go.mod`, `ci.yml`):

```sh
cd relay && GOTOOLCHAIN=local go build -trimpath -o relay . && go version -m relay
```

Kopiera filen till `/usr/local/bin/sha-relay` och skapa
`/etc/systemd/system/sha-relay.service`:

```ini
[Unit]
Description=SHA relay
After=network-online.target

[Service]
ExecStart=/usr/local/bin/sha-relay -addr 127.0.0.1:8080 -trusted-proxies 127.0.0.1
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
# Paketen ligger i RAM: lämna marginal över -max-total-mib (relay/README.md).
MemoryMax=768M

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

```sh
apt install certbot python3-certbot-nginx
certbot --nginx -d relay.example.se
systemctl list-timers | grep certbot   # förnyelsen är schemalagd
certbot renew --dry-run                # provar förnyelsen
```

Kontrollera efteråt att certbot inte har lagt till en `access_log` eller
ändrat `error_log` i nginx-konfigurationen (`relay/README.md`, exemplet).

## 4. Uppdateringar

- **Relayn:** bygg en ny fil (steg 2), kopiera den och kör
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
  startar systemd om tjänsten, och paketen försvinner.
- **Inga IP-adresser** i något av detta. Lägg inte till verktyg som läser
  nginx- eller brandväggsloggar.

## 6. Säkerhetskopior

Inga: relayn har inget tillstånd att spara. Spara bara
`/etc/systemd/system/sha-relay.service` och nginx-konfigurationen.

## 7. De öppna frågorna i 0002

Svaren och förslagen för version 1 står i
[0008](../docs/decisions/0008-oppna-fragor-i-0002.md).
