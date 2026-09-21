# templates/desktop-kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# Kiosk display on standard hardware — lobby screens, meeting-room panels,
# shop-floor dashboards. A machine someone can walk up to, on ordinary PC
# hardware, with a network and a maintenance window.
#
# Features:
#   - No desktop environment; the session runs as an unprivileged account
#   - cage (Wayland kiosk compositor) with Chromium or a native HMI
#   - Session restarts on crash; watchdog catches a freeze that does not crash
#   - BAUER GROUP boot splash instead of kernel messages
#   - Compose backend services on Docker or Podman
#   - Optional touchscreen, rotation and idle reset
#
# For a panel bolted to a machine, use embedded-kiosk instead: same session,
# different assumptions about flash wear, reboots and uptime.
#
# Deploy: nixos-rebuild switch --flake .#desktop-kiosk --impure
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  params = config.bauergroup.params;
in
{
  imports = [
    ../modules/baseline/ntp.nix
    ../modules/baseline/ssh.nix
    ../modules/baseline/users.nix
    ../modules/baseline/networking.nix
    ../modules/baseline/nix.nix
    ../modules/baseline/auto-update.nix
    ../modules/baseline/platform.nix
    ../modules/features/kiosk.nix
    ../modules/services/monitoring.nix
  ];

  # ── Boot ────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = lib.mkIf (params.boot.loader == "systemd-boot") {
    enable = true;
    configurationLimit = 5;
  };
  boot.loader.grub = lib.mkIf (params.boot.loader == "grub") {
    enable = true;
    device = params.boot.grubDevice;
  };
  boot.loader.efi.canTouchEfiVariables = params.boot.loader == "systemd-boot";

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
  boot.tmp.cleanOnBoot = true;

  # ── Branding ───────────────────────────────────────────────────────
  # A screen the public looks at should not boot showing kernel messages
  bauergroup.features.branding.enable = lib.mkDefault true;

  # ── Containers (backend services) ──────────────────────────────────
  bauergroup.services.containers.enableOnBoot = lib.mkDefault true;

  # ── Monitoring (node exporter for fleet visibility) ────────────────
  bauergroup.services.monitoring.exporterOnly = lib.mkDefault true;

  # ── Networking ─────────────────────────────────────────────────────
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 1;

  environment.systemPackages = with pkgs; [
    curl
    htop
  ];

  # ── State Version ──────────────────────────────────────────────────
  system.stateVersion = "26.05";
}
