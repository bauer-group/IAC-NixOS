# templates/desktop-kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# Kiosk desktop template.
# Displays a full-screen web browser (Chromium) pointed at a local
# or remote URL. Backend services run in Docker Compose.
#
# Features:
#   - No desktop environment; the session runs as an unprivileged kiosk user
#   - cage (Wayland kiosk compositor) + Chromium in kiosk mode
#   - Browser and compositor restart automatically
#   - Docker Compose for backend services
#   - Optional touchscreen support
#   - Screen rotation (via wlr-randr)
#   - Idle timeout to reset browser to home URL (via swayidle)
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
  inherit (params) kiosk;
  userParams = params.user;

  url = lib.escapeShellArg kiosk.url;
  wlr-randr = "${pkgs.wlr-randr}/bin/wlr-randr";

  # wl_output transforms rotate counter-clockwise, so xrandr's "left" is 90.
  # cage dropped its own -r flag in 0.1.5 in favour of wlr-output-management.
  transform = {
    left = "90";
    inverted = "180";
    right = "270";
  };

  # Runs inside cage, which sets WAYLAND_DISPLAY for wlr-randr and swayidle
  kioskSession = pkgs.writeShellScript "kiosk-session" ''
    set -u

    # Wait for the backend, but show the page (or its error) after about a minute
    for _ in $(seq 1 30); do
      ${pkgs.curl}/bin/curl -sf --max-time 5 ${url} > /dev/null 2>&1 && break
      sleep 2
    done

    ${lib.optionalString (kiosk.rotation != "normal") ''
      rotate() {
        # Output names are the first word of wlr-randr's non-indented lines
        for output in $(${wlr-randr} | ${pkgs.gnugrep}/bin/grep -v '^ ' | ${pkgs.coreutils}/bin/cut -d' ' -f1); do
          ${wlr-randr} --output "$output" --transform ${transform.${kiosk.rotation}} \
            || echo "kiosk: could not rotate $output" >&2
        done
      }
    ''}

    browser=
    ${lib.optionalString (kiosk.idleTimeout != null) ''
      # swayidle sends USR1 once per idle period; the loop below restarts
      # the browser at the home URL. Video playback inhibits idle.
      trap '[ -n "$browser" ] && kill "$browser" 2>/dev/null' USR1
      ${pkgs.swayidle}/bin/swayidle timeout ${toString kiosk.idleTimeout} "kill -USR1 $$" &
      idle=$!
      # cage exits only when every child is gone, so never leave swayidle behind
      trap 'kill "$idle" 2>/dev/null' EXIT
    ''}

    # Chromium runs in the background so the idle trap can fire while we wait,
    # and a crashed or closed browser comes back instead of leaving a dark screen
    while true; do
      ${lib.optionalString (kiosk.rotation != "normal") "rotate"}
      ${pkgs.chromium}/bin/chromium \
        --ozone-platform=wayland \
        --kiosk \
        --no-first-run \
        --disable-infobars \
        --disable-session-crashed-bubble \
        --disable-translate \
        --noerrdialogs \
        --disable-features=TranslateUI \
        --check-for-update-interval=31536000 \
        ${lib.optionalString kiosk.touchscreen "--touch-events=enabled"} \
        ${url} &
      browser=$!
      # Poll instead of a blocking wait: the idle trap interrupts the sleep, and
      # cage re-creates a re-plugged display with transform normal
      while kill -0 "$browser" 2>/dev/null; do
        ${lib.optionalString (kiosk.rotation != "normal") ''
          ${wlr-randr} | ${pkgs.gnugrep}/bin/grep -qx '  Transform: normal' && rotate
        ''}
        sleep 5 &
        wait $!
      done
      browser=
      sleep 2
    done
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
  # cage opens its own PAM session for the kiosk user, so no console
  # auto-login is needed and every other TTY keeps its login prompt
  services.cage = {
    enable = true;
    inherit (kiosk) user;
    program = kioskSession;
  };

  # The browser runs as its own account: a compromised page must not reach
  # the admin's SSH keys, sudo or the Docker socket (root-equivalent)
  users.users.${kiosk.user} = {
    isNormalUser = true;
    # mkDefault: if kiosk.user equals user.name, the assertion below reports it
    # instead of a conflicting-definition error for the description
    description = lib.mkDefault "Kiosk session";
  };

  assertions = [
    {
      assertion = kiosk.user != userParams.name;
      message = ''
        bauergroup.params.kiosk.user ("${kiosk.user}") must differ from user.name:
        the kiosk browser must not run as the admin account. Kiosks set up with
        user.name = "kiosk" (older docs) should set kiosk.user to a new, unused
        name such as "kiosk-display"; do not reuse the admin's home directory.
      '';
    }
  ];

  warnings = lib.optional (userParams.hashedPassword == null) ''
    desktop-kiosk: user.hashedPassword is not set, so "${userParams.name}" cannot use sudo
    (sudo requires a password on kiosks). Auto-updates still work.
  '';

  # Without a display manager, getty.target wants autovt@tty1. Every switch
  # starts all active targets, and that start would stop cage-tty1 through its
  # Conflicts= (a job-requested stop that Restart= does not undo). Masking
  # both names keeps tty1 for cage, as nixpkgs does for display managers.
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # wlroots does not map touchscreens to an output, so the wlr-randr transform
  # never reaches touch input; rotate it in libinput with the same matrix
  services.udev.extraRules = lib.mkIf (kiosk.touchscreen && kiosk.rotation != "normal") ''
    ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="${
      {
        left = "0 -1 1 1 0 0";
        inverted = "-1 0 1 0 -1 1";
        right = "0 1 0 -1 0 1";
      }
      .${kiosk.rotation}
    }"
  '';

  systemd.services.cage-tty1 = {
    # The nixpkgs module sets neither: the session would stay dark after a
    # crash, and new kiosk settings would only apply after a reboot
    restartIfChanged = lib.mkForce true;
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
    };
    # A kiosk has nobody to notice a failed unit, so never stop retrying
    startLimitIntervalSec = 0;
  };

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
    wants = [ "network-online.target" ];
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
  services.logind.settings.Login = {
    HandleLidSwitch = "ignore";
    HandlePowerKey = "ignore";
    IdleAction = "ignore";
  };

  # ── Security ───────────────────────────────────────────────────────
  # Physically exposed device: the admin account needs its password for sudo
  security.sudo.wheelNeedsPassword = lib.mkForce true;

  # Fail2ban for SSH protection
  services.fail2ban = {
    enable = lib.mkDefault true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment.enable = true;
  };

  # ── State Version ──────────────────────────────────────────────────
  system.stateVersion = "26.05";
}
