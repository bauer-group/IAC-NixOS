# templates/server.nix
# ─────────────────────────────────────────────────────────────────────
# Headless server template.
# Hardened, with Docker-based services defined via params.
# Each Docker Compose project gets its own systemd service.
#
# Deploy: nixos-rebuild switch --flake .#server --impure
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  params = config.bauer.params;
  serverParams = params.server;
in
{
  imports = [
    ../modules/baseline/ntp.nix
    ../modules/baseline/ssh.nix
    ../modules/baseline/users.nix
    ../modules/baseline/networking.nix
    ../modules/baseline/nix.nix
    ../modules/baseline/auto-update.nix
    ../modules/services/docker.nix
    ../modules/services/monitoring.nix
    ../modules/services/backup.nix
  ];

  # ── Boot ────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = lib.mkIf (params.boot.loader == "systemd-boot") {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.grub = lib.mkIf (params.boot.loader == "grub") {
    enable = true;
    device = params.boot.grubDevice;
  };
  boot.loader.efi.canTouchEfiVariables = params.boot.loader == "systemd-boot";

  # Servers use stable LTS kernel
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
  boot.tmp.cleanOnBoot = lib.mkDefault true;

  # ── Security ───────────────────────────────────────────────────────
  security.auditd.enable = lib.mkDefault true;
  security.audit = {
    enable = lib.mkDefault true;
    rules = [ "-a exit,always -F arch=b64 -S execve" ];
  };

  services.fail2ban = {
    enable = lib.mkDefault true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment.enable = true;
  };

  # ── Monitoring ─────────────────────────────────────────────────────
  bauer.services.monitoring.exporterOnly = lib.mkDefault serverParams.monitoring;

  # ── Journald ───────────────────────────────────────────────────────
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=30day
  '';

  # ── Networking ─────────────────────────────────────────────────────
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 2;

  # ── Docker ─────────────────────────────────────────────────────────
  bauer.services.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # ── Dynamic Docker Compose Services ────────────────────────────────
  # Creates a systemd service for each entry in bauer.params.server.composeProjects
  systemd.services = lib.mapAttrs' (
    name: project:
    lib.nameValuePair "compose-${name}" {
      description = "Docker Compose: ${name}";
      wantedBy = [ "multi-user.target" ];
      after = [
        "docker.service"
        "network-online.target"
      ];
      requires = [ "docker.service" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = project.directory;
        ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
        ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
        TimeoutStartSec = "120";

        # Hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ project.directory ];
      };

      preStart = lib.optionalString (project.envFile != null) ''
        cp -f ${project.envFile} ${project.directory}/.env
        chmod 600 ${project.directory}/.env
      '';
    }
  ) serverParams.composeProjects;

  # ── Backup ─────────────────────────────────────────────────────────
  bauer.services.backup = lib.mkIf serverParams.backup.enable {
    enable = true;
    repository = serverParams.backup.repository;
    passwordFile = serverParams.backup.passwordFile;
    paths = serverParams.backup.paths;
  };

  # ── State Version ──────────────────────────────────────────────────
  system.stateVersion = "25.11";
}
