# Deployment

## Deployment-Methoden

| Methode          | Wann nutzen                                | Rollback                    |
| ---------------- | ------------------------------------------ | --------------------------- |
| `nixos-rebuild`  | Einzelne Maschine, lokal oder remote       | Boot-Menü oder `--rollback` |
| `nixos-anywhere` | Neue Maschine von Grund auf provisionieren | Neuinstallation             |

## nixos-rebuild (Standard)

### Lokal auf der Zielmaschine

```bash
cd /pfad/zum/repo
sudo nixos-rebuild switch --flake .#server --impure
```

### Remote von einer anderen Maschine

```bash
nixos-rebuild switch --flake .#server \
  --target-host root@10.0.0.5 \
  --build-host localhost \
  --impure
```

- `--target-host`: SSH-Ziel (die Maschine die konfiguriert wird)
- `--build-host`: Wo der Build stattfindet (lokal oder remote)
- `--impure`: Nötig damit `/etc/nixos/params.nix` auf dem Target gelesen wird

### Testen ohne Commitment

```bash
# Test: Aktiviert die Config, aber beim nächsten Reboot wird zurückgesetzt
sudo nixos-rebuild test --flake .#server --impure

# Build: Nur bauen, nicht aktivieren (zum Prüfen ob es kompiliert)
nixos-rebuild build --flake .#server --impure
```

## nixos-anywhere (Neuinstallation)

Provisioniert einen bestehenden Linux-Server komplett mit NixOS — bootet in ein RAM-NixOS, partitioniert, installiert:

```bash
nix run github:nix-community/nixos-anywhere -- \
  --flake .#server \
  root@IP_ADRESSE
```

**Voraussetzungen:**

- SSH-Root-Zugang zum Zielserver
- Server hat mindestens 1 GB RAM
- `/etc/nixos/params.nix` muss auf dem Ziel vorhanden sein (vorher per SCP kopieren)

## Deployment-Workflow (Best Practice)

```bash
# 1. Änderungen im Repo machen (lokal)
vim templates/server.nix
vim modules/services/docker.nix

# 2. Formatierung prüfen
nix fmt

# 3. Linting prüfen
nix flake check

# 4. Auf einer Test-Maschine testen
nixos-rebuild test --flake .#server --impure \
  --target-host root@test-server

# 5. Committen
git add -A && git commit -m "feat: update docker config"

# 6. Auf Produktion deployen
nixos-rebuild switch --flake .#server --impure \
  --target-host root@prod-server

# 7. Verifizieren
./scripts/health-check.sh prod-server

# 8. Bei Problemen: Rollback
nixos-rebuild switch --rollback --target-host root@prod-server
```

## Rollback

### Via Boot-Menü

Beim Booten zeigt der Bootloader (systemd-boot oder GRUB) die letzten Generationen. Ältere Generation auswählen → System startet mit der vorherigen Konfiguration.

### Via CLI

```bash
# Zur letzten Generation zurückkehren
sudo nixos-rebuild switch --rollback

# Alle Generationen anzeigen
sudo nix-env --list-generations -p /nix/var/nix/profiles/system

# Bestimmte Generation aktivieren
sudo nix-env --switch-generation 42 -p /nix/var/nix/profiles/system
sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch
```

## Post-Deployment Health Check

```bash
# Von einem anderen Rechner aus
./scripts/health-check.sh 10.0.0.5

# Prüft:
# ✓ SSH erreichbar
# ✓ System gebootet
# ✓ Keine fehlgeschlagenen Services
# ✓ Disk < 85% voll
# ✓ Docker läuft (falls aktiviert)
# ✓ Firewall aktiv
# ✓ DNS funktioniert
# ✓ Node Exporter antwortet (falls Monitoring)
```

## Mehrere Maschinen parallel

Für Fleet-Deployment (viele Maschinen gleichzeitig) kann ein einfaches Shell-Script verwendet werden:

```bash
#!/usr/bin/env bash
SERVERS=("10.0.0.1" "10.0.0.2" "10.0.0.3")
TEMPLATE="server"

for srv in "${SERVERS[@]}"; do
  echo "Deploying to $srv..."
  nixos-rebuild switch --flake .#$TEMPLATE \
    --target-host "root@$srv" \
    --build-host localhost \
    --impure &
done
wait

for srv in "${SERVERS[@]}"; do
  ./scripts/health-check.sh "$srv"
done
```

## Updates

```bash
# Flake-Inputs aktualisieren (nixpkgs, home-manager, etc.)
nix flake update

# Prüfen was sich ändert
nix flake lock --update-input nixpkgs
nixos-rebuild build --flake .#server --impure
nix-diff /run/current-system ./result  # Unterschiede anzeigen

# Deployen
sudo nixos-rebuild switch --flake .#server --impure
```
