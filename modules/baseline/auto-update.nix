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

  # nixos-rebuild falls back to the hostname when the URI has no #attribute,
  # but configurations are named after templates (server, desktop-dev, ...)
  flakeRef = if lib.hasInfix "#" cfg.flake then cfg.flake else "${cfg.flake}#${cfg.template}";
in
{
  config = lib.mkIf cfg.enable {
    system.autoUpgrade = {
      enable = true;
      flake = flakeRef;
      dates = cfg.schedule;
      inherit (cfg) allowReboot;
      rebootWindow = {
        lower = cfg.rebootWindowStart;
        upper = cfg.rebootWindowEnd;
      };
      # Use --impure so /etc/nixos/params.nix is read
      flags = [ "--impure" ];
    };
  };
}
