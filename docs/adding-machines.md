# Neue Maschine hinzufügen

## Übersicht

Jede Maschine braucht genau zwei Dateien auf dem Zielsystem:

1. `/etc/nixos/hardware-configuration.nix` — Hardware-spezifisch (automatisch generiert)
2. `/etc/nixos/params.nix` — Parametrisierung des Templates

Das Git-Repo bleibt generisch — keine maschinenspezifischen Dateien.

## Schritt 1: NixOS installieren

### Physische Maschine

```bash
# NixOS-ISO booten, Netzwerk einrichten, partitionieren
# (Siehe docs/getting-started.md für Details)

sudo nixos-generate-config --root /mnt
sudo nixos-install
sudo reboot
```

### Hetzner Cloud / VPS

```bash
# Via nixos-anywhere (provisioniert eine laufende Linux-Instanz)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#server \
  root@IP_ADRESSE
```

### VM (Testen)

```bash
# QEMU/KVM VM erstellen und NixOS-ISO booten
qemu-img create -f qcow2 nixos-test.qcow2 20G
qemu-system-x86_64 -m 4096 -cdrom nixos-minimal.iso \
  -drive file=nixos-test.qcow2 -enable-kvm
```

## Schritt 2: Hardware-Konfiguration generieren

```bash
# Auf der Zielmaschine (nach Installation)
sudo nixos-generate-config

# Prüfen
cat /etc/nixos/hardware-configuration.nix
```

Die Datei enthält:

- CPU-Typ und Microcode (Intel/AMD)
- Kernel-Module für Hardware (NVMe, USB, etc.)
- Dateisystem-Layout (Partitionen, UUIDs, Mount-Optionen)
- Swap-Konfiguration

**Diese Datei nie manuell bearbeiten** — sie wird von `nixos-generate-config` erzeugt.

## Schritt 3: Parameterdatei erstellen

```bash
# Repo klonen (oder aus anderem Rechner kopieren)
git clone git@github.com:bauer-group/nixos.git

# Beispiel als Vorlage
cp nixos/params.example.nix /etc/nixos/params.nix
vim /etc/nixos/params.nix
```

### Pflichtfelder

```nix
{ ... }: {
  bauer.params = {
    # ── PFLICHT ──────────────────────────────
    hostName = "srv-prod-01";

    user = {
      name = "admin";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA..."
      ];
    };
  };
}
```

### Template-spezifische Parameter

#### Server

```nix
bauer.params = {
  # ... Pflichtfelder ...

  network = {
    useDHCP = false;
    interface = "eth0";
    address = "10.0.0.5";
    prefixLength = 24;
    gateway = "10.0.0.1";
    openPorts = [ 80 443 ];
  };

  boot = {
    loader = "grub";
    grubDevice = "/dev/sda";
  };

  server = {
    monitoring = true;

    composeProjects = {
      webapp = {
        directory = "/opt/webapp";
        envFile = /run/agenix/webapp-env;  # Optional: Secrets
      };
      traefik = {
        directory = "/opt/traefik";
      };
    };

    backup = {
      enable = true;
      repository = "sftp:backup@storage:/backups/srv-prod-01";
      passwordFile = /run/agenix/restic-password;
    };
  };
};
```

#### Desktop (Development)

```nix
bauer.params = {
  # ... Pflichtfelder ...

  user.hashedPassword = "$6$rounds=100000$...";  # mkpasswd -m sha-512
  network.useDHCP = true;

  dev = {
    embeddedDev = true;   # CAN-Bus / SocketCAN aktivieren
  };
};
```

#### Desktop (Kiosk)

```nix
bauer.params = {
  # ... Pflichtfelder ...

  kiosk = {
    url = "https://dashboard.bauer-group.de";
    composeFile = /opt/kiosk/docker-compose.yml;
    composeDirectory = "/opt/kiosk";
    touchscreen = true;
    rotation = "left";     # Hochformat-Display
    idleTimeout = 300;     # Nach 5 Min Browser resetten
  };
};
```

## Schritt 4: Template deployen

```bash
# Repo auf die Maschine bringen
cd /opt/nixos  # oder wo auch immer das Repo liegt

# Template wählen
sudo nixos-rebuild switch --flake .#server --impure
# oder
sudo nixos-rebuild switch --flake .#desktop-dev --impure
# oder
sudo nixos-rebuild switch --flake .#desktop-kiosk --impure
```

## Schritt 5: Verifizieren

```bash
# Health-Check ausführen (von einem anderen Rechner)
./scripts/health-check.sh IP_ADRESSE

# Oder direkt auf der Maschine
systemctl --failed                          # Fehlgeschlagene Services
nixos-version                               # Version prüfen
docker ps                                   # Container (falls Server/Kiosk)
```

## Docker-Compose-Projekte vorbereiten (Server/Kiosk)

Für jeden Eintrag in `composeProjects` muss die `docker-compose.yml` im angegebenen Verzeichnis liegen:

```bash
# Verzeichnis erstellen
sudo mkdir -p /opt/webapp

# docker-compose.yml anlegen
sudo vim /opt/webapp/docker-compose.yml

# Optional: .env Datei (besser via agenix — siehe docs/secrets.md)
sudo vim /opt/webapp/.env
```

Das Server-Template erzeugt automatisch einen systemd-Service `compose-<name>` für jedes Projekt:

```bash
# Service-Status prüfen
systemctl status compose-webapp

# Logs
journalctl -u compose-webapp -f

# Manuell neustarten
sudo systemctl restart compose-webapp
```

## Template wechseln

Eine Maschine kann jederzeit das Template wechseln:

```bash
# Von Server zu Desktop-Dev
sudo nixos-rebuild switch --flake .#desktop-dev --impure

# Von Desktop-Dev zu Kiosk
sudo nixos-rebuild switch --flake .#desktop-kiosk --impure
```

Die `params.nix` muss ggf. angepasst werden (template-spezifische Felder hinzufügen).

## Remote-Deployment

```bash
# Von einer anderen Maschine aus deployen
nixos-rebuild switch --flake .#server \
  --target-host root@10.0.0.5 \
  --build-host localhost \
  --impure
```

## Checkliste: Neue Maschine

- [ ] NixOS installiert und gebootet
- [ ] `/etc/nixos/hardware-configuration.nix` generiert
- [ ] `/etc/nixos/params.nix` erstellt mit mindestens `hostName` und `user.sshKeys`
- [ ] Template deployed (`nixos-rebuild switch --flake .#<template> --impure`)
- [ ] SSH-Zugang getestet
- [ ] Services laufen (`systemctl --failed` zeigt keine Fehler)
- [ ] Docker-Compose-Projekte vorhanden (falls Server/Kiosk)
- [ ] Monitoring erreichbar (falls aktiviert)
- [ ] Backup konfiguriert (falls Produktion)
