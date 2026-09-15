# Secrets Management mit agenix

## Warum Secrets Management?

NixOS-Konfigurationen landen im Nix Store — der ist **world-readable**. Passwörter, API-Keys und Zertifikate dürfen daher nie direkt in `.nix`-Dateien stehen.

**agenix** löst das: Secrets werden mit `age` verschlüsselt im Git-Repo gespeichert und erst zur Laufzeit auf dem Zielsystem entschlüsselt (unter `/run/agenix/`).

## Setup

### 1. Age-Keys sammeln

Jede Maschine hat einen SSH-Host-Key, der als Age-Key verwendet wird:

```bash
# Von einer Maschine den Host-Key als Age-Key extrahieren
ssh-keyscan -t ed25519 10.0.0.5 2>/dev/null | ssh-to-age

# Eigenen persönlichen Key (zum Editieren von Secrets)
cat ~/.ssh/id_ed25519.pub | ssh-to-age
```

### 2. Keys in secrets.nix eintragen

```nix
# secrets/secrets.nix
let
  admin = "age1ql3z7hjy...";          # Dein persönlicher Key
  srv-prod-01 = "age1abc123...";       # Host-Key von srv-prod-01
  srv-prod-02 = "age1def456...";       # Host-Key von srv-prod-02
  kiosk-lobby = "age1ghi789...";       # Host-Key von kiosk-lobby

  allServers = [ srv-prod-01 srv-prod-02 ];
  allMachines = allServers ++ [ kiosk-lobby ];
in {
  "restic-password.age".publicKeys     = [ admin ] ++ allServers;
  "webapp-env.age".publicKeys          = [ admin srv-prod-01 ];
  "grafana-admin-password.age".publicKeys = [ admin srv-prod-01 ];
  "grafana-secret-key.age".publicKeys     = [ admin srv-prod-01 ];
}
```

### 3. Secrets erstellen

```bash
# Dev-Shell betreten (enthält agenix CLI)
nix develop

# Secret erstellen (öffnet Editor)
agenix -e secrets/webapp-env.age

# Oder: aus Datei/Pipe
echo "DB_PASSWORD=supersecret" | agenix -e secrets/webapp-env.age

# Passwort-Hash für User generieren
mkpasswd -m sha-512 "mein-passwort" | agenix -e secrets/user-password.age
```

### 4. Secrets in params.nix referenzieren

Die Secrets werden zur Laufzeit unter `/run/agenix/<name>` verfügbar. Referenziere sie in der `params.nix` der Maschine:

```nix
# /etc/nixos/params.nix auf srv-prod-01
{ ... }: {
  bauergroup.params = {
    hostName = "srv-prod-01";
    # ...

    server = {
      composeProjects = {
        webapp = {
          directory = "/opt/webapp";
          envFile = "/run/agenix/webapp-env";  # ← agenix Secret
        };
      };

      backup = {
        enable = true;
        repository = "sftp:backup@storage:/backups/srv-prod-01";
        passwordFile = "/run/agenix/restic-password";  # ← agenix Secret
      };
    };
  };

  # agenix Secret-Deklarationen
  age.secrets.webapp-env.file = /pfad/zum/repo/secrets/webapp-env.age;
  age.secrets.restic-password.file = /pfad/zum/repo/secrets/restic-password.age;
}
```

### Grafana Secret Key und Admin-Passwort (Monitoring-Server)

Der volle Monitoring-Stack (`bauergroup.services.monitoring.enable = true`) braucht zwei Dateien, sonst schlägt die Evaluation fehl: einen eigenen Grafana Secret Key (Pflicht seit NixOS 26.05) und das Admin-Passwort (es gibt kein `admin`/`admin` mehr). Das Baseline-Modul erwartet nur Dateipfade auf der Zielmaschine — woher die Dateien kommen, entscheidet das Deployment:

```nix
# /etc/nixos/params.nix auf dem Monitoring-Server
{ ... }: {
  bauergroup.services.monitoring = {
    enable = true;
    grafanaSecretKeyFile = "/run/agenix/grafana-secret-key";
    grafanaAdminPasswordFile = "/run/agenix/grafana-admin-password";
  };

  # Variante A: agenix Secrets aus dem Repo
  #   head -c 32 /dev/urandom | base64 | agenix -e secrets/grafana-secret-key.age
  #   agenix -e secrets/grafana-admin-password.age
  age.secrets.grafana-secret-key.file = /pfad/zum/repo/secrets/grafana-secret-key.age;
  age.secrets.grafana-admin-password.file = /pfad/zum/repo/secrets/grafana-admin-password.age;

  # Variante B: Dateien beim Deployment ablegen (dann ohne age.secrets)
  #   head -c 32 /dev/urandom | base64 | sudo install -m 0400 /dev/stdin /var/lib/grafana-secret-key
  #   read -rs PW && printf '%s' "$PW" | sudo install -m 0400 /dev/stdin /var/lib/grafana-admin-password
  #   grafanaSecretKeyFile = "/var/lib/grafana-secret-key";
  #   grafanaAdminPasswordFile = "/var/lib/grafana-admin-password";
}
```

