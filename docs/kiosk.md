# Kiosk & HMI

## Überblick

Zwei Templates, eine gemeinsame Runtime:

| Template         | Einsatz                                              | Besonderheit                                           |
| ---------------- | ---------------------------------------------------- | ------------------------------------------------------ |
| `desktop-kiosk`  | Foyer-Display, Besprechungsraum, Shopfloor-Dashboard | Standard-PC-Hardware, Wartungsfenster, Auto-Reboot     |
| `embedded-kiosk` | Panel-PC an der Anlage (HMI)                         | Kein Selbst-Reboot, flash-schonend, Boot ohne Netzwerk |

Beide starten dieselbe Session: **cage**, ein Wayland-Compositor, der genau ein
Fenster im Vollbild zeigt und kein Fenstermanagement anbietet — nichts lässt
sich verschieben, minimieren oder schließen.

Was in diesem Fenster läuft, bestimmt `kiosk.mode`:

| Modus           | Inhalt                          | Grafik-Pfad                                |
| --------------- | ------------------------------- | ------------------------------------------ |
| `"browser"`     | Chromium auf `kiosk.url`        | Nativ Wayland (`--ozone-platform=wayland`) |
| `"application"` | Beliebige native App (.NET, Qt) | XWayland — cage setzt `DISPLAY` selbst     |

> **Warum kein Desktop-Environment?**
> Ein DE bringt Panels, Benachrichtigungen, Session-Manager und einen
> Display-Manager mit — alles Oberflächen, die ein Besucher oder Bediener
> erreichen kann und die im Fehlerfall zusätzlich abstürzen können. cage hat
> keine davon.

---

## Browser-Kiosk

Der Normalfall für Web-UIs (React/Vite-SPA, Grafana, Node-RED):

```nix
bauergroup.params.kiosk = {
  mode = "browser";
  url = "http://localhost:3000";
  touchscreen = true;
  rotation = "left";      # Portrait auf einem Landscape-Panel
  idleTimeout = 300;      # Nach 5 min ohne Eingabe zurück zur Startseite
};
```

Chromium läuft **nativ auf Wayland**, nicht über XWayland. Das ist für
Touch-Eingabe und VSync spürbar sauberer und war der Grund, cage einem
klassischen X11-Setup vorzuziehen.

Gesetzte Flags, die erfahrungsgemäß nötig sind:

| Flag                                                   | Grund                                                                |
| ------------------------------------------------------ | -------------------------------------------------------------------- |
| `--password-store=basic`                               | Ohne Keyring blockiert Chromium beim Start auf einem Passwort-Dialog |
| `--check-for-update-interval=31536000`                 | Chromium kann sich im Nix-Store ohnehin nicht selbst aktualisieren   |
| `--autoplay-policy=no-user-gesture-required`           | Signage spielt Medien ohne Klick                                     |
| `--disable-pinch`, `--overscroll-history-navigation=0` | Auf einem HMI ist eine Wischgeste ein Fehlgriff, keine Navigation    |

Zusätzliche Flags über `kiosk.extraFlags`.

---

## Application-Kiosk (.NET / Avalonia)

Avalonia nutzt unter Linux den **X11-Backend**. cage bringt XWayland mit und
setzt `DISPLAY` für seinen Kindprozess — die App muss also **nicht** portiert
werden. cage zwingt das erste Fenster ins Vollbild, die App muss das nicht
selbst anfordern.

### Weg A — Binary nach `/opt` (schnellster Weg)

```bash
dotnet publish -c Release -r linux-x64 --self-contained true -o ./publish
rsync -a --delete publish/ hmi-01:/opt/hmi/
```

```nix
bauergroup.params.kiosk = {
  mode = "application";
  application = {
    command = "/opt/hmi/BauerGroup.Hmi";
    foreignBinaries = true;                 # ← unverzichtbar, siehe unten
    environment.DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1";
  };
  healthCheckCommand = "/run/current-system/sw/bin/curl -sf --max-time 5 http://127.0.0.1:8080/healthz";
  extraGroups = [ "dialout" ];              # Serielle Verbindung zur SPS
};
```

> **`foreignBinaries = true` ist keine Option, sondern Pflicht.**
> Ein `dotnet publish`-Ergebnis ist gegen `/lib64/ld-linux-x86-64.so.2`
> gelinkt — einen Pfad, den es auf NixOS nicht gibt. Ohne diesen Schalter
> scheitert der Start mit `No such file or directory`, obwohl die Datei
> sichtbar vorhanden ist. Das ist der teuerste Stolperstein beim ersten
> Deployment; die Fehlermeldung zeigt in die falsche Richtung.
>
> Fehlt danach noch eine Bibliothek, mit `ldd /opt/hmi/BauerGroup.Hmi` suchen
> und über `application.extraLibraries` ergänzen.

