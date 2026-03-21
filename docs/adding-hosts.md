# Neuen Host hinzufügen

## Übersicht

Jeder Host braucht:
1. Einen Ordner unter `hosts/<hostname>/`
2. Eine `default.nix` mit host-spezifischer Config
3. Eine `hardware-configuration.nix` (für physische Maschinen)
4. Einen Eintrag in `flake.nix`

## Schritt-für-Schritt

### 1. Host-Ordner erstellen

```bash
mkdir -p hosts/new-server
```

### 2. Hardware-Config generieren

**Auf physischer Maschine:**
```bash
nixos-generate-config --show-hardware-config > hosts/new-server/hardware-configuration.nix
```

**Für Hetzner Cloud / VPS:**
```nix
# hosts/new-server/hardware-configuration.nix
{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "virtio_pci" "sd_mod" "sr_mod" ];
  boot.initrd.kernelModules = [ "virtio_blk" "virtio_net" ];
}
```

### 3. Host-Config schreiben

```nix
# hosts/new-server/default.nix
{ config, lib, pkgs, ... }: {
  imports = [ ./hardware-configuration.nix ];

  networking.hostName = "new-server";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/DEIN-UUID";
    fsType = "ext4";
  };

  networking = {
    useDHCP = false;
    interfaces.eth0.ipv4.addresses = [{
      address = "1.2.3.4";
      prefixLength = 24;
    }];
    defaultGateway = "1.2.3.1";
    nameservers = [ "1.1.1.1" ];
    firewall.allowedTCPPorts = [ 80 443 ];
  };

  system.stateVersion = "25.11";
}
```

### 4. In flake.nix registrieren

```nix
# In nixosConfigurations:
new-server = mkHost {
  hostname = "new-server";
  modules = [
    ./modules/roles/server.nix
    ./modules/services/docker.nix
    # weitere Services nach Bedarf
  ];
};
```

### 5. In Colmena registrieren (für Remote-Deployment)

```nix
# In colmena:
new-server = { name, ... }: {
  deployment = {
    targetHost = "1.2.3.4";
    targetUser = "root";
    tags = [ "production" "hetzner" ];
  };
  imports = [ ./hosts/new-server ];
};
```

### 6. Deployen

```bash
# Lokal bauen, remote deployen
colmena apply --on new-server

# Oder via nixos-rebuild
nixos-rebuild switch --flake .#new-server \
  --target-host root@1.2.3.4 --build-host localhost
```

## Neuen Host von Null provisionieren (nixos-anywhere)

Für einen frischen Server, auf dem noch kein NixOS läuft:

```bash
# Voraussetzung: SSH-Zugang zum Server (beliebiges Linux oder NixOS Installer)
nix run github:nix-community/nixos-anywhere -- \
  --flake .#new-server \
  root@1.2.3.4
```

Das Tool:
1. Bootet in ein RAM-basiertes NixOS
2. Partitioniert die Disks (wenn disko konfiguriert)
3. Installiert deine NixOS-Config
4. Rebootet

## Rollen zuweisen

Wähle Rollen nach Funktion:

| Rolle | Import | Beschreibung |
|-------|--------|-------------|
| Server (Basis) | `./modules/roles/server.nix` | Alle Baselines + Hardening |
| Desktop Dev | `./modules/roles/desktop-dev.nix` | Server + GUI + Dev Tools |
| Embedded Dev | `./modules/roles/embedded-dev.nix` | Latest Kernel + CAN-Bus |

Und Services nach Bedarf:

| Service | Import | Beschreibung |
|---------|--------|-------------|
| Docker | `./modules/services/docker.nix` | Docker Engine + Compose |
| Outline | `./modules/services/outline.nix` | Wiki (braucht Docker) |

## Eigene Module erstellen

Neuen Service als Modul:

```nix
# modules/services/mein-service.nix
{ lib, pkgs, config, ... }: {
  # Option zum Ein/Ausschalten
  options.services.meinService.enable = lib.mkEnableOption "Mein Service";

  config = lib.mkIf config.services.meinService.enable {
    environment.systemPackages = [ pkgs.mein-paket ];
    systemd.services.mein-service = {
      # ...
    };
  };
}
```
