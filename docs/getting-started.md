# Getting Started — NixOS für BAUER GROUP

## Voraussetzungen

- Ein x86_64-Rechner (physisch oder VM)
- NixOS 25.11 Installations-ISO ([Download](https://nixos.org/download))
- USB-Stick (mind. 4 GB) oder VM-Setup
- Internetzugang auf der Zielmaschine

## Schritt 1: NixOS installieren

1. NixOS-ISO auf USB-Stick schreiben:

   ```bash
   # Linux/macOS
   sudo dd if=nixos-minimal.iso of=/dev/sdX bs=4M status=progress

   # Windows: Rufus oder balenaEtcher verwenden
   ```

2. Vom USB-Stick booten und das Netzwerk einrichten:

   ```bash
   # WLAN (falls nötig)
   sudo systemctl start wpa_supplicant
   wpa_cli
   > add_network
   > set_network 0 ssid "SSID"
   > set_network 0 psk "Passwort"
   > enable_network 0

   # Prüfen
   ip a
   ping nixos.org
   ```

3. Partitionieren und Basis-Installation:

   ```bash
   # Beispiel: EFI + ext4
   sudo parted /dev/sda -- mklabel gpt
   sudo parted /dev/sda -- mkpart ESP fat32 1MiB 512MiB
   sudo parted /dev/sda -- set 1 esp on
   sudo parted /dev/sda -- mkpart primary ext4 512MiB 100%

   sudo mkfs.fat -F32 /dev/sda1
   sudo mkfs.ext4 /dev/sda2

   sudo mount /dev/sda2 /mnt
   sudo mkdir -p /mnt/boot
   sudo mount /dev/sda1 /mnt/boot

   # Basis-Config generieren
   sudo nixos-generate-config --root /mnt
   ```

## Schritt 2: Hardware-Konfiguration sichern

Die Hardware-Konfiguration wird automatisch generiert und beschreibt CPU, Disks, Kernel-Module etc. für diese spezifische Maschine:

```bash
# Anzeigen (zur Prüfung)
cat /mnt/etc/nixos/hardware-configuration.nix

# Diese Datei bleibt auf der Maschine unter /etc/nixos/
# Sie wird NICHT ins Git-Repo committet.
```

**Wichtig:** Die `hardware-configuration.nix` ist maschinenspezifisch und gehört auf die Maschine, nicht ins Repo. Sie wird bei jedem `nixos-generate-config` neu erzeugt.

## Schritt 3: Parameterdatei erstellen

Jede Maschine braucht eine `/etc/nixos/params.nix` die das Template parametrisiert.

```bash
# Repo klonen (auf einem anderen Rechner oder nach der Installation)
git clone git@github.com:bauer-group/nixos.git
cd nixos

# Beispiel-Parameterdatei als Vorlage kopieren
cp params.example.nix /mnt/etc/nixos/params.nix

# Bearbeiten — mindestens hostName und user.sshKeys setzen!
vim /mnt/etc/nixos/params.nix
```

### Minimale params.nix für einen Server

```nix
{ ... }: {
  bauer.params = {
    hostName = "srv-prod-01";

    user = {
      name = "admin";
      fullName = "BAUER Admin";
      email = "admin@bauer-group.com";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... admin@workstation"
      ];
    };

    network = {
      useDHCP = false;
      interface = "eth0";
      address = "10.0.0.5";
      prefixLength = 24;
      gateway = "10.0.0.1";
      nameservers = [ "1.1.1.1" "8.8.8.8" ];
      openPorts = [ 80 443 ];
    };

    boot.loader = "grub";
    boot.grubDevice = "/dev/sda";

    server = {
      composeProjects = {
        webapp = { directory = "/opt/webapp"; };
      };
    };
  };
}
```

### Minimale params.nix für einen Desktop

```nix
{ ... }: {
  bauer.params = {
    hostName = "dev-workstation-01";

    user = {
      name = "karl";
      fullName = "Karl Bauer";
      email = "karl@bauer-group.com";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... karl@desktop"
      ];
      hashedPassword = "$6$rounds=100000$...";  # mkpasswd -m sha-512
    };

    network.useDHCP = true;
    dev.embeddedDev = true;  # CAN-Bus Tooling aktivieren
  };
}
```

### Minimale params.nix für einen Kiosk

```nix
{ ... }: {
  bauer.params = {
    hostName = "kiosk-lobby-01";

    user = {
      name = "kiosk";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA... admin@workstation"
      ];
    };

    network.useDHCP = true;

    kiosk = {
      url = "http://localhost:3000";
      composeFile = /opt/kiosk/docker-compose.yml;
      touchscreen = true;
    };
  };
}
```

## Schritt 4: Erstes Deployment

```bash
# Von der Zielmaschine aus (nach Installation und Reboot)
cd /pfad/zum/nixos-repo

# Template wählen und deployen
sudo nixos-rebuild switch --flake .#server --impure

# Oder für Desktop:
sudo nixos-rebuild switch --flake .#desktop-dev --impure

# Oder für Kiosk:
sudo nixos-rebuild switch --flake .#desktop-kiosk --impure
```

**Das `--impure` Flag ist nötig**, damit NixOS die lokale `/etc/nixos/params.nix` lesen kann. Ohne `--impure` schlägt der Build fehl.

## Schritt 5: Täglicher Workflow

### Änderungen testen

```bash
# Ohne Reboot testen (wird beim nächsten Reboot zurückgesetzt)
sudo nixos-rebuild test --flake .#server --impure

# Dauerhaft anwenden
sudo nixos-rebuild switch --flake .#server --impure
```

### Rollback

```bash
# Im Boot-Menü: ältere Generation auswählen

# Oder via CLI
sudo nixos-rebuild switch --rollback
```

### Updates

```bash
# Flake-Inputs aktualisieren (nixpkgs, home-manager, etc.)
nix flake update

# Dann neu deployen
sudo nixos-rebuild switch --flake .#server --impure
```

### Parameter ändern

```bash
# Einfach die params.nix auf der Maschine bearbeiten
sudo vim /etc/nixos/params.nix

# Und neu deployen
sudo nixos-rebuild switch --flake .#server --impure
```

## Cheat Sheet

```bash
# ── Deployment ────────────────────────────────
nixos-rebuild switch --flake .#server --impure     # Server deployen
nixos-rebuild switch --flake .#desktop-dev --impure # Desktop deployen
nixos-rebuild test --flake .#server --impure        # Testen ohne Commit
nixos-rebuild switch --rollback                     # Letzte Generation

# ── Nix ───────────────────────────────────────
nix flake update                    # Inputs aktualisieren
nix flake check                     # Linting + Formatting prüfen
nix fmt                             # Code formatieren
nix develop                         # Dev-Shell betreten

# ── System ────────────────────────────────────
nixos-version                       # Aktuelle Version
nixos-generate-config               # Hardware-Config neu generieren
nix-store --gc                      # Speicher freigeben
nix-store --optimise                # Store deduplizieren

# ── Diagnose ──────────────────────────────────
systemctl --failed                  # Fehlgeschlagene Services
journalctl -xe                      # Letzte Logs
nixos-option bauer.params           # Parameter-Optionen anzeigen
```
