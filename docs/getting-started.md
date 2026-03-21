# Getting Started — NixOS für BAUER GROUP

## Voraussetzungen

- Ein x86_64-Rechner (physisch oder VM)
- USB-Stick (≥4 GB) für die Installation
- Grundlegende Linux-Kenntnisse

## 1. NixOS installieren

### ISO herunterladen

```bash
# Aktuelles ISO (Plasma Desktop — für graphische Installation)
wget https://channels.nixos.org/nixos-25.11/latest-nixos-plasma6-x86_64-linux.iso

# Auf USB-Stick schreiben
sudo dd bs=4M conv=fsync oflag=direct status=progress \
  if=latest-nixos-plasma6-x86_64-linux.iso of=/dev/sdX
```

### Installation durchführen

1. Vom USB-Stick booten
2. Graphischen Installer starten (oder manuell via CLI)
3. Partitionierung wählen (EFI + Root, optional Swap)
4. Installation abschließen, reboot

### Nach der Installation: Flakes aktivieren

```bash
# Temporär Flakes aktivieren
export NIX_CONFIG="experimental-features = nix-command flakes"

# Git installieren (wird für Flakes benötigt)
nix-env -iA nixos.git
```

## 2. Dieses Repo einrichten

```bash
# Repo clonen
git clone <repo-url> ~/bauer-nix
cd ~/bauer-nix

# Hardware-Config generieren und einfügen
nixos-generate-config --show-hardware-config > hosts/karl-desktop/hardware-configuration.nix
```

### Anpassen

1. **`hosts/karl-desktop/hardware-configuration.nix`** — wurde gerade generiert
2. **`hosts/karl-desktop/default.nix`** — Boot-Loader, GPU, Netzwerk prüfen
3. **`home/karl.nix`** — Git-Name, E-Mail, SSH-Keys eintragen
4. **`modules/baseline/users.nix`** — SSH Public Key eintragen

## 3. Erstes Deployment

```bash
cd ~/bauer-nix

# Erst nur bauen (ohne zu aktivieren) — prüft auf Fehler
nixos-rebuild build --flake .#karl-desktop

# Wenn erfolgreich: aktivieren
sudo nixos-rebuild switch --flake .#karl-desktop
```

Nach dem Reboot läuft dein System komplett aus der deklarativen Config.

## 4. Workflow im Alltag

### Änderungen machen

```bash
# Config editieren
vim modules/roles/desktop-dev.nix

# Testen (aktiviert, aber kein Boot-Eintrag)
sudo nixos-rebuild test --flake .#karl-desktop

# Wenn gut: permanent aktivieren
sudo nixos-rebuild switch --flake .#karl-desktop

# Committen
git add -A && git commit -m "feat: add package X to desktop"
```

### Rollback

```bash
# Vorherige Generation booten (im Boot-Menü oder):
sudo nixos-rebuild switch --rollback

# Alle Generationen anzeigen
nix profile history --profile /nix/var/nix/profiles/system
```

### Updates

```bash
# Alle Flake-Inputs updaten (nixpkgs, home-manager, etc.)
nix flake update

# Nur nixpkgs updaten
nix flake update nixpkgs

# Danach neu bauen
sudo nixos-rebuild switch --flake .#karl-desktop

# Commit lock file
git add flake.lock && git commit -m "chore: update flake inputs"
```

## 5. Nix Shell für Projekte

Statt global Pakete zu installieren, nutze projektspezifische Shells:

```bash
# Temporäre Shell mit bestimmten Paketen
nix shell nixpkgs#nodejs_22 nixpkgs#pnpm

# Oder: flake.nix im Projektordner
# Dann reicht `nix develop` oder automatisch via direnv
```

### Beispiel: `flake.nix` für ein Node.js-Projekt

```nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  outputs = { nixpkgs, ... }:
    let pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in {
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = with pkgs; [ nodejs_22 nodePackages.pnpm ];
      };
    };
}
```

## Wichtige Befehle — Cheat Sheet

| Befehl | Beschreibung |
|--------|-------------|
| `sudo nixos-rebuild switch --flake .#host` | Config aktivieren |
| `sudo nixos-rebuild test --flake .#host` | Config testen (kein Boot-Eintrag) |
| `sudo nixos-rebuild build --flake .#host` | Nur bauen |
| `sudo nixos-rebuild switch --rollback` | Rollback auf vorherige Generation |
| `nix flake update` | Alle Inputs updaten |
| `nix flake show` | Flake-Outputs anzeigen |
| `nix repl` dann `:lf .` | Interaktiv Config inspizieren |
| `nix develop` | Dev Shell betreten |
| `nix shell nixpkgs#paket` | Temporär ein Paket nutzen |
| `nix search nixpkgs paketname` | Pakete suchen |
| `nixos-option services.openssh.enable` | Option-Doku anzeigen |
