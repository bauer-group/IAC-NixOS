# modules/baseline/users.nix
# ─────────────────────────────────────────────────────────────────────
# User account baseline — reads from bauer.params.user.
# Creates the primary user with groups, SSH keys, and shell.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  userParams = config.bauer.params.user;
in
{
  # Don't allow imperative user management
  users.mutableUsers = lib.mkDefault false;

  users.users.${userParams.name} = {
    isNormalUser = true;
    description = userParams.fullName;
    extraGroups =
      [
        "wheel" # sudo
        "networkmanager"
        "docker"
        "dialout" # serial / CAN-Bus USB adapters
        "plugdev" # USB devices
      ]
      ++ userParams.extraGroups;

    openssh.authorizedKeys.keys = userParams.sshKeys;

    # Password: either from params or login only via SSH
    hashedPassword = lib.mkIf (userParams.hashedPassword != null) userParams.hashedPassword;

    shell = pkgs.zsh;
  };

  # Enable zsh system-wide (needed for user shell)
  programs.zsh.enable = true;

  # Passwordless sudo for wheel group (convenience for deployment)
  security.sudo.wheelNeedsPassword = lib.mkDefault false;
}
