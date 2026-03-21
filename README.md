# BAUER GROUP — NixOS Infrastructure

Deklarative, reproduzierbare Infrastruktur für BAUER GROUP.  
Ein Flake, alle Maschinen — Desktop, Production Server, Embedded Dev.

## Quickstart

```bash
# 1. Clone
git clone <this-repo> ~/bauer-nix && cd ~/bauer-nix

# 2. Desktop lokal deployen (nach NixOS-Installation)
sudo nixos-rebuild switch --flake .#karl-desktop

# 3. Production Server deployen (remote via Colmena)
nix develop          # Dev Shell mit allen Tools
colmena apply --on @production

# 4. Einzelnen Server deployen
colmena apply --on prod-server-01
# oder direkt:
nixos-rebuild switch --flake .#prod-server-01 \
  --target-host root@10.0.0.1 --build-host localhost
```

## Repo-Struktur

```
bauer-nix/
├── flake.nix                          # Entry Point — alle Inputs & Outputs
├── flake.lock                         # Gelockte Dependency-Versionen
│
├── modules/
│   ├── baseline/                      # Globale Defaults (alle Maschinen)
│   │   ├── ntp.nix                    #   Chrony + PTB Zeitserver
│   │   ├── ssh.nix                    #   Gehärteter SSH (Key-only, Ed25519)
│   │   ├── users.nix                  #   User Accounts + sudo
│   │   ├── networking.nix             #   Firewall, DNS, BBR, Sysctl
│   │   └── nix.nix                    #   Flakes, Caches, GC, System Packages
│   │
│   ├── roles/                         # Rollen (komponieren Baselines)
│   │   ├── server.nix                 #   Production: Baselines + Fail2ban + Audit
│   │   ├── desktop-dev.nix            #   Desktop: Server + GUI + Dev Tools
│   │   └── embedded-dev.nix           #   Embedded: Latest Kernel + CAN-Bus + Toolchains
│   │
│   └── services/                      # Opt-in Services
│       ├── docker.nix                 #   Docker Engine + Compose + Prune
│       └── outline.nix                #   Outline Wiki (Docker Compose wrapper)
│
├── hosts/                             # Host-spezifische Konfiguration
│   ├── karl-desktop/
│   │   ├── default.nix                #   Hostname, Boot, GPU, Overrides
│   │   └── hardware-configuration.nix #   Hardware (von nixos-generate-config)
│   ├── prod-server-01/
│   │   └── default.nix
│   └── prod-server-02/
│       └── default.nix
│
├── home/                              # Home Manager (User-Level Config)
│   ├── common.nix                     #   Git, Zsh, Starship, Direnv, Aliases
│   └── karl.nix                       #   Karls persönliche Config
│
└── docs/                              # Dokumentation
    ├── getting-started.md
    ├── adding-hosts.md
    ├── deployment.md
    ├── canbus.md
    ├── secrets.md
    └── troubleshooting.md
```

## Architektur-Prinzipien

### Modulare Vererbung

```
baseline/*  →  roles/server.nix  →  roles/desktop-dev.nix
                                  →  roles/embedded-dev.nix
```

- **Baseline-Module** setzen Defaults via `lib.mkDefault` → jeder Host kann overriden
- **Rollen** komponieren Baselines + fügen rollenspezifische Config hinzu
- **Services** sind opt-in Module, die per Host zugeschaltet werden
- **Hosts** definieren Hardware, Netzwerk, und wählen Rollen/Services

### Kernel-Strategie

| Rolle | Kernel | Grund |
|-------|--------|-------|
| `server.nix` | LTS (`linuxPackages`) | Stabilität, ZFS-Kompatibilität |
| `desktop-dev.nix` | LTS (erbt von server) | Stabilität |
| `embedded-dev.nix` | Latest (`linuxPackages_latest`) | Neueste CAN-Bus Treiber |

### Override-Hierarchie

```
lib.mkDefault (schwächster)  →  normaler Wert  →  lib.mkForce (stärkster)
```

Baseline setzt `mkDefault`, Rollen setzen normale Werte, Hosts nutzen `mkForce` nur wenn nötig.

## Nächste Schritte

1. [Getting Started](docs/getting-started.md) — NixOS installieren & erste Config
2. [Adding Hosts](docs/adding-hosts.md) — Neuen Server/Desktop hinzufügen
3. [Deployment](docs/deployment.md) — Colmena, nixos-rebuild, nixos-anywhere
4. [CAN-Bus Development](docs/canbus.md) — SocketCAN Setup & Tooling
5. [Secrets Management](docs/secrets.md) — agenix für Passwörter & Keys
6. [Troubleshooting](docs/troubleshooting.md) — Häufige Probleme & Lösungen
