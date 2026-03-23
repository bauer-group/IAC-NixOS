# Automatische Prozesse

## Uebersicht

Jede Maschine fuehrt automatisch folgende Prozesse aus:

### Auf jeder Maschine

| Prozess | Zeitpunkt | Was passiert |
| --- | --- | --- |
| **Auto-Update** | Taeglich 03:00 | Pulled neueste Config + Pakete von GitHub, rebuild, reboot bei Bedarf |
| **Nix Garbage Collection** | Woechentlich | Loescht unbenutzte Pakete aelter als 7 Tage |
| **Docker Auto-Prune** | Woechentlich | Entfernt unbenutzte Docker Images aelter als 7 Tage |
| **Restic Backup** | Taeglich (wenn aktiviert) | Sichert /opt, /var/lib, /home auf Backup-Server |
| **Chrony NTP** | Permanent | Zeitsynchronisation mit time.bauer-group.com |
| **Fail2ban** | Permanent | Blockiert SSH Brute-Force (5 Versuche → 1h Ban) |

### In GitHub (CI/CD)

| Prozess | Zeitpunkt | Was passiert |
| --- | --- | --- |
| **🧹 CI** | Bei Push/PR auf main | Linting (deadnix) |
| **🎨 Format** | Manuell | Formatiert alle .nix Dateien |
| **🔄 Flake Update** | Sonntag 02:00 UTC | Erstellt PR mit aktualisierten Paketversionen |
| **🚀 Release** | Bei Push auf main | Semantic Versioning + Changelog |
| **📢 Teams** | Bei Events | Benachrichtigungen an Microsoft Teams |

## Auto-Update

### Wie es funktioniert

```text
03:00  Maschine pulled github:bauer-group/IAC-NixOS (main branch)
  │
  ├─ Keine Aenderungen? → Nichts passiert
  │
  └─ Aenderungen gefunden?
       │
       ├─ nixos-rebuild switch --flake ... --impure
       │
       ├─ Kernel/systemd geaendert?
       │    └─ JA → Reboot im Fenster 03:00-03:30
       │
       └─ Nur Pakete/Config?
            └─ Kein Reboot noetig, sofort aktiv
```

### Konfiguration

Auto-Update ist **standardmaessig aktiviert** fuer alle Maschinen. In `/etc/nixos/params.nix`:

```nix
bauergroup.params.autoUpdate = {
  enable = true;                                      # Default: true
  flake = "github:bauer-group/IAC-NixOS";             # Quelle
  schedule = "03:00";                                  # Taeglich um 03:00
  allowReboot = true;                                  # Auto-Reboot erlaubt
  rebootWindowStart = "03:00";                         # Fruehester Reboot
  rebootWindowEnd = "03:30";                           # Spaetester Reboot
};
```

### Deaktivieren (z.B. fuer Testzwecke)

```nix
bauergroup.params.autoUpdate.enable = false;
```

### Was wird aktualisiert?

1. **NixOS Pakete** — Sicherheitsupdates, Bugfixes aus dem nixos-25.11 Channel
2. **Repo-Aenderungen** — Neue Module, geaenderte Templates, Konfigurationsaenderungen
3. **Flake Inputs** — Wenn jemand `nix flake update` committet (nixpkgs, home-manager, etc.)

### Ablauf eines Updates

```bash
# Das passiert automatisch — kein manueller Eingriff noetig:
# 1. systemd Timer triggert um 03:00
# 2. nixos-rebuild switch --flake github:bauer-group/IAC-NixOS --impure
# 3. /etc/nixos/params.nix wird gelesen (maschinenspezifische Werte)
# 4. System wird neu gebaut und aktiviert
# 5. Reboot nur wenn Kernel/systemd sich geaendert haben
```

### Logs pruefen

```bash
# Status des Auto-Update Timers
systemctl status nixos-upgrade.timer

# Letzte Update-Logs
journalctl -u nixos-upgrade.service -n 50

# Naechster geplanter Run
systemctl list-timers | grep nixos-upgrade
```

### Manuelles Update erzwingen

```bash
# Sofort updaten (nicht auf Timer warten)
sudo systemctl start nixos-upgrade.service

# Oder manuell mit vollem Output
sudo nixos-rebuild switch --flake github:bauer-group/IAC-NixOS --impure
```

## Nix Garbage Collection

Alte Pakete und NixOS-Generationen werden automatisch bereinigt.

```bash
# Konfiguriert in modules/baseline/nix.nix:
# nix.gc.automatic = true
# nix.gc.dates = "weekly"
# nix.gc.options = "--delete-older-than 7d"

# Manuell ausfuehren
sudo nix-collect-garbage -d

# Speicherverbrauch pruefen
du -sh /nix/store
```

