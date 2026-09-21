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
  params = config.bauergroup.params;
  serverParams = params.server;

  inherit (config.bauergroup.services.containers) composeCommand;
  # Docker has a daemon to wait for; Podman is daemonless and reached through a
  # socket-activated unit, so each engine has its own thing to order behind
  engineUnit =
    if config.bauergroup.services.containers.engine == "docker" then
      "docker.service"
    else
      "podman.socket";
in
{
  imports = [
    ../modules/baseline/ntp.nix
    ../modules/baseline/ssh.nix
    ../modules/baseline/users.nix
    ../modules/baseline/networking.nix
    ../modules/baseline/nix.nix
    ../modules/baseline/auto-update.nix
    ../modules/baseline/platform.nix
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
  bauergroup.services.monitoring.exporterOnly = lib.mkDefault serverParams.monitoring;

  # ── Journald ───────────────────────────────────────────────────────
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=30day
  '';

  # ── Networking ─────────────────────────────────────────────────────
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 2;

  # ── Containers ─────────────────────────────────────────────────────
  bauergroup.services.containers.enableOnBoot = lib.mkDefault true;

  # ── Dynamic Compose Services ───────────────────────────────────────
  # Creates a systemd service for each entry in bauergroup.params.server.composeProjects.
  # Engine-independent: Podman serves the same API socket, and only Docker has
  # a daemon unit to order against.
  systemd.services = lib.mapAttrs' (
    name: project:
    lib.nameValuePair "compose-${name}" {
      description = "Compose project: ${name}";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [
        "network-online.target"
        engineUnit
      ];
      requires = [ engineUnit ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = project.directory;
        ExecStart = "${composeCommand} up -d";
        ExecStop = "${composeCommand} down";
        TimeoutStartSec = "120";

        # Hardening
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ project.directory ];
      };

      preStart = lib.optionalString (project.envFile != null) ''
        cp -f ${toString project.envFile} ${project.directory}/.env
        chmod 600 ${project.directory}/.env
      '';
    }
  ) serverParams.composeProjects;

  # ── Backup ─────────────────────────────────────────────────────────
  bauergroup.services.backup = lib.mkIf serverParams.backup.enable {
    enable = true;
    repository = serverParams.backup.repository;
    passwordFile = serverParams.backup.passwordFile;
    paths = serverParams.backup.paths;
  };

  # ── State Version ──────────────────────────────────────────────────
  system.stateVersion = "26.05";
}
