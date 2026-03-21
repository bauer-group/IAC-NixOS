# hosts/prod-server-02/default.nix
# ─────────────────────────────────────────────────────────────────────
# Production Server 02 — e.g. second Hetzner node
# ─────────────────────────────────────────────────────────────────────
{ config, lib, pkgs, ... }: {

  networking.hostName = "prod-server-02";

  boot.loader.grub = {
    enable = true;
    device = "/dev/sda";
  };

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-ME";
    fsType = "ext4";
  };

  networking = {
    useDHCP = false;
    interfaces.eth0 = {
      ipv4.addresses = [{
        address = "10.0.0.2";
        prefixLength = 24;
      }];
    };
    defaultGateway = "10.0.0.254";
    nameservers = [ "1.1.1.1" "8.8.8.8" ];
    firewall.allowedTCPPorts = [ 80 443 ];
  };

  system.stateVersion = "25.11";
}
