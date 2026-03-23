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
  "grafana-password.age".publicKeys    = [ admin srv-prod-01 ];
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
          envFile = /run/agenix/webapp-env;  # ← agenix Secret
        };
      };

      backup = {
        enable = true;
        repository = "sftp:backup@storage:/backups/srv-prod-01";
        passwordFile = /run/agenix/restic-password;  # ← agenix Secret
      };
    };
  };

  # agenix Secret-Deklarationen
  age.secrets.webapp-env.file = /pfad/zum/repo/secrets/webapp-env.age;
  age.secrets.restic-password.file = /pfad/zum/repo/secrets/restic-password.age;
}
```

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

| Secret        | Datei                   | Wer braucht es                    |
| ------------- | ----------------------- | --------------------------------- |
| User-Passwort | `user-password.age`     | Alle Maschinen                    |
| Restic Backup | `restic-password.age`   | Server mit Backup                 |
| Docker .env   | `webapp-env.age`        | Server mit diesem Compose-Projekt |
| Grafana Admin | `grafana-password.age`  | Monitoring-Server                 |
| Wireguard Key | `wireguard-private.age` | VPN-Teilnehmer                    |

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
