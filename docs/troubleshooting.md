# Troubleshooting

## Build-Fehler

### "error: attribute 'XXX' missing"

Ein Paket oder Option existiert nicht in der aktuellen nixpkgs-Version.

```bash
# Option im NixOS-Search suchen
# https://search.nixos.org/options

# Oder im REPL prüfen
nix repl
:lf .
nixosConfigurations.server.config.services.XXX
```

### "error: infinite recursion encountered"

Zwei Module setzen denselben Wert ohne `mkDefault` / `mkForce`:

```bash
# Trace aktivieren
nixos-rebuild build --flake .#server --impure --show-trace 2>&1 | head -100
```

### "hash mismatch in fixed-output derivation"

Ein Paket-Hash stimmt nicht (z.B. nach nixpkgs-Update):

```bash
# Nix Store reparieren
sudo nix-store --verify --repair

# Oder: betroffenes Paket löschen und neu bauen
nix-store --delete /nix/store/HASH-paketname
```

### "error: getting status of '/etc/nixos/params.nix': No such file"

Das `--impure` Flag fehlt oder die `params.nix` existiert nicht:

```bash
# Prüfe ob die Datei existiert
ls -la /etc/nixos/params.nix

# Falls nicht: Vorlage kopieren
cp params.example.nix /etc/nixos/params.nix
vim /etc/nixos/params.nix

# Build mit --impure
sudo nixos-rebuild switch --flake .#server --impure
```

### "error: The option 'bauergroup.params.hostName' is used but not defined"

Die `params.nix` setzt nicht alle Pflichtfelder:

```bash
# Pflichtfelder prüfen
# Mindestens: hostName und user.name müssen gesetzt sein
cat /etc/nixos/params.nix
```

## Deployment-Fehler

### "Permission denied (publickey)"

```bash
# SSH-Key auf der Zielmaschine prüfen
ssh -v root@ZIEL_IP

# SSH-Key muss in params.nix eingetragen sein:
# bauergroup.params.user.sshKeys = [ "ssh-ed25519 AAAA..." ];

# Oder: Initial-Passwort setzen (temporär)
# bauergroup.params.user.hashedPassword = "...";
```

### "The option 'XXX' does not exist"

Template-Option wird nicht vom gewählten Template unterstützt:

```bash
# Verfügbare Optionen anzeigen
nixos-option bauergroup.params
nixos-option bauergroup.services

# Template prüfen: welches Template passt?
# desktop-dev:   bauergroup.params.dev.*
# desktop-kiosk: bauergroup.params.kiosk.*
# server:        bauergroup.params.server.*
```

### Docker Compose Service startet nicht

```bash
# Service-Status prüfen
systemctl status compose-webapp

# Logs anzeigen
journalctl -u compose-webapp -f

# Docker-Compose direkt testen
cd /opt/webapp
docker-compose up

# Häufige Ursachen:
# 1. docker-compose.yml fehlt im Verzeichnis
# 2. .env Datei fehlt oder falsche Berechtigungen
# 3. Docker-Images nicht verfügbar (Netzwerk?)
```

## System-Probleme

### Boot-Fehler

```bash
# Im GRUB/systemd-boot Menü: ältere Generation auswählen
# Dann die fehlerhafte Config reparieren und neu deployen

# Oder: von USB-Stick booten und chroot
sudo mount /dev/sda2 /mnt
sudo mount /dev/sda1 /mnt/boot
sudo nixos-enter --root /mnt
nixos-rebuild switch --rollback
```

### Shutdown hängt (Service stoppt nicht)

```bash
# Hängenden Service identifizieren
systemctl list-jobs

# Service forcieren
sudo systemctl stop SERVICENAME --force

# Default-Timeout verkürzen (in params.nix oder Template)
# systemd.extraConfig = "DefaultTimeoutStopSec=30s";
```

### Disk voll

```bash
# Nix Garbage Collection
sudo nix-collect-garbage -d

# Alte Generationen löschen (älter als 7 Tage)
sudo nix-collect-garbage --delete-older-than 7d

# Store optimieren (Hardlinks für identische Dateien)
sudo nix-store --optimise

# Docker aufräumen
sudo docker system prune -a --volumes
```

### Paket nicht gefunden

```bash
# In nixpkgs suchen
nix search nixpkgs packagename

# Unstable-Kanal verwenden (in Nix-Modulen)
# pkgs.unstable.packagename

# Temporär in nix-shell testen
nix shell nixpkgs#packagename
```

## Monitoring-Probleme

### Node Exporter antwortet nicht

```bash
# Service prüfen
systemctl status prometheus-node-exporter

# Port prüfen
ss -tlnp | grep 9100

# Firewall prüfen (Port 9100 muss offen sein)
sudo iptables -L INPUT -n | grep 9100
```

### Grafana nicht erreichbar

```bash
# Service prüfen
systemctl status grafana

# Default-Port: 3100
curl http://localhost:3100/api/health
```

## Nix Debugging

### REPL verwenden

```bash
nix repl
:lf .                                    # Flake laden

# Konfiguration inspizieren (ohne --impure nicht möglich für Templates)
# Stattdessen: einzelne Module testen
:e ./modules/params.nix                  # Datei im Editor öffnen
builtins.attrNames (import ./overlays { nixpkgs-unstable = inputs.nixpkgs-unstable; })
```

### Optionen suchen

```bash
# Welche Optionen sind verfügbar?
nixos-option bauergroup.params
nixos-option bauergroup.params.user
nixos-option bauergroup.services.docker

# Online: https://search.nixos.org/options
```

### Build-Unterschiede anzeigen

```bash
# Vor und nach einer Änderung vergleichen
nixos-rebuild build --flake .#server --impure
nix-diff /run/current-system ./result
```

## Nützliche Links

- [NixOS Options Search](https://search.nixos.org/options)
- [NixOS Packages Search](https://search.nixos.org/packages)
- [NixOS Wiki](https://wiki.nixos.org)
- [Nix Pills (Tutorial)](https://nixos.org/guides/nix-pills/)
- [agenix Dokumentation](https://github.com/ryantm/agenix)
- [Home Manager Options](https://nix-community.github.io/home-manager/options.html)