Die Dateien dürfen root-only bleiben: systemd reicht sie per `LoadCredential` an Grafana weiter. Ist eine leer, startet Grafana nicht. Pfade am besten als String angeben — die Baseline-Module lesen sie per `toString` zur Laufzeit, andere Module würden einen unquotierten Pfad aber in den world-readable Nix Store kopieren.

Ein neuer Key macht Werte unlesbar, die Grafana bereits mit dem alten Key verschlüsselt hat (z.B. in der UI eingetragene Contact-Point-Credentials). Die per Nix provisionierte Prometheus-Datasource ist nicht betroffen.

Das Admin-Passwort übernimmt Grafana nur, wenn es den Admin beim allerersten Start anlegt. Auf einem bestehenden Monitoring-Server (bisher `admin`/`admin`) das Passwort einmalig selbst setzen und auf die Erfolgsmeldung achten — der Befehl endet auch bei Fehlern mit Exit-Code 0:

```bash
# Die Secret-Datei ist root-only, deshalb liest sudo cat sie und nicht die eigene Shell
sudo cat /run/agenix/grafana-admin-password | sudo -u grafana grafana cli --homepath /var/lib/grafana \
  --config "$(tr '\0' '\n' < /proc/$(systemctl show -p MainPID --value grafana)/cmdline | grep config.ini)" \
  admin reset-admin-password --password-from-stdin
# Erwartet: "Admin password changed successfully"
```

Grafana lauscht nur noch auf `127.0.0.1:3100`. Zugriff per SSH-Tunnel (`ssh -L 3100:localhost:3100 admin@srv-prod-01`) oder über einen Reverse Proxy mit TLS auf derselben Maschine. Wer Grafana direkt im Netz braucht, setzt `grafanaListenAddress = "0.0.0.0"` und öffnet den Port selbst (z.B. `network.openPorts`) — Grafana spricht dann unverschlüsseltes HTTP.

## Secret-Rotation

```bash
# 1. Neuen Key hinzufügen oder alten entfernen in secrets/secrets.nix
vim secrets/secrets.nix

# 2. Alle Secrets neu verschlüsseln
agenix -r

# 3. Committen und deployen
git add secrets/
git commit -m "chore: rotate secrets"
nixos-rebuild switch --flake .#server --impure
```

## Workflow-Übersicht

```text
┌─ Entwickler-Rechner ─────────────────────────┐
│  secrets.nix       → Definiert wer was darf   │
│  *.age Dateien     → Verschlüsselt im Git     │
│  agenix CLI        → Erstellen/Bearbeiten      │
└──────────────────────────────────────────────┘
                     │ git push
                     ▼
┌─ Zielmaschine ───────────────────────────────┐
│  /run/agenix/*     → Entschlüsselt, 0400     │
│  SSH Host-Key      → Zum Entschlüsseln        │
│  systemd Services  → Lesen aus /run/agenix/   │
└──────────────────────────────────────────────┘
```

## Häufige Secrets

| Secret        | Datei                        | Wer braucht es                    |
| ------------- | ---------------------------- | --------------------------------- |
| User-Passwort | `user-password.age`          | Alle Maschinen                    |
| Restic Backup | `restic-password.age`        | Server mit Backup                 |
| Docker .env   | `webapp-env.age`             | Server mit diesem Compose-Projekt |
| Grafana Admin | `grafana-admin-password.age` | Monitoring-Server (Pflicht)       |
| Grafana Key   | `grafana-secret-key.age`     | Monitoring-Server (Pflicht)       |
| Wireguard Key | `wireguard-private.age`      | VPN-Teilnehmer                    |

## Troubleshooting

### "Failed to decrypt"

```bash
# Prüfe ob der Host-Key in secrets.nix eingetragen ist
cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
# Ergebnis mit dem Eintrag in secrets.nix vergleichen

# Secrets neu verschlüsseln nach Key-Änderung
agenix -r
```

### Secret-Datei ist leer auf der Maschine

```bash
# Prüfe ob der agenix-Service läuft
systemctl status agenix

# Prüfe Berechtigungen
ls -la /run/agenix/
```
