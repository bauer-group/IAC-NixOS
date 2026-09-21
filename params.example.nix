# params.example.nix
# ─────────────────────────────────────────────────────────────────────
# Place this file as /etc/nixos/params.nix on the target machine.
# It parameterizes the NixOS template for this specific machine.
#
# Then deploy with:
#   nixos-rebuild switch --flake github:your-org/nixos#<template> --impure
#
# Available templates:
#   desktop-dev     — Development desktop (KDE Plasma 6, dev tools)
#   desktop-kiosk   — Kiosk display on standard hardware (lobby, dashboard)
#   embedded-kiosk  — HMI on the machine (panel PC, no self-reboot, flash-aware)
#   server          — Headless server (container services, hardened)
# ─────────────────────────────────────────────────────────────────────
{ pkgs, ... }:
{
  bauergroup.params = {

    # ══════════════════════════════════════════════════════════════════
    # REQUIRED — set these for every machine
    # ══════════════════════════════════════════════════════════════════
    hostName = "REPLACE-ME"; # e.g. "dev-workstation-01", "kiosk-lobby", "srv-prod-01"

    user = {
      name = "admin"; # Username for the primary account
      fullName = "Max Mustermann"; # For git config
      email = "max@bauer-group.com"; # For git config

      # REQUIRED: at least one SSH key or a hashedPassword.
      # With both empty the build fails, because the account could never log in.
      sshKeys = [
        # "ssh-ed25519 AAAAC3Nza... user@machine"
      ];

      # Generate with: mkpasswd -m sha-512 "your-password"
      # If null, only SSH key login works (no console login).
      # desktop-kiosk: needed for sudo, which requires a password there.
      hashedPassword = null;

      # Extra groups beyond the defaults (wheel, docker, etc.)
      # extraGroups = [ "video" "audio" ];
    };

    # ══════════════════════════════════════════════════════════════════
    # NETWORK — DHCP by default, set for static IP
    # ══════════════════════════════════════════════════════════════════
    network = {
      useDHCP = true; # Set to false for static IP
      # interface = "eth0";
      # address = "10.0.0.5";
      # prefixLength = 24;
      # gateway = "10.0.0.1";
      # nameservers = [ "1.1.1.1" "8.8.8.8" ];
      # openPorts = [ 80 443 ];
    };

    # ══════════════════════════════════════════════════════════════════
    # BOOT — defaults to systemd-boot (EFI)
    # ══════════════════════════════════════════════════════════════════
    boot = {
      loader = "systemd-boot"; # or "grub" for BIOS/legacy
      # grubDevice = "/dev/sda";  # only for grub
    };

    # ══════════════════════════════════════════════════════════════════
    # LOCALE — defaults to German/Berlin
    # ══════════════════════════════════════════════════════════════════
    # timezone = "Europe/Berlin";
    # locale = "en_US.UTF-8";
    # keymap = "de-latin1";
    # xkbLayout = "de";

    # ══════════════════════════════════════════════════════════════════
    # AUTO-UPDATE — enabled by default for all machines
    # ══════════════════════════════════════════════════════════════════
    autoUpdate = {
      enable = true; # Pull latest config + packages daily
      # flake = "github:bauer-group/IAC-NixOS";         # Source repo (#<template> is appended)
      # schedule = "03:00";                              # When to check
      # allowReboot = true;                              # Reboot if kernel changed
      # rebootWindowStart = "03:00";                     # Earliest reboot time
      # rebootWindowEnd = "03:30";                       # Latest reboot time
    };

    # ══════════════════════════════════════════════════════════════════
    # TEMPLATE-SPECIFIC: desktop-dev
    # ══════════════════════════════════════════════════════════════════
    dev = {
      embeddedDev = false; # Set to true for CAN-Bus / SocketCAN tooling
      # extraPackages = with pkgs; [ ];  # Additional packages
    };

    # ══════════════════════════════════════════════════════════════════
    # CONTAINER ENGINE — all templates
    # ══════════════════════════════════════════════════════════════════
    containers = {
      # enable = true;              # false on machines that run no containers
      engine = "docker"; # or "podman" — both serve /run/docker.sock,
      #   so Compose projects work either way.
      #   Switching re-creates containers and does
      #   NOT migrate named volumes.
    };

    # ══════════════════════════════════════════════════════════════════
    # WATCHDOG — all templates
    # ══════════════════════════════════════════════════════════════════
    # Resets the machine when systemd stops responding. Harmless where no
    # watchdog hardware exists — systemd notes the missing device and carries on.
    watchdog = {
      enable = true;
      # runtimeTime = "60s";        # Do not go below ~30s on I/O-heavy machines
      # rebootTime = "3min";        # Bounds how long a hung unit blocks a reboot

      # Many industrial boards expose no watchdog until the driver is named.
      # Check with `wdctl` on the machine — no device means no recovery.
      #   iTCO_wdt      Intel PCH          sp5100_tco    AMD
      #   it87_wdt      Super-I/O          w83627hf_wdt  Super-I/O
      # kernelModules = [ "iTCO_wdt" ];

      # Kernel-implemented watchdog for VMs and boards with no hardware.
      # Recovers a hung userspace, NOT a hung kernel. Leave off where real
      # watchdog hardware exists.
      # useSoftdog = false;
    };

    # ══════════════════════════════════════════════════════════════════
    # BRANDING — boot splash (kiosk templates by default)
    # ══════════════════════════════════════════════════════════════════
    # branding = {
    #   enable = null;              # null = follow template default
    #   silentBoot = true;          # false while commissioning hardware
    # };

    # ══════════════════════════════════════════════════════════════════
    # TEMPLATE-SPECIFIC: desktop-kiosk / embedded-kiosk
    # ══════════════════════════════════════════════════════════════════
    kiosk = {
      mode = "browser"; # "browser" = Chromium on Wayland
      #   "application" = native HMI via XWayland

      # ── mode = "browser" ──────────────────────────────────────────
      url = "http://localhost:3000";
      # extraFlags = [ "--force-device-scale-factor=1.5" ];

      # ── mode = "application" ──────────────────────────────────────
      # application = {
      #   command = "/opt/hmi/BauerGroup.Hmi";   # absolute path, or a
      #                                          # "podman run ..." line
      #   environment = { DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1"; };
      #
      #   # REQUIRED for a `dotnet publish` output or any supplier binary.
      #   # Without it the app fails with "No such file or directory" even
      #   # though the file is there — NixOS has no /lib64/ld-linux-x86-64.so.2.
      #   # Not needed for a Nix-packaged app or one running in a container.
      #   foreignBinaries = true;
      #   # extraLibraries = with pkgs; [ alsa-lib ];   # find with `ldd`
      # };

      # ── Session ───────────────────────────────────────────────────
      # user = "kiosk";             # Unprivileged session account, must differ from user.name
      # extraGroups = [ "dialout" ];# Serial adapter to a PLC; never wheel/docker/podman
      # touchscreen = false;
      # rotation = "normal";        # "normal", "left" (counter-clockwise), "right" (clockwise), "inverted"
      # multiMonitor = "last";      # or "extend" across all outputs
      # allowVtSwitch = false;      # true only while commissioning — it is an
      #                             # unauthenticated path to a login prompt
      # idleTimeout = null;         # Seconds without input before the UI resets (null = disabled)

      # ── Startup ───────────────────────────────────────────────────
      # Wait for the backend instead of briefly showing a connection error.
      # "browser" defaults to fetching kiosk.url; "application" needs this set.
      # startupProbe = "/run/current-system/sw/bin/curl -sf --max-time 5 http://localhost:8080/ready";

      # ── Freeze detection ──────────────────────────────────────────
      # A frozen UI keeps its process alive and systemd healthy, so nothing
      # else notices it. In "browser" mode the probe is configured for you.
      # In "application" mode set healthCheckCommand or this has no effect.
      # watchdog = true;
      # healthCheckCommand = "/run/current-system/sw/bin/curl -sf --max-time 5 http://127.0.0.1:8080/healthz";
      #
      # Probes are ignored for this long after every session start, so a
      # session that is merely still coming up is not restarted. Raise it when
      # the backend is slow (large Compose project on eMMC).
      # startupGrace = 120;

      # ── Backend ───────────────────────────────────────────────────
      # composeFile = /opt/kiosk/docker-compose.yml;
      # composeDirectory = "/opt/kiosk";
    };

    # ══════════════════════════════════════════════════════════════════
    # TEMPLATE-SPECIFIC: server
    # ══════════════════════════════════════════════════════════════════
    server = {
      monitoring = true; # Enable Prometheus node exporter

      # Docker Compose projects — each becomes a systemd service
      composeProjects = {
        # outline = {
        #   directory = "/opt/outline";
        #   envFile = null;  # or "/run/agenix/outline-env"
        # };
        # traefik = {
        #   directory = "/opt/traefik";
        # };
      };

      backup = {
        enable = false;
        # repository = "sftp:backup@storage:/backups/hostname";
        # passwordFile = "/run/agenix/restic-password";
        # paths = [ "/opt" "/var/lib" "/home" "/etc/nixos" ];
      };
    };
  };
}