**Nachteil:** Die App liegt außerhalb der Nix-Generation. Ein
`nixos-rebuild --rollback` setzt das System zurück, **nicht** die HMI-Version.

### Weg B — Nix-Paket (beste Reproduzierbarkeit)

```nix
application.command = "${pkgs.callPackage ./pkgs/bg-hmi { }}/bin/bg-hmi";
```

Mit `buildDotnetModule` gebaut. `foreignBinaries` entfällt, weil das Paket
seine Bibliotheken mitbringt. App-Version und System-Generation sind
gekoppelt — ein Rollback nimmt die HMI mit zurück. Dafür wandert der
App-Quellcode in den Nix-Build.

### Weg C — Container

Möglich, aber aufwendiger als es aussieht: die Session läuft als
unprivilegiertes Konto, und dieses Konto darf **nicht** in die
Container-Socket-Gruppe (der Build lehnt das ab — ein Container-Socket kann
jeden Host-Pfad privilegiert einhängen und macht das Konto de facto zu root).

Der Container muss daher **rootless** laufen (eigene `subuid`/`subgid` für das
Session-Konto), und Wayland-Socket sowie `/dev/dri` müssen hineingereicht
werden. Sinnvoll, wenn die HMI ohnehin als Image ausgeliefert wird; für einen
einzelnen Binary-Deploy ist Weg A schlanker.

---

## Watchdog

Zwei Ebenen, weil es zwei verschiedene Fehlerbilder gibt:

```
Kernel-Lockup, Storage-Stall, OOM
   └─► systemd pingt /dev/watchdog nicht mehr
       └─► Hardware setzt das Board zurück          ← einzige Ebene,
                                                      die einen toten
                                                      Kernel überlebt

UI eingefroren, System gesund
   └─► Prozess lebt, systemd gesund, Hardware-Watchdog schweigt
       └─► Health-Probe schlägt 3× fehl
           └─► systemctl restart cage-tty1
               └─► 3 Restarts in 10 min ohne Besserung
                   └─► systemctl reboot
```

Die zweite Ebene ist der Grund, warum `Restart=always` allein nicht reicht:
ein eingefrorenes Chromium **stürzt nicht ab**. Es zeigt ein Standbild, der
Prozess lebt, und ohne explizite Probe merkt das niemand.

### Konfiguration

```nix
bauergroup.params = {
  watchdog = {
    enable = true;
    kernelModules = [ "iTCO_wdt" ];   # siehe Warnung unten
  };
  kiosk.watchdog = true;
};
```

Im Modus `"browser"` wird die Probe automatisch eingerichtet (Chromiums
DevTools-Endpunkt auf Loopback). Im Modus `"application"` gibt es nichts
generisch Prüfbares — ohne `kiosk.healthCheckCommand` bleibt die
Freeze-Erkennung wirkungslos, und der Build warnt entsprechend.

> **Der DevTools-Endpunkt ist nicht authentifiziert.**
> Er liegt auf Loopback, aber wer ihn erreicht, kann mehr als Gesundheit
> abfragen: JavaScript in der Seite ausführen, navigieren, den Bildschirminhalt
> lesen. „Loopback" heißt also **jeder lokale Prozess**, nicht nur dieser
> Watchdog — eine niedrigere Hürde als das separate Session-Konto, das sonst
> überall durchgezogen wird.
>
> Auf einer Single-Purpose-Appliance ist das meist ein akzeptabler Tausch gegen
> Freeze-Erkennung. Wo nicht: eigenes `kiosk.healthCheckCommand` setzen — dann
> wird der Port gar nicht erst geöffnet und stattdessen geprüft, was die
> Oberfläche selbst anbietet.

### Anlaufzeit

Der Watchdog zählt Fehlschläge erst, wenn die Session länger als
`startupGrace` (Default 120 s) aktiv ist — gemessen ab **Unit-Start**, nicht ab
Boot, damit ein Neustart dieselbe Karenz bekommt.

Das ist kein Komfort, sondern verhindert einen Bootloop: die Session wartet bis
zu 60 s auf ihr Backend, bevor sie überhaupt etwas startet. Ohne Karenz würden
die ersten Proben berechtigt fehlschlagen, der Watchdog würde neu starten, die
Wartezeit liefe von vorn — und nach drei Runden rebootet die Maschine, nach dem
Boot wieder. Bei einem langsamen Backend (großes Compose-Projekt auf eMMC)
`startupGrace` erhöhen.

