# Troubleshooting

## Build-Fehler

### "error: attribute 'XXX' missing"

**Ursache:** Modul erwartet ein Argument, das nicht übergeben wird.

```bash
# Prüfe, ob alle Inputs korrekt weitergereicht werden:
nix flake check
```

### "error: infinite recursion encountered"

**Ursache:** Zirkuläre Abhängigkeit in der Config.
Häufig durch `config.XXX` in einer Option, die von sich selbst abhängt.

```bash
# Debuggen: Welche Option verursacht es?
nix eval .#nixosConfigurations.hostname.config.XXX --show-trace 2>&1 | head -50
```

### "hash mismatch in fixed-output derivation"

**Ursache:** Upstream-Quelle hat sich geändert.

```bash
# Flake-Lock updaten
nix flake update
# Dann neu bauen
```

### Build bricht mit OOM ab

```bash
# Weniger parallele Builds
NIX_BUILD_CORES=2 nixos-rebuild switch --flake .#hostname

# Oder Swap temporär aktivieren
sudo fallocate -l 4G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile
```

## Deployment-Fehler

### "Permission denied (publickey)"

```bash
# SSH-Verbindung testen
ssh -v root@10.0.0.1

# Key auf Server autorisiert?
# In modules/baseline/users.nix → openssh.authorizedKeys.keys
```

### "error: the option does not exist"

**Ursache:** NixOS-Version-Mismatch. Option existiert in der Ziel-Nixpkgs-Version nicht.

```bash
# Prüfe Nixpkgs-Version im Lock
nix flake metadata | grep nixpkgs

# Option suchen
nix search nixpkgs#nixosModules services.XXX
# Oder: https://search.nixos.org/options
```

### Colmena: "Host unreachable"

```bash
# Einzeln testen
ssh root@10.0.0.1 echo ok

# Nur erreichbare Hosts deployen
colmena apply --on @production 2>&1 | grep -v unreachable
```

## System-Probleme

### System bootet nicht nach Rebuild

1. Im Boot-Menü eine **vorherige Generation** wählen
2. Danach: `sudo nixos-rebuild switch --rollback`
3. Problem in der Config fixen und neu deployen

### "A stop job is running for..." (hängt beim Shutdown)

```bash
# Welcher Service hängt?
systemctl list-jobs

# Timeout verkürzen (temporär)
sudo systemctl stop <service-name> --force
```

### Disk voll (Nix Store)

```bash
# Sofort aufräumen
sudo nix-collect-garbage -d

# Nur Generationen älter als 7 Tage löschen
sudo nix-collect-garbage --delete-older-than 7d

# Store optimieren (Deduplizierung)
sudo nix-store --optimise

# Prüfe Disk-Usage
du -sh /nix/store | sort -h | tail -20
nix path-info --size --closure-size /run/current-system | sort -k2 -n
```

### Package nicht gefunden

```bash
# In Nixpkgs suchen
nix search nixpkgs paketname

# Oder online: https://search.nixos.org/packages

# Paket aus unstable Channel nutzen (wenn in stable nicht vorhanden)
# In Config: pkgs.unstable.paketname (dank Overlay in flake.nix)
```

## Kernel / Hardware

### Kernel-Modul fehlt

```bash
# Prüfe ob Modul verfügbar
find /lib/modules/$(uname -r) -name '*.ko*' | grep modulname

# Manuell laden
sudo modprobe modulname

# Permanent in Config:
# boot.kernelModules = [ "modulname" ];
```

### Latest Kernel bricht ZFS

ZFS unterstützt oft nicht den allerneuesten Kernel.

```bash
# Lösung: ZFS-kompatiblen Kernel nutzen
boot.kernelPackages = config.boot.zfs.package.latestCompatibleLinuxPackages;
```

### Kernel-Config prüfen

```bash
# Aktuelle Kernel-Config
zcat /proc/config.gz | grep CAN
# oder
cat /boot/config-$(uname -r) | grep CAN
```

## Nix Sprache / Debugging

### Config interaktiv inspizieren

```bash
# REPL starten
nix repl

# Flake laden
:lf .

# Config eines Hosts inspizieren
nixosConfigurations.karl-desktop.config.boot.kernelPackages.kernel.version
nixosConfigurations.karl-desktop.config.services.openssh.enable
nixosConfigurations.karl-desktop.config.environment.systemPackages

# Alle NTP-Settings
nixosConfigurations.karl-desktop.config.services.chrony
```

### Welches Modul setzt eine Option?

```bash
# Trace anzeigen
nixos-option --flake .#karl-desktop services.chrony.servers

# Oder in REPL:
:lf .
nixosConfigurations.karl-desktop.options.services.chrony.servers.definitionsWithLocations
```

### Diff zwischen zwei Generationen

```bash
# Welche Pakete haben sich geändert?
nix store diff-closures /nix/var/nix/profiles/system-{100,101}-link
```

## Nützliche Links

- NixOS Options Search: https://search.nixos.org/options
- Nixpkgs Packages: https://search.nixos.org/packages
- NixOS & Flakes Book: https://nixos-and-flakes.thiscute.world/
- NixOS Wiki: https://wiki.nixos.org/
- Nix Pills (Deep Dive): https://nixos.org/guides/nix-pills/
