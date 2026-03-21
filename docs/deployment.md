# Deployment

## Deployment-Methoden im Überblick

| Methode | Wann nutzen | Parallelismus | Rollback |
|---------|------------|---------------|----------|
| `nixos-rebuild` | Lokal oder einzelner Remote-Host | Nein | Ja (manuell) |
| **Colmena** | Mehrere Server, Tags/Gruppen | Ja | Ja (automatisch) |
| `nixos-anywhere` | Erstinstallation von Null | N/A | N/A |
| `deploy-rs` | Alternative zu Colmena, kein Root nötig | Ja | Ja (automatisch) |

## Colmena (empfohlen für Fleet Management)

### Setup

Colmena ist bereits im `devShells` des Flakes enthalten:

```bash
cd ~/bauer-nix
nix develop    # Startet Shell mit colmena, agenix, etc.
```

### Befehle

```bash
# Alle Production-Server deployen
colmena apply --on @production

# Einzelnen Host
colmena apply --on prod-server-01

# Nur bauen (ohne zu deployen)
colmena build

# Deployment-Plan anzeigen (dry-run)
colmena apply --on @production --evaluator streaming

# Nur auf erreichbare Hosts deployen
colmena apply --on @production --keep-result

# Parallele Builds (default: alle gleichzeitig)
colmena apply --on @production --parallel 4
```

### Tags

Tags werden in der Colmena-Config pro Host gesetzt:

```nix
prod-server-01 = {
  deployment.tags = [ "production" "hetzner" "germany" ];
  # ...
};
```

Dann filtern:
```bash
colmena apply --on @production          # Alle mit Tag "production"
colmena apply --on @hetzner             # Alle Hetzner-Server
colmena apply --on prod-server-01       # Einzelner Host
```

## nixos-rebuild (Remote)

Für einzelne Hosts ohne Colmena:

```bash
# Lokal bauen, remote deployen
nixos-rebuild switch \
  --flake .#prod-server-01 \
  --target-host root@10.0.0.1 \
  --build-host localhost

# Remote bauen und deployen (wenn Server genug RAM/CPU hat)
nixos-rebuild switch \
  --flake .#prod-server-01 \
  --target-host root@10.0.0.1 \
  --build-host root@10.0.0.1

# Nur testen (kein Boot-Eintrag)
nixos-rebuild test \
  --flake .#prod-server-01 \
  --target-host root@10.0.0.1
```

## nixos-anywhere (Erstinstallation)

Für neue Server, auf denen noch kein NixOS läuft:

### Voraussetzungen

- SSH-Zugang zum Zielserver (als root)
- Server hat ≥1 GB RAM
- disko-Config im Host definiert (siehe `hosts/prod-server-01/default.nix`)

### Ausführung

```bash
# Aus dem Repo-Root:
nix run github:nix-community/nixos-anywhere -- \
  --flake .#prod-server-01 \
  root@1.2.3.4

# Mit disko disk-config:
nix run github:nix-community/nixos-anywhere -- \
  --flake .#prod-server-01 \
  --disk-encryption-keys /tmp/secret.key <(echo "mein-passwort") \
  root@1.2.3.4
```

### Was passiert

1. Server bootet in RAM-basiertes NixOS (via kexec)
2. disko partitioniert und formatiert die Disks
3. NixOS wird installiert
4. Server rebootet in fertiges System

## Deployment-Workflow (Best Practice)

```
1. Änderung machen
   └─ vim modules/services/docker.nix

2. Lokal bauen & prüfen
   └─ nix flake check
   └─ nixos-rebuild build --flake .#prod-server-01

3. Auf Staging testen (optional)
   └─ colmena apply --on staging-server

4. Committen
   └─ git add -A && git commit -m "feat: update docker config"

5. Production deployen
   └─ colmena apply --on @production

6. Verifizieren
   └─ colmena exec --on @production -- systemctl status docker

7. Bei Problemen: Rollback
   └─ colmena apply --on @production -- switch --rollback
   └─ oder: auf dem Server direkt:
      nixos-rebuild switch --rollback
```

## CI/CD (optional)

Für automatisiertes Deployment via GitHub Actions / GitLab CI:

```yaml
# .github/workflows/deploy.yml (Beispiel)
name: Deploy
on:
  push:
    branches: [main]
jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v27
        with:
          extra_nix_config: |
            experimental-features = nix-command flakes
      - run: nix build .#nixosConfigurations.prod-server-01.config.system.build.toplevel
      # Eigentliches Deployment nur manuell triggern (safety)
```

## Remote-Befehle ausführen

```bash
# Befehl auf allen Production-Servern
colmena exec --on @production -- systemctl status docker

# Uptime aller Server
colmena exec --on @production -- uptime

# NixOS-Version prüfen
colmena exec --on @production -- nixos-version
```
