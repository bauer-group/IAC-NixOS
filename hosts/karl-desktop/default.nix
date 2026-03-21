# hosts/karl-desktop/default.nix
# ─────────────────────────────────────────────────────────────────────
# Karl's development workstation.
# Hardware-specific settings + host overrides.
# ─────────────────────────────────────────────────────────────────────
{ config, lib, pkgs, inputs, ... }: {

  imports = [
    ./hardware-configuration.nix
  ];

  # ── Identity ─────────────────────────────────────────────────────
  networking.hostName = "karl-desktop";

  # ── Boot ─────────────────────────────────────────────────────────
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Keep last 10 generations in boot menu
  boot.loader.systemd-boot.configurationLimit = 10;

  # ── Timezone override (when in Thailand) ─────────────────────────
  # Uncomment when working from Thailand:
  # time.timeZone = lib.mkForce "Asia/Bangkok";

  # ── Home Manager ─────────────────────────────────────────────────
  home-manager.users.karl = import ../../home/karl.nix;

  # ── Extra packages (host-specific) ──────────────────────────────
  environment.systemPackages = with pkgs; [
    # VPN for remote server access
    wireguard-tools
    openvpn

    # VM management (local testing)
    qemu
    virt-manager
    libvirt
  ];

  # ── Virtualisation ──────────────────────────────────────────────
  virtualisation.libvirtd.enable = true;

  # ── Bluetooth ───────────────────────────────────────────────────
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # ── GPU (uncomment the appropriate section) ─────────────────────
  # AMD:
  # hardware.graphics.enable = true;
  # hardware.graphics.extraPackages = with pkgs; [ amdvlk ];

  # NVIDIA:
  # hardware.nvidia.modesetting.enable = true;
  # services.xserver.videoDrivers = [ "nvidia" ];

  # Intel:
  # hardware.graphics.enable = true;
  # hardware.graphics.extraPackages = with pkgs; [ intel-media-driver ];

  # ── NixOS State Version ─────────────────────────────────────────
  # DO NOT CHANGE after initial install
  system.stateVersion = "25.11";
}
