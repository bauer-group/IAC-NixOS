# BAUER GROUP — NixOS Infrastructure

Parametrische NixOS-Templates für die gesamte Infrastruktur.
Drei Templates, eine Parameterdatei pro Maschine — fertig.

## Templates

| Template        | Befehl                                                  | Beschreibung                                                   |
| --------------- | ------------------------------------------------------- | -------------------------------------------------------------- |
| `desktop-dev`   | `nixos-rebuild switch --flake .#desktop-dev --impure`   | Entwickler-Desktop (KDE Plasma 6, Dev-Tools, optional CAN-Bus) |
| `desktop-kiosk` | `nixos-rebuild switch --flake .#desktop-kiosk --impure` | Kiosk-Display (Fullscreen-Browser + Docker-Backend)            |
| `server`        | `nixos-rebuild switch --flake .#server --impure`        | Headless Server (Docker-Services, gehärtet, Monitoring)        |

## Quickstart

```bash
# 1. Repo klonen
git clone git@github.com:bauer-group/nixos.git
cd nixos

# 2. Hardware-Konfiguration generieren (auf der Zielmaschine)
nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix

# 3. Parameterdatei erstellen
cp params.example.nix /etc/nixos/params.nix
vim /etc/nixos/params.nix    # Werte anpassen

# 4. Template deployen
sudo nixos-rebuild switch --flake .#server --impure
```

## Struktur

```
├── templates/                     # NixOS-Konfigurationsprofile
│   ├── desktop-dev.nix            #   Entwickler-Desktop
│   ├── desktop-kiosk.nix          #   Kiosk-Display
│   └── server.nix                 #   Headless Server
│
├── modules/
│   ├── params.nix                 # Parametertypen + Validierung
│   ├── baseline/                  # Geteilte Grundkonfiguration
│   │   ├── auto-update.nix        #   Tägliches Auto-Update von GitHub
│   │   ├── networking.nix         #   Firewall, DNS, IP (aus params)
│   │   ├── nix.nix                #   Flakes, Caches, GC
│   │   ├── ntp.nix                #   Chrony (time.bauer-group.com)
│   │   ├── ssh.nix                #   Gehärtetes SSH (Ed25519-only)
│   │   └── users.nix              #   User-Accounts (aus params)
│   ├── features/                  # Opt-in Feature-Module
│   │   └── embedded-dev.nix       #   CAN-Bus / SocketCAN
│   └── services/                  # Opt-in Services (mkOption)
│       ├── docker.nix             #   Docker Engine
│       ├── monitoring.nix         #   Prometheus + Grafana
│       └── backup.nix             #   Restic Backup
│
├── home/                          # Home Manager (User-Dotfiles)
│   ├── common.nix                 #   Git, Zsh, Starship, Direnv
│   └── user.nix                   #   Parametrische User-Config
│
├── overlays/                      # Nix Overlays
├── tests/                         # NixOS VM-Integrationstests
├── scripts/health-check.sh        # Post-Deployment Prüfung
├── secrets/                       # agenix Secrets-Verwaltung
├── params.example.nix             # Referenz-Parameterdatei
└── docs/                          # Dokumentation
```

## Architektur

```
/etc/nixos/params.nix (Werte)     params.example.nix (Referenz)
         │                                  │
         ▼                                  ▼
┌─ modules/params.nix ─────────────────────────┐
│  bauergroup.params.hostName, .user, .network, ... │
└──────────────────────────────────────────────┘
         │
         ▼
┌─ templates/*.nix ────────────────────────────┐
│  desktop-dev │ desktop-kiosk │ server        │
│  ┌───────────────────────────────────────┐   │
│  │ modules/baseline/* (SSH, NTP, FW, ...) │   │
│  │ modules/services/* (Docker, Backup)    │   │
│  │ modules/features/* (CAN-Bus)           │   │
│  │ home/user.nix (Zsh, Git, Neovim)       │   │
│  └───────────────────────────────────────┘   │
└──────────────────────────────────────────────┘
         │
         ▼
    nixos-rebuild switch --flake .#template --impure
```

## Dokumentation

| Dokument                                       | Inhalt                                       |
| ---------------------------------------------- | -------------------------------------------- |
| [Erste Schritte](docs/getting-started.md)      | Installation, erste Maschine einrichten      |
| [Maschine hinzufügen](docs/adding-machines.md) | Neue Maschine mit Template provisionieren    |
| [Deployment](docs/deployment.md)               | Deployment-Methoden und Workflows            |
| [Automatisierung](docs/automation.md)          | Auto-Update, GC, Backup, Monitoring          |
| [Secrets](docs/secrets.md)                     | agenix Setup, Secrets erstellen und rotieren |
| [CAN-Bus](docs/canbus.md)                      | SocketCAN, USB-Adapter, can-utils            |
| [Troubleshooting](docs/troubleshooting.md)     | Häufige Fehler und Lösungen                  |

## Code-Qualität

```bash
nix develop          # Dev-Shell mit allen Tools + Pre-Commit Hooks
nix fmt              # Formatierung (nixfmt, prettier, shfmt)
```

## Lizenz

MIT — BAUER GROUP
