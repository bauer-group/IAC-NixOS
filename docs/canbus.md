# CAN-Bus Development mit NixOS

## Überblick

Das `embedded-dev`-Feature-Modul (`modules/features/embedded-dev.nix`) konfiguriert:

- **SocketCAN** Kernel-Module (CAN als Linux-Netzwerk-Interface)
- **USB-Adapter** Treiber (PEAK, candleLight, Kvaser, etc.)
- **Userspace-Tools** (can-utils, Python-CAN, cantools, UDS)
- **Embedded-Toolchains** (GCC ARM, OpenOCD, ST-Link, ESP-IDF)
- **Virtuelle CAN-Interfaces** (vcan0, vcan1 für Tests)

## Aktivierung

In der `/etc/nixos/params.nix` auf der Zielmaschine:

```nix
{ ... }: {
  bauer.params = {
    # ...
    dev.embeddedDev = true;
  };
}
```

Dann deployen mit dem Desktop-Dev Template:

```bash
sudo nixos-rebuild switch --flake .#desktop-dev --impure
```

## USB-Adapter Support

| Adapter | Kernel-Modul | USB ID |
| --- | --- | --- |
| PEAK-System PCAN-USB | `peak_usb` | `0c72:*` |
| candleLight / canable | `gs_usb` | `1d50:606f` |
| Kvaser USB | `kvaser_usb` | `0bfd:*` |
| USBtin / LAWICEL | `slcan` | (seriell) |
| EMS CPC-USB | `ems_usb` | |
| USB2CAN (8 Devices) | `usb_8dev` | |
| Microchip CAN Analyzer | `mcba_usb` | |

Alle Adapter werden automatisch erkannt. udev-Regeln setzen `MODE=0666` für die `plugdev`-Gruppe.

## can-utils Befehle

```bash
# ── Empfangen ─────────────────────────────────
candump can0                          # Alle Frames auf can0
candump can0,123:7FF                  # Nur ID 0x123
candump -ta can0                      # Mit absolutem Timestamp

# ── Senden ────────────────────────────────────
cansend can0 123#DEADBEEF             # Einzelner Frame
cangen can0 -I 123 -L 8 -g 100       # Generator (100ms Intervall)

# ── Analyse ───────────────────────────────────
cansniffer can0                       # Live-Anzeige mit Delta
canbusload can0                       # Busauslastung messen

# ── ISO-TP (Automotive) ──────────────────────
isotpsend -s 7E0 -d 7E8 can0         # ISO-TP Nachricht senden
isotprecv -s 7E8 -d 7E0 can0         # ISO-TP Antwort empfangen

# ── Interface konfigurieren ──────────────────
sudo ip link set can0 type can bitrate 500000
sudo ip link set up can0
```

## Python-CAN

```python
import can

# CAN-Bus öffnen
bus = can.Bus(interface='socketcan', channel='can0', bitrate=500000)

# Frame senden
msg = can.Message(arbitration_id=0x123, data=[0xDE, 0xAD, 0xBE, 0xEF])
bus.send(msg)

# Frame empfangen
msg = bus.recv(timeout=1.0)
print(f"ID: {msg.arbitration_id:#x}, Data: {msg.data.hex()}")
```

### DBC-Datei parsen (cantools)

```python
import cantools

db = cantools.database.load_file('vehicle.dbc')
msg = db.get_message_by_name('EngineSpeed')
data = msg.encode({'RPM': 3500, 'Temperature': 85})
print(f"Encoded: {data.hex()}")
```

### UDS Diagnostics

```python
import udsoncan
from udsoncan.connections import PythonIsoTpConnection
from udsoncan.client import Client

conn = PythonIsoTpConnection('can0', rxid=0x7E8, txid=0x7E0)
with Client(conn) as client:
    response = client.read_data_by_identifier(0xF190)  # VIN lesen
    print(response.service_data)
```

## Virtuelle CAN-Interfaces (Testing)

Die Interfaces `vcan0` und `vcan1` werden automatisch beim Boot erstellt:

```bash
# Prüfen
ip link show type vcan

# Loopback-Test
candump vcan0 &
cansend vcan0 123#AABBCCDD
# → Empfängt den eigenen Frame

# Zwei Terminals verbinden
# Terminal 1: candump vcan0
# Terminal 2: cansend vcan0 456#11223344
```

## Troubleshooting

### "RTNETLINK: Operation not supported"

```bash
# CAN-Kernel-Module laden
sudo modprobe can
sudo modprobe can_raw
sudo modprobe vcan

# Prüfen ob geladen
lsmod | grep can
```

### USB-Adapter wird nicht erkannt

```bash
# USB-Geräte auflisten
lsusb

# Kernel-Logs prüfen
dmesg | grep -i can

# Treiber manuell laden
sudo modprobe peak_usb   # PEAK
sudo modprobe gs_usb     # candleLight
```

### Bus-Off Recovery

```bash
# Interface zurücksetzen
sudo ip link set can0 down
sudo ip link set can0 type can restart-ms 100
sudo ip link set can0 up

# Statistiken prüfen
ip -details -statistics link show can0
```

### CAN-FD (Flexible Data-Rate)

```bash
# Interface mit CAN-FD konfigurieren
sudo ip link set can0 type can bitrate 500000 dbitrate 2000000 fd on
sudo ip link set can0 up

# FD-Frames senden (bis 64 Byte)
cansend can0 123##1.DEADBEEFCAFEBABE
```