## Docker Auto-Prune

Unbenutzte Docker Images und Container werden woechentlich bereinigt.

```bash
# Konfiguriert in modules/services/docker.nix:
# autoPrune.enable = true
# autoPrune.dates = "weekly"
# autoPrune.flags = ["--all" "--filter" "until=168h"]

# Status pruefen
systemctl list-timers | grep docker-prune

# Manuell ausfuehren
sudo docker system prune -a --filter "until=168h"
```

## Restic Backup (optional)

Nur aktiv wenn in `params.nix` konfiguriert:

```nix
bauergroup.params.server.backup = {
  enable = true;
  repository = "sftp:backup@storage:/backups/hostname";
  passwordFile = /run/agenix/restic-password;
};
```

```bash
# Status pruefen
systemctl status restic-backups-system.timer

# Letzte Backup-Logs
journalctl -u restic-backups-system.service -n 50

# Snapshots anzeigen
sudo restic -r sftp:backup@storage:/backups/hostname snapshots

# Manuelles Backup
sudo systemctl start restic-backups-system.service
```

## Zeitsynchronisation (Chrony)

Alle Maschinen synchronisieren ueber `time.bauer-group.com` mit `de.pool.ntp.org` als Fallback.

```bash
# Status pruefen
chronyc tracking

# Quellen anzeigen
chronyc sources -v

# Zeitdifferenz
chronyc makestep  # Erzwingt sofortige Korrektur
```

## Monitoring (Node Exporter)

Auf Servern und Kiosks laeuft standardmaessig der Prometheus Node Exporter (Port 9100).

```bash
# Status pruefen
systemctl status prometheus-node-exporter

# Metriken abrufen
curl -s http://localhost:9100/metrics | head -20
```

## Fail2ban

SSH Brute-Force-Schutz auf Servern und Kiosks.

```bash
# Status und gebannte IPs
sudo fail2ban-client status sshd

# IP manuell entsperren
sudo fail2ban-client set sshd unbanip 1.2.3.4

# Logs
journalctl -u fail2ban.service -n 50
```

## Woechentliches Flake Update (Paket-Updates)

Config-Aenderungen werden sofort deployed (naechster 03:00 Zyklus). Aber **Paketversionen** (nixpkgs, home-manager, etc.) sind im `flake.lock` gepinnt und aendern sich erst nach `nix flake update`.

Der **🔄 Flake Update** Workflow automatisiert das:

```text
Sonntag 02:00 UTC
  │
  ├─ nix flake update (aktualisiert flake.lock)
  │
  ├─ Keine Aenderungen? → Nichts passiert
  │
  └─ Neue Versionen?
       │
       └─ Erstellt Pull Request "🔄 Weekly Flake Update"
          mit Changelog der aktualisierten Inputs
```

### Warum ein PR statt direkt auf main?

- **Review moeglich** — bei Breaking Changes kann man den PR ablehnen
- **CI laeuft** — Linting wird geprueft bevor gemergt wird
- **Rollback einfach** — PR revert statt flake.lock manuell zuruecksetzen

### Manuell triggern

GitHub Actions → 🔄 Flake Update → Run workflow

### Was wird aktualisiert?

| Input | Channel | Was aendert sich |
| --- | --- | --- |
| nixpkgs | nixos-25.11 | Sicherheitspatches, Bugfixes, Paketversionen |
| nixpkgs-unstable | nixos-unstable | Bleeding-edge Pakete (nur via pkgs.unstable.*) |
| home-manager | release-25.11 | User-Config Module |
| agenix | latest | Secrets Management |
| disko | latest | Disk Partitioning |
| colmena | latest | Fleet Deployment |
| treefmt-nix | latest | Code Formatter |
| git-hooks-nix | latest | Pre-Commit Hooks |

## Gesamter Update-Zyklus

```text
Sonntag 02:00    🔄 Flake Update erstellt PR mit neuen Paketversionen
Montag           Entwickler reviewt + merged PR (oder auto-merge)
Dienstag 03:00   Alle Maschinen rebuilden mit neuen Paketen
```

Config-Aenderungen sind schneller:

```text
Jederzeit        Entwickler pusht Config-Aenderung auf main
Naechste 03:00   Alle Maschinen rebuilden automatisch
```

Fuer dringende Aenderungen — nicht auf Timer warten:

```bash
# Einzelne Maschine sofort updaten
ssh root@MACHINE "systemctl start nixos-upgrade.service"

# Oder direkt
nixos-rebuild switch --flake github:bauer-group/IAC-NixOS \
  --target-host root@MACHINE --impure
```
