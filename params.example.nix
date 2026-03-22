# params.example.nix
# ─────────────────────────────────────────────────────────────────────
# Place this file as /etc/nixos/params.nix on the target machine.
# It parameterizes the NixOS template for this specific machine.
#
# Then deploy with:
#   nixos-rebuild switch --flake github:your-org/nixos#<template> --impure
#
# Available templates:
#   desktop-dev    — Development desktop (KDE Plasma 6, dev tools)
#   desktop-kiosk  — Kiosk display (fullscreen browser + Docker backend)
#   server         — Headless server (Docker services, hardened)
# ─────────────────────────────────────────────────────────────────────
{ ... }:
{
  bauer.params = {

    # ══════════════════════════════════════════════════════════════════
    # REQUIRED — set these for every machine
    # ══════════════════════════════════════════════════════════════════
    hostName = "REPLACE-ME"; # e.g. "dev-workstation-01", "kiosk-lobby", "srv-prod-01"

    user = {
      name = "admin"; # Username for the primary account
      fullName = "Max Mustermann"; # For git config
      email = "max@bauer-group.com"; # For git config
      sshKeys = [
        # "ssh-ed25519 AAAAC3Nza... user@machine"
      ];

      # Generate with: mkpasswd -m sha-512 "your-password"
      # If null, only SSH key login works (no console login)
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
    # TEMPLATE-SPECIFIC: desktop-dev
    # ══════════════════════════════════════════════════════════════════
    dev = {
      embeddedDev = false; # Set to true for CAN-Bus / SocketCAN tooling
      # extraPackages = with pkgs; [ ];  # Additional packages
    };

    # ══════════════════════════════════════════════════════════════════
    # TEMPLATE-SPECIFIC: desktop-kiosk
    # ══════════════════════════════════════════════════════════════════
    kiosk = {
      url = "http://localhost:3000"; # URL to display in kiosk browser
      # composeFile = /opt/kiosk/docker-compose.yml;
      # composeDirectory = "/opt/kiosk";
      # touchscreen = false;
      # rotation = "normal";        # "normal", "left", "right", "inverted"
      # idleTimeout = null;         # Seconds before browser resets (null = disabled)
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
        #   envFile = null;  # or /run/agenix/outline-env
        # };
        # traefik = {
        #   directory = "/opt/traefik";
        # };
      };

      backup = {
        enable = false;
        # repository = "sftp:backup@storage:/backups/hostname";
        # passwordFile = "/run/agenix/restic-password";
        # paths = [ "/opt" "/var/lib" "/home" ];
      };
    };
  };
}
