# modules/services/docker.nix
# ─────────────────────────────────────────────────────────────────────
# Docker Engine with BAUER GROUP defaults.
# Enable via: bauer.services.docker.enable = true;
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.bauer.services.docker;
in
{
  options.bauer.services.docker = {
    enable = lib.mkEnableOption "Docker Engine with BAUER GROUP defaults";

    enableOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Start Docker daemon on boot. Set to false for on-demand usage (desktop).";
    };

    storageDriver = lib.mkOption {
      type = lib.types.str;
      default = "overlay2";
      description = "Docker storage driver.";
    };

    logMaxSize = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = "Maximum size of a container log file before rotation.";
    };

    logMaxFiles = lib.mkOption {
      type = lib.types.str;
      default = "3";
      description = "Number of rotated log files to keep per container.";
    };

    pruneSchedule = lib.mkOption {
      type = lib.types.str;
      default = "weekly";
      description = "How often to prune unused images (systemd calendar expression).";
    };

    pruneKeepHours = lib.mkOption {
      type = lib.types.int;
      default = 168;
      description = "Remove images older than this many hours during prune.";
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = cfg.enableOnBoot;
      storageDriver = cfg.storageDriver;

      # Live restore: containers keep running during daemon restart
      liveRestore = true;

      # Log rotation
      daemon.settings = {
        "log-driver" = "json-file";
        "log-opts" = {
          "max-size" = cfg.logMaxSize;
          "max-file" = cfg.logMaxFiles;
        };
      };

      # Auto-prune unused images
      autoPrune = {
        enable = true;
        dates = cfg.pruneSchedule;
        flags = [
          "--all"
          "--filter"
          "until=${toString cfg.pruneKeepHours}h"
        ];
      };
    };

    # Docker Compose + TUI
    environment.systemPackages = with pkgs; [
      docker-compose
      lazydocker
    ];

    # Container networking requires IP forwarding
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  };
}
