# BAUER GROUP — NixOS Infrastructure

Parametrische NixOS-Templates für die gesamte Infrastruktur.
Vier Templates, eine Parameterdatei pro Maschine — fertig.

## Templates

| Template         | Befehl                                                   | Beschreibung                                                   |
| ---------------- | -------------------------------------------------------- | -------------------------------------------------------------- |
| `desktop-dev`    | `nixos-rebuild switch --flake .#desktop-dev --impure`    | Entwickler-Desktop (KDE Plasma 6, Dev-Tools, optional CAN-Bus) |
| `desktop-kiosk`  | `nixos-rebuild switch --flake .#desktop-kiosk --impure`  | Kiosk-Display auf Standard-Hardware (Foyer, Dashboard)         |
| `embedded-kiosk` | `nixos-rebuild switch --flake .#embedded-kiosk --impure` | HMI an der Anlage — kein Selbst-Reboot, flash-schonend         |
| `server`         | `nixos-rebuild switch --flake .#server --impure`         | Headless Server (Container-Services, gehärtet, Monitoring)     |

Beide Kiosk-Templates zeigen wahlweise eine **Web-UI** (Chromium nativ auf
Wayland) oder eine **native App** (.NET/Avalonia, Qt) im Vollbild — siehe
[Kiosk & HMI](docs/kiosk.md).

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
│   ├── desktop-kiosk.nix          #   Kiosk-Display (Standard-Hardware)
│   ├── embedded-kiosk.nix         #   HMI an der Anlage (Panel-PC)
│   └── server.nix                 #   Headless Server
│
├── modules/
│   ├── params.nix                 # Parametertypen + Validierung
│   ├── baseline/                  # Geteilte Grundkonfiguration
│   │   ├── auto-update.nix        #   Tägliches Auto-Update von GitHub
│   │   ├── networking.nix         #   Firewall, DNS, IP (aus params)
│   │   ├── nix.nix                #   Flakes, Caches, GC
│   │   ├── ntp.nix                #   Chrony (time.bauer-group.com)
│   │   ├── platform.nix           #   Engine, Watchdog, Splash (aus params)
│   │   ├── ssh.nix                #   Gehärtetes SSH (Ed25519-only)
│   │   └── users.nix              #   User-Accounts (aus params)
│   ├── features/                  # Opt-in Feature-Module
│   │   ├── branding.nix           #   Boot-Splash (Plymouth)
│   │   ├── embedded-dev.nix       #   CAN-Bus / SocketCAN
│   │   └── kiosk.nix              #   params → Kiosk-Runtime + Policy
│   └── services/                  # Opt-in Services (mkOption)
│       ├── backup.nix             #   Restic Backup
│       ├── containers.nix         #   Container-Engine (Docker | Podman)
│       ├── kiosk.nix              #   cage-Session (Browser | native App)
│       ├── monitoring.nix         #   Prometheus + Grafana
│       └── watchdog.nix           #   Hardware- + Freeze-Watchdog
│
├── home/                          # Home Manager (User-Dotfiles)
│   ├── common.nix                 #   Git, Zsh, Starship, Direnv
│   └── user.nix                   #   Parametrische User-Config
│
├── pkgs/                          # Eigene Pakete
│   └── plymouth-theme-bauergroup/ #   Boot-Splash aus dem Marken-SVG
│
├── assets/branding/               # Logo-Quellen (SVG)
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
┌─ templates/*.nix ────────────────────────────────────────────┐
│  desktop-dev │ desktop-kiosk │ embedded-kiosk │ server       │
│  ┌────────────────────────────────────────────────────────┐  │
│  │ modules/baseline/*  SSH, NTP, FW, Engine, Watchdog      │  │
│  │ modules/services/*  Kiosk, Container, Monitoring, Backup│  │
│  │ modules/features/*  Kiosk-Policy, Branding, CAN-Bus     │  │
│  │ home/user.nix       Zsh, Git, Neovim                    │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
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
| [Kiosk & HMI](docs/kiosk.md)                   | Browser- und App-Kiosk, Watchdog, Splash     |
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