> **Industrieboards brauchen den Treiber meist explizit.**
> Ohne passendes Kernel-Modul existiert `/dev/watchdog` schlicht nicht, und
> die Anlage hat keine automatische Wiederherstellung. Nach dem
> Inbetriebnehmen prüfen:
>
> ```bash
> wdctl          # meldet Gerät, Treiber und echten Timeout
> ```
>
> Kandidaten: `iTCO_wdt` (Intel PCH), `sp5100_tco` (AMD), `it87_wdt` und
> `w83627hf_wdt` (Super-I/O). Für VMs und Boards ganz ohne Watchdog gibt es
> `watchdog.useSoftdog` — der rettet eine hängende Userspace, **nicht** einen
> hängenden Kernel.

---

## Container-Engine

`docker` ist Standard, `podman` ein Ein-Zeilen-Wechsel:

```nix
bauergroup.params.containers.engine = "podman";
```

Beide stellen die Docker-API unter `/run/docker.sock` bereit, deshalb laufen
alle Compose-Projekte dieses Repos unverändert auf beiden. Verifiziert durch
`checks.x86_64-linux.container-engine`, das auf beiden Engines einen Container
startet und ein Compose-Projekt hochfährt.

> **Ein Wechsel legt Container neu an und migriert keine Named Volumes.**
> Auf einer laufenden Maschine vorher Datenvolumes sichern.

---

## Boot-Splash

Kiosk- und HMI-Maschinen booten mit dem BAUER-GROUP-Splash statt mit
Kernel-Meldungen — ein Bildschirm, auf den ein Kunde oder Bediener schaut,
soll beim Start nicht wie ein defekter Rechner aussehen.

Das Theme wird aus `assets/branding/bauer-group-logo-wide-white.svg` gebaut;
Farben kommen aus den Corporate-Identity-Tokens:

| Element            | Token        | Wert      |
| ------------------ | ------------ | --------- |
| Hintergrund        | `warm-900`   | `#231F1C` |
| Fortschrittsbalken | `orange-500` | `#FF8500` |
| Balken-Spur        | `warm-800`   | `#3A3430` |
| Statustext         | `warm-50`    | `#F9F8F6` |

> Die SVG-Master stammen aus einer EPS-Konvertierung und tragen
> Prozent-`rgb()`-Füllungen, die auf `#F57E13` runden statt auf das
> verbindliche `#FF8500`. Der Build korrigiert das beim Rastern
> (`--replace-fail`, schlägt also auf, falls die Quelle später repariert wird).

Beim Inbetriebnehmen von Hardware stört der Splash eher:

```nix
bauergroup.params.branding.silentBoot = false;   # Kernel-Meldungen sichtbar
# oder ganz aus:
bauergroup.params.branding.enable = false;
```

---

## Sicherheit

Die Session läuft unter einem eigenen, unprivilegierten Konto (`kiosk.user`),
getrennt vom Admin-Konto. Eine kompromittierte Seite oder HMI erreicht damit
weder SSH-Keys noch sudo noch den Container-Socket.

Der Build lehnt ab:

- `kiosk.user == user.name` — die Session als Admin zu fahren
- `wheel`, `docker` oder `podman` in `kiosk.extraGroups` — alles drei macht das
  Konto faktisch zu root und hebt die Trennung auf

`allowVtSwitch` ist aus: `Ctrl+Alt+F2` wäre sonst ein unauthentifizierter Weg
zu einem Login-Prompt an einem Gerät im öffentlichen Bereich. Beim
Inbetriebnehmen vorübergehend einschalten.

---

## Troubleshooting

| Symptom                                             | Ursache / Prüfung                                                                       |
| --------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Schwarzer Bildschirm, Session startet nicht         | `journalctl -u cage-tty1 -b` — meist scheitert das Payload-Kommando                     |
| `No such file or directory` trotz vorhandener Datei | `foreignBinaries = true` fehlt (siehe Weg A)                                            |
| HMI startet, aber ohne Schrift                      | Fehlende Fonts — `fonts.enableDefaultPackages` ist an, App-eigene Fonts ergänzen        |
| Maschine rebootet unerwartet                        | `journalctl -u bauergroup-app-watchdog -b` zeigt Probe-Fehler und Eskalation            |
| Watchdog greift nie                                 | `wdctl` — ohne Gerät fehlt das Kernel-Modul (`watchdog.kernelModules`)                  |
| Bild steht, Touch reagiert daneben                  | Rotation: Touch wird über eine libinput-Matrix mitgedreht, nur bei `touchscreen = true` |
| Compose-Projekt startet nicht unter Podman          | `systemctl status podman.socket`, dann `docker info`                                    |

Session gezielt neu starten, ohne zu rebooten:

```bash
systemctl restart cage-tty1
```
