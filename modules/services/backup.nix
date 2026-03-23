# modules/services/backup.nix
# ─────────────────────────────────────────────────────────────────────
# Restic backup with BAUER GROUP defaults.
# Enable via: bauergroup.services.backup.enable = true;
#
# Prerequisites:
#   1. Create restic repo password: agenix -e secrets/restic-password.age
#   2. Initialize repo: restic -r sftp:backup@storage:/backups/$(hostname) init
#   3. Set repository URL in bauergroup.services.backup.repository
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.bauergroup.services.backup;
in
{
  options.bauergroup.services.backup = {
    enable = lib.mkEnableOption "Restic backup";

    repository = lib.mkOption {
      type = lib.types.str;
      description = "Restic repository URL (e.g. sftp:user@host:/backups/hostname).";
      example = "sftp:backup@storage.bauer-group.de:/backups/prod-server-01";
    };

    passwordFile = lib.mkOption {
      type = lib.types.path;
      description = "Path to file containing the restic repository password (use agenix).";
      example = "/run/agenix/restic-password";
    };

    paths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/opt"
        "/var/lib"
        "/home"
        "/etc/nixos"
      ];
      description = "Paths to back up.";
    };

    excludePaths = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/var/lib/docker/overlay2"
        "/var/lib/docker/image"
        "/var/cache"
        "/var/tmp"
      ];
      description = "Paths to exclude from backup.";
    };

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "Backup schedule (systemd calendar expression).";
      example = "*-*-* 03:00:00";
    };

    retentionDays = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Number of daily snapshots to keep.";
    };

    retentionWeeks = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Number of weekly snapshots to keep.";
    };

    retentionMonths = lib.mkOption {
      type = lib.types.int;
      default = 6;
      description = "Number of monthly snapshots to keep.";
    };

    preBackupScript = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Script to run before backup (e.g. database dump).";
      example = ''
        ${pkgs.docker}/bin/docker exec outline-postgres pg_dumpall -U outline > /opt/outline/backup/db-dump.sql
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.restic.backups.system = {
      repository = cfg.repository;
      passwordFile = cfg.passwordFile;
      paths = cfg.paths;
      exclude = cfg.excludePaths;

      timerConfig = {
        OnCalendar = cfg.schedule;
        Persistent = true;
        RandomizedDelaySec = "1h";
      };

      pruneOpts = [
        "--keep-daily ${toString cfg.retentionDays}"
        "--keep-weekly ${toString cfg.retentionWeeks}"
        "--keep-monthly ${toString cfg.retentionMonths}"
      ];

      backupPrepareCommand = lib.mkIf (cfg.preBackupScript != "") cfg.preBackupScript;
    };

    # Restic CLI available for manual operations
    environment.systemPackages = [ pkgs.restic ];
  };
}
