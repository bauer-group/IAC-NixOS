# hosts/prod-server-01/default.nix
# ─────────────────────────────────────────────────────────────────────
# Production Server 01 — e.g. Hetzner Dedicated / Cloud
# ─────────────────────────────────────────────────────────────────────
{ config, lib, pkgs, inputs, ... }: {

  # ── Identity ─────────────────────────────────────────────────────
  networking.hostName = "prod-server-01";

  # ── Boot (Hetzner typically uses GRUB) ──────────────────────────
  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";   # TODO: adjust for your disk
  };

  # ── Disk Layout (disko) ─────────────────────────────────────────
  # Uncomment and adjust for automated disk partitioning via disko
  # disko.devices = {
  #   disk.main = {
  #     device = "/dev/sda";
  #     type = "disk";
  #     content = {
  #       type = "gpt";
  #       partitions = {
  #         boot = { size = "1M"; type = "EF02"; };
  #         root = {
  #           size = "100%";
  #           content = {
  #             type = "filesystem";
  #             format = "ext4";
  #             mountpoint = "/";
  #           };
  #         };
  #       };
  #     };
  #   };
  # };

  # ── Placeholder filesystem (replace with disko or real config) ──
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-ME";
    fsType = "ext4";
  };

  # ── Network ─────────────────────────────────────────────────────
  networking = {
    # Static IP (typical for Hetzner)
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "10.0.0.1";     # TODO: real IP
        prefixLength = 24;
      }];
    };
    defaultGateway = "10.0.0.254";  # TODO: real gateway
    nameservers = [ "1.1.1.1" "8.8.8.8" ];

    # Firewall: open web ports
    firewall.allowedTCPPorts = [ 80 443 ];
  };

  # ── Services ────────────────────────────────────────────────────
  # Traefik as reverse proxy (example, adjust to your setup)
  # services.traefik = {
  #   enable = true;
  #   ...
  # };

  # ── Auto-upgrade (opt-in for production) ────────────────────────
  # system.autoUpgrade = {
  #   enable = true;
  #   flake = "github:your-org/bauer-nix";
  #   dates = "04:00";
  #   allowReboot = true;
  #   rebootWindow = { lower = "03:00"; upper = "05:00"; };
  # };

  # ── State Version ───────────────────────────────────────────────
  system.stateVersion = "25.11";
}
