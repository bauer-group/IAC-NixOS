# modules/baseline/auto-update.nix
# ─────────────────────────────────────────────────────────────────────
# Automatic system updates from Git.
# Pulls the latest flake, rebuilds, and reboots if needed.
# Controlled via bauergroup.params.autoUpdate.*
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  config,
  ...
}:
let
  cfg = config.bauergroup.params.autoUpdate;
in
{
  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      flake = cfg.flake;
      dates = cfg.schedule;
      allowReboot = cfg.allowReboot;
      rebootWindow = {
        lower = cfg.rebootWindowStart;
        upper = cfg.rebootWindowEnd;
      };
      # Use --impure so /etc/nixos/params.nix is read
      flags = [ "--impure" ];
    };
  };
}
