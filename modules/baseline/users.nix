# modules/baseline/users.nix
# ─────────────────────────────────────────────────────────────────────
# User accounts baseline.
# Define all human users here; service accounts go in their service modules.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, ... }: {

  # Don't allow imperative user management
  users.mutableUsers = lib.mkDefault false;

  users.users.karl = {
    isNormalUser = true;
    description = "Karl — BAUER GROUP";
    extraGroups = [
      "wheel"       # sudo
      "networkmanager"
      "docker"
      "dialout"     # serial / CAN-Bus USB adapters
      "plugdev"     # USB devices
    ];

    # TODO: Replace with your actual SSH public key(s)
    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAAC3Nza... karl@desktop"
    ];

    shell = pkgs.zsh;
  };

  # Enable zsh system-wide (needed for user shell)
  programs.zsh.enable = true;

  # Passwordless sudo for wheel group (convenience for deployment)
  # For tighter security, remove this and use agenix for sudo passwords
  security.sudo.wheelNeedsPassword = lib.mkDefault false;
}
