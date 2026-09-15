# modules/baseline/users.nix
# ─────────────────────────────────────────────────────────────────────
# User account baseline — reads from bauergroup.params.user.
# Creates the primary user with groups, SSH keys, and shell.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  userParams = config.bauergroup.params.user;
  account = config.users.users.${userParams.name};
in
{
  # NixOS only checks that root or some wheel user can log in, and its message
  # does not name the params to set. Other credential options (e.g.
  # hashedPasswordFile from agenix) set in /etc/nixos/params.nix count too.
  assertions = [
    {
      assertion =
        config.users.mutableUsers
        || config.users.allowNoPasswordLogin
        || account.openssh.authorizedKeys.keys != [ ]
        || account.openssh.authorizedKeys.keyFiles != [ ]
        || account.hashedPassword != null
        || account.hashedPasswordFile != null
        || account.password != null;
      message = ''
        bauergroup.params.user: set user.sshKeys or user.hashedPassword in /etc/nixos/params.nix.
        Users are managed declaratively (users.mutableUsers = false), so without either
        the account "${userParams.name}" could never log in.
      '';
    }
  ];

  # Don't allow imperative user management
  users.mutableUsers = lib.mkDefault false;

  users.users.${userParams.name} = {
    isNormalUser = true;
    description = userParams.fullName;
    extraGroups = [
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
