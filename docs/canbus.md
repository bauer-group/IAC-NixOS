# CAN-Bus Development mit NixOS

## Überblick

Das `embedded-dev.nix` Modul konfiguriert:
- **Latest stable Kernel** für neueste CAN-Bus Treiber
- **SocketCAN** Kernel-Module (can, can_raw, can_bcm, can_gw, can_isotp)
- **USB-Adapter-Treiber** (PEAK, candleLight/canable, Kvaser, etc.)
- **Virtual CAN** (vcan0, vcan1) für Tests ohne Hardware
- **Userspace Tools** (can-utils, python-can, cantools)
- **udev Rules** für automatische Adapter-Erkennung

## SocketCAN Basics

SocketCAN macht CAN-Bus-Interfaces zu normalen Netzwerk-Interfaces:

```bash
# CAN-Interface anzeigen
ip link show type can

# Virtuelle CAN-Interfaces (automatisch erstellt via systemd)
ip link show vcan0
ip link show vcan1

# Physisches CAN-Interface konfigurieren (z.B. PEAK USB)
sudo ip link set can0 type can bitrate 500000
sudo ip link set can0 up

# Mit FD (Flexible Data-Rate):
sudo ip link set can0 type can bitrate 500000 dbitrate 2000000 fd on
sudo ip link set can0 up

# Interface-Status
ip -details link show can0
```

## USB-Adapter

### Unterstützte Adapter

| Adapter | Kernel-Modul | Anmerkung |
|---------|-------------|-----------|
| PEAK PCAN-USB | `peak_usb` | Industriestandard, sehr zuverlässig |
| candleLight / canable | `gs_usb` | Open-Source Hardware, günstig |
| Kvaser Leaf Light | `kvaser_usb` | Professionell, gut für Automotive |
| USBtin / LAWICEL | `slcan` | Serial Line CAN, einfach |
| Microchip CAN BUS Analyzer | `mcba_usb` | Budget-Option |

### Adapter anschließen

```bash
# USB-Adapter einstecken, dann prüfen:
dmesg | tail -20
# Sollte zeigen: "peak_usb: PCAN-USB ... connected" o.ä.

# CAN-Interface sollte erscheinen:
ip link show type can
# → can0

# Konfigurieren und hochfahren
sudo ip link set can0 type can bitrate 500000
sudo ip link set can0 up
```

## can-utils — Wichtigste Befehle

### Empfangen

```bash
# Alle Frames auf can0 anzeigen
candump can0

# Mit Timestamps und ASCII-Dekodierung
candump -ta -c can0

# Nur bestimmte CAN-IDs filtern
candump can0,123:7FF        # Nur ID 0x123
candump can0,100:700         # IDs 0x100-0x1FF

# In Logdatei schreiben
candump -L can0 > trace.log
```

### Senden

```bash
# Einzelnen Frame senden (ID#Daten)
cansend can0 123#DEADBEEF

# CAN-FD Frame
cansend can0 123##1.DEADBEEFCAFEBABE0011223344556677

# Frame aus Logdatei abspielen
canplayer -I trace.log
```

### Generieren & Testen

```bash
# Zufällige Frames generieren (Last-Test)
cangen can0 -g 10 -I r -L 8 -D r

# Bus-Statistiken
canbusload can0@500000

# Sniffer (gruppiert nach ID, zeigt Änderungen)
cansniffer can0
```

### ISO-TP (für UDS / Automotive Diagnostik)

```bash
# ISO-TP Nachricht senden (TX: 0x7E0, RX: 0x7E8)
echo "10 01" | isotpsend -s 7E0 -d 7E8 can0

# ISO-TP empfangen
isotprecv -s 7E8 -d 7E0 can0

# UDS DiagnosticSessionControl (Extended Session)
echo "10 03" | isotpsend -s 7E0 -d 7E8 can0
```

## Python-CAN

```python
#!/usr/bin/env python3
import can

# Bus öffnen
bus = can.interface.Bus(channel='vcan0', interface='socketcan')

# Frame senden
msg = can.Message(
    arbitration_id=0x123,
    data=[0xDE, 0xAD, 0xBE, 0xEF],
    is_extended_id=False
)
bus.send(msg)

# Frames empfangen
for msg in bus:
    print(f"ID: {msg.arbitration_id:#05x}  Data: {msg.data.hex()}")
```

### DBC-Dateien parsen (cantools)

```python
import cantools

# DBC laden
db = cantools.database.load_file('vehicle.dbc')

# Signal dekodieren
msg = db.get_message_by_name('EngineData')
decoded = msg.decode(b'\x00\x00\x04\xD2\x00\x00\x00\x00')
print(decoded)  # {'RPM': 1234, 'Temperature': 0, ...}

# Signal enkodieren
data = msg.encode({'RPM': 3000, 'Temperature': 85})
print(data.hex())
```

## Virtuelle CAN-Interfaces (Testing)

Das Modul erstellt automatisch `vcan0` und `vcan1` via systemd:

```bash
# Terminal 1: Empfangen
candump vcan0

# Terminal 2: Senden
cansend vcan0 123#CAFEBABE

# vxcan: Tunnel zwischen zwei vcan Interfaces
sudo ip link add dev vxcan0 type vxcan peer name vxcan1
sudo ip link set up vxcan0
sudo ip link set up vxcan1
# Was auf vxcan0 gesendet wird, erscheint auf vxcan1 und umgekehrt
```

## Kernel-Version prüfen

```bash
# Aktuelle Kernel-Version
uname -r
# Sollte z.B. 6.12.x oder neuer sein

# CAN-Module geladen?
lsmod | grep can
# Sollte zeigen: can, can_raw, can_bcm, vcan, etc.

# CAN-Subsystem im Kernel?
cat /proc/net/can/version

# Verfügbare CAN-bezogene Module
find /lib/modules/$(uname -r) -name '*can*'
```

## Troubleshooting

### "RTNETLINK answers: Operation not supported"
→ CAN-Kernel-Module nicht geladen. Prüfe `lsmod | grep can`.
→ Evtl. `sudo modprobe can` / `sudo modprobe can_raw`.

### USB-Adapter wird nicht erkannt
→ `dmesg | grep -i can` prüfen
→ `lsusb` prüfen ob Adapter aufgelistet wird
→ udev Rules checken: `udevadm info /dev/bus/usb/...`

### "Cannot find device can0"
→ Adapter angeschlossen? `ip link show type can`
→ Richtiger Treiber? `dmesg | tail -30`

### Bus-Off / Error-Passive
→ Falsche Bitrate? Muss auf allen Teilnehmern gleich sein
→ Terminierung? CAN-Bus braucht 120Ω Terminierung an beiden Enden
→ `ip -details -statistics link show can0` für Error-Counter

### CAN-FD Frames werden nicht empfangen
→ `ip link set can0 type can bitrate 500000 dbitrate 2000000 fd on`
→ Adapter muss CAN-FD unterstützen (PEAK PCAN-USB FD, canable Pro)
