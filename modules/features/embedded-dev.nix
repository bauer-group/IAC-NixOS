# modules/features/embedded-dev.nix
# ─────────────────────────────────────────────────────────────────────
# Embedded systems / CAN-Bus development feature module.
# Switches to latest kernel for newest CAN-Bus drivers.
# Includes SocketCAN tooling, serial debug, cross-compilation support.
#
# Enable via: bauer.params.dev.embeddedDev = true (in params.nix)
# ─────────────────────────────────────────────────────────────────────
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.bauer.params.dev.embeddedDev;
in
{
  config = lib.mkIf cfg {
    # ══════════════════════════════════════════════════════════════════
    # KERNEL — Latest stable for newest CAN-Bus driver support
    # ══════════════════════════════════════════════════════════════════
    boot.kernelPackages = lib.mkForce pkgs.linuxPackages_latest;

    # ── CAN-Bus Kernel Modules ──────────────────────────────────────
    boot.kernelModules = [
      # Core SocketCAN
      "can"
      "can_raw"
      "can_bcm"
      "can_gw"
      "can_isotp" # ISO 15765-2 (ISO-TP) — automotive diagnostics / UDS

      # Virtual CAN for testing without hardware
      "vcan"
      "vxcan" # Virtual CAN tunnel (pairs of vcan)

      # USB CAN adapters
      "peak_usb" # PEAK-System PCAN-USB
      "gs_usb" # Geschwister Schneider / candleLight / canable
      "kvaser_usb" # Kvaser USB adapters
      "ems_usb" # EMS CPC-USB
      "usb_8dev" # USB2CAN by 8 Devices
      "mcba_usb" # Microchip CAN BUS Analyzer

      # Serial line CAN
      "slcan" # Serial Line CAN (e.g. USBtin, LAWICEL)

      # MCP251x SPI (for Raspberry Pi / embedded boards)
      "mcp251x"
      "mcp251xfd" # MCP2517FD / MCP2518FD
    ];

    # ── Extra kernel config (ensure CAN subsystem is built) ─────────
    boot.kernelPatches = [
      {
        name = "canbus-full-support";
        patch = null;
        extraStructuredConfig = with lib.kernel; {
          # Core CAN
          CAN = yes;
          CAN_RAW = yes;
          CAN_BCM = yes;
          CAN_GW = yes;
          CAN_ISOTP = yes;

          # Virtual
          CAN_VCAN = module;
          CAN_VXCAN = module;

          # USB adapters
          CAN_PEAK_USB = module;
          CAN_GS_USB = module;
          CAN_KVASER_USB = module;
          CAN_SLCAN = module;
          CAN_EMS_USB = module;
          CAN_8DEV_USB = module;
          CAN_MCBA_USB = module;

          # SPI
          CAN_MCP251X = module;
          CAN_MCP251XFD = module;

          # J1939 (SAE J1939 — heavy vehicles, agriculture)
          CAN_J1939 = module;
        };
      }
    ];

    # ── Kernel module auto-load parameters ──────────────────────────
    boot.extraModprobeConfig = ''
      # Peak USB: enable bus error reporting
      options peak_usb bus_error=1
    '';

    # ══════════════════════════════════════════════════════════════════
    # UDEV RULES — CAN adapter permissions
    # ══════════════════════════════════════════════════════════════════
    services.udev.extraRules = ''
      # PEAK-System USB adapters
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0c72", MODE="0666", GROUP="plugdev"

      # Geschwister Schneider / candleLight / canable
      SUBSYSTEM=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="606f", MODE="0666", GROUP="plugdev"

      # Kvaser USB
      SUBSYSTEM=="usb", ATTRS{idVendor}=="0bfd", MODE="0666", GROUP="plugdev"

      # Generic: allow plugdev group access to all CAN network interfaces
      SUBSYSTEM=="net", KERNEL=="can*", GROUP="plugdev", MODE="0660"
      SUBSYSTEM=="net", KERNEL=="vcan*", GROUP="plugdev", MODE="0660"
    '';

    # ══════════════════════════════════════════════════════════════════
    # USERSPACE TOOLS
    # ══════════════════════════════════════════════════════════════════
    environment.systemPackages = with pkgs; [
      # ── CAN-Bus ────────────────────────────────────────────────────
      can-utils

      # ── Python CAN ─────────────────────────────────────────────────
      (python3.withPackages (
        ps: with ps; [
          python-can
          cantools
          udsoncan
        ]
      ))

      # ── Serial / Debug ─────────────────────────────────────────────
      minicom
      picocom
      screen
      usbutils
      pciutils

      # ── Embedded Toolchains ────────────────────────────────────────
      gcc-arm-embedded
      openocd
      stlink
      esptool
      platformio-core

      # ── Logic Analyzer / Protocol ──────────────────────────────────
      sigrok-cli
      pulseview

      # ── Build Tools ────────────────────────────────────────────────
      cmake
      ninja
      gnumake
      pkg-config
    ];

    # ══════════════════════════════════════════════════════════════════
    # SYSTEMD — Auto-setup virtual CAN for testing
    # ══════════════════════════════════════════════════════════════════
    systemd.services.vcan-setup = {
      description = "Setup virtual CAN interfaces for development";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;

        # Hardening — only needs CAP_NET_ADMIN to create interfaces
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        CapabilityBoundingSet = [ "CAP_NET_ADMIN" ];
        AmbientCapabilities = [ "CAP_NET_ADMIN" ];
        RestrictNamespaces = true;
        RestrictSUIDSGID = true;
        ProtectKernelModules = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
      };
      script = ''
        ${pkgs.iproute2}/bin/ip link add dev vcan0 type vcan 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set up vcan0 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link add dev vcan1 type vcan 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set up vcan1 2>/dev/null || true
      '';
    };
  };
}
