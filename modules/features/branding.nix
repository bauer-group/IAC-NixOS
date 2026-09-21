# modules/features/branding.nix
# ─────────────────────────────────────────────────────────────────────
# BAUER GROUP boot splash.
#
# A kiosk or HMI is judged from the moment it is switched on. A wall of
# kernel messages in front of a customer, or on a panel at a machine, reads
# as "broken computer" rather than "product starting up".
#
# Enable via: bauergroup.features.branding.enable = true;
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.bauergroup.features.branding;

  theme = pkgs.callPackage ../../pkgs/plymouth-theme-bauergroup {
    logo = ../../assets/branding/bauer-group-logo-wide-white.svg;
    inherit (cfg)
      background
      accent
      track
      foreground
      ;
  };
in
{
  options.bauergroup.features.branding = {
    enable = lib.mkEnableOption "BAUER GROUP boot splash (Plymouth)";

    background = lib.mkOption {
      type = lib.types.str;
      default = "#231F1C";
      description = "Splash background. Default is the brand-black token (warm-900).";
    };

    accent = lib.mkOption {
      type = lib.types.str;
      default = "#FF8500";
      description = ''
        Progress bar fill, and the corrected fill for the logo's mark. Default
        is the brand primary (orange-500).
      '';
    };

    track = lib.mkOption {
      type = lib.types.str;
      default = "#3A3430";
      description = "Progress bar track. Default is the brand-dark token (warm-800).";
    };

    foreground = lib.mkOption {
      type = lib.types.str;
      default = "#F9F8F6";
      description = "Status and password-prompt text. Default is the brand-light token (warm-50).";
    };

    silentBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Quieten the kernel and initrd so the splash is not overdrawn by log
        output. Turn off while commissioning hardware, when the messages the
        splash hides are exactly the ones worth reading.

        Errors still reach the journal either way; this only affects the
        console during boot.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    boot.plymouth = {
      enable = true;
      theme = "bauergroup";
      themePackages = [ theme ];
    };

    # Already the NixOS default on 26.05; stated here because the splash
    # depends on it. systemd in the initrd hands over to the running system
    # without tearing the splash down and putting it back up, and is what lets
    # Plymouth prompt for a disk passphrase at all. mkDefault, so a machine
    # that has deliberately turned it off keeps its choice.
    boot.initrd.systemd.enable = lib.mkDefault true;

    boot.kernelParams = lib.mkIf cfg.silentBoot [
      "quiet"
      "splash"
      "loglevel=3"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];

    boot.consoleLogLevel = lib.mkIf cfg.silentBoot (lib.mkDefault 0);
    boot.initrd.verbose = lib.mkIf cfg.silentBoot (lib.mkDefault false);
  };
}
