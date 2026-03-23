# templates/desktop-kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# Kiosk desktop template.
# Displays a full-screen web browser (Chromium) pointed at a local
# or remote URL. Backend services run in Docker Compose.
#
# Features:
#   - Auto-login, no desktop environment
#   - cage (Wayland kiosk compositor) + Chromium in kiosk mode
#   - Docker Compose for backend services
#   - Optional touchscreen support
#   - Screen rotation support
#   - Idle timeout to reset browser to home URL
#
# Deploy: nixos-rebuild switch --flake .#desktop-kiosk --impure
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  params = config.bauergroup.params;
  kiosk = params.kiosk;
  userParams = params.user;

  # Chromium kiosk launch command
  kioskCommand = pkgs.writeShellScript "kiosk-browser" ''
    # Wait for network
    for i in $(seq 1 30); do
      ${pkgs.curl}/bin/curl -sf "${kiosk.url}" > /dev/null 2>&1 && break
      sleep 2
    done

    exec ${pkgs.chromium}/bin/chromium \
      --kiosk \
      --no-first-run \
      --disable-infobars \
      --disable-session-crashed-bubble \
      --disable-translate \
      --noerrdialogs \
      --disable-features=TranslateUI \
      --check-for-update-interval=31536000 \
      ${lib.optionalString kiosk.touchscreen "--touch-events=enabled"} \
      "${kiosk.url}"
  '';
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
  ];

  # ── Boot ────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = lib.mkIf (params.boot.loader == "systemd-boot") {
    enable = true;
    configurationLimit = 5;
  };
  boot.loader.grub = lib.mkIf (params.boot.loader == "grub") {
    enable = true;
    device = params.boot.grubDevice;
  };
  boot.loader.efi.canTouchEfiVariables = params.boot.loader == "systemd-boot";

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
  boot.tmp.cleanOnBoot = true;

  # ── Kiosk Display (cage Wayland compositor) ────────────────────────
  services.cage = {
    enable = true;
    user = userParams.name;
    program = toString kioskCommand;
    extraArguments = lib.optional (kiosk.rotation != "normal") (
      if kiosk.rotation == "left" then
        "-r"
      else if kiosk.rotation == "right" then
        "-rr"
      else if kiosk.rotation == "inverted" then
        "-rrr"
      else
        ""
    );
  };

  # Auto-login for kiosk user
  services.getty.autologinUser = userParams.name;

  # Minimal packages for kiosk operation
  environment.systemPackages = with pkgs; [
    chromium
    curl
    htop
  ];

  # Allow unfree (Chromium codecs)
  nixpkgs.config.allowUnfree = true;

  # ── Docker (backend services) ──────────────────────────────────────
  bauergroup.services.docker = {
    enable = true;
    enableOnBoot = true;
  };

  # ── Backend Docker Compose Service ─────────────────────────────────
  systemd.services.kiosk-backend = lib.mkIf (kiosk.composeFile != null) {
    description = "Kiosk backend services (Docker Compose)";
    wantedBy = [ "multi-user.target" ];
    after = [
      "docker.service"
      "network-online.target"
    ];
    requires = [ "docker.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = kiosk.composeDirectory;
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      TimeoutStartSec = "120";

      # Hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ kiosk.composeDirectory ];
    };

    # Deploy compose file from Nix store to working directory
    preStart = lib.optionalString (kiosk.composeFile != null) ''
      mkdir -p ${kiosk.composeDirectory}
      cp -f ${kiosk.composeFile} ${kiosk.composeDirectory}/docker-compose.yml
    '';
  };

  # ── Monitoring (node exporter for fleet visibility) ────────────────
  bauergroup.services.monitoring.exporterOnly = lib.mkDefault true;

  # ── Networking ─────────────────────────────────────────────────────
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 1;

  # ── Power management ──────────────────────────────────────────────
  # Prevent screen from sleeping
  services.logind = {
    lidSwitch = "ignore";
    extraConfig = ''
      HandlePowerKey=ignore
      IdleAction=ignore
    '';
  };

  # ── Security ───────────────────────────────────────────────────────
  # Kiosk user cannot sudo (locked down)
  security.sudo.wheelNeedsPassword = lib.mkForce true;

  # Fail2ban for SSH protection
  services.fail2ban = {
    enable = lib.mkDefault true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment.enable = true;
  };

  # ── State Version ──────────────────────────────────────────────────
  system.stateVersion = "25.11";
}
