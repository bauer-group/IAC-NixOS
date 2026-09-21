# modules/features/kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# Binds bauergroup.params.kiosk to the generic kiosk runtime, and holds the
# policy both kiosk templates share: an unprivileged session account, a
# password-gated sudo on a physically exposed machine, the backend compose
# project, and the freeze watchdog.
#
# Imported by templates/desktop-kiosk.nix and templates/embedded-kiosk.nix.
# The runtime itself lives in modules/services/kiosk.nix and knows nothing
# about params.
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

  containers = config.bauergroup.services.containers;
  engineUnit = if containers.engine == "docker" then "docker.service" else "podman.socket";

  isBrowser = kiosk.mode == "browser";

  # Chromium's DevTools endpoint stops answering when the browser process
  # wedges — the freeze that leaves a still image up while systemd stays
  # healthy. Nothing equivalent exists for an arbitrary native binary, so an
  # application kiosk has to supply its own probe.
  debugPort = 9222;
  browserProbe = "${pkgs.curl}/bin/curl -sf --max-time 5 http://127.0.0.1:${toString debugPort}/json/version";

  healthCheck =
    if kiosk.healthCheckCommand != null then
      kiosk.healthCheckCommand
    else if isBrowser then
      browserProbe
    else
      null;

  watchdogUsable = kiosk.watchdog && healthCheck != null;

  # The DevTools endpoint can drive the browser, so it is opened only when it
  # is the thing actually being probed. An operator who supplies their own
  # healthCheckCommand gets no debug port they did not ask for.
  usesBrowserProbe = isBrowser && watchdogUsable && kiosk.healthCheckCommand == null;
in
{
  imports = [
    ../services/kiosk.nix
    ../services/watchdog.nix
    ../services/containers.nix
  ];

  # ── Runtime ─────────────────────────────────────────────────────────
  bauergroup.services.kiosk = {
    enable = true;
    inherit (kiosk)
      user
      mode
      touchscreen
      rotation
      multiMonitor
      allowVtSwitch
      idleTimeout
      extraGroups
      ;

    # A site that renames its container socket group must not thereby open a
    # hole in the check that keeps that group off the session account
    privilegedGroups = lib.mkDefault (
      lib.unique (
        [
          "wheel"
          "docker"
          "podman"
        ]
        ++ [ containers.socketGroup ]
      )
    );

    browser = {
      inherit (kiosk) url extraFlags;
      remoteDebuggingPort = lib.mkIf usesBrowserProbe debugPort;
    };

    application = {
      inherit (kiosk.application)
        command
        environment
        foreignBinaries
        extraLibraries
        ;
    };

    # Waiting on the backend avoids showing a connection error during the few
    # seconds a compose project needs to come up after a cold boot. A browser
    # kiosk can be probed generically by fetching its own URL; a native HMI
    # has to say what "ready" means for it.
    startupProbe =
      if kiosk.startupProbe != null then
        kiosk.startupProbe
      else
        lib.mkIf isBrowser "${pkgs.curl}/bin/curl -sf --max-time 5 ${lib.escapeShellArg kiosk.url}";
  };

  # ── Watchdog ────────────────────────────────────────────────────────
  bauergroup.services.watchdog.application = lib.mkIf watchdogUsable {
    enable = true;
    unit = "cage-tty1.service";
    healthCheckCommand = healthCheck;
    inherit (kiosk) startupGrace;
  };

  # ── Backend compose project ─────────────────────────────────────────
  systemd.services.kiosk-backend = lib.mkIf (kiosk.composeFile != null) {
    description = "Kiosk backend services (Compose)";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    # Docker has a daemon to wait for; Podman is daemonless and reached through
    # a socket-activated unit, so each engine has its own thing to order behind
    after = [
      "network-online.target"
      engineUnit
    ];
    requires = [ engineUnit ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = kiosk.composeDirectory;
      ExecStart = "${containers.composeCommand} up -d";
      ExecStop = "${containers.composeCommand} down";
      TimeoutStartSec = "120";

      # Hardening
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      NoNewPrivileges = true;
      ReadWritePaths = [ kiosk.composeDirectory ];
    };

    preStart = ''
      mkdir -p ${kiosk.composeDirectory}
      cp -f ${kiosk.composeFile} ${kiosk.composeDirectory}/docker-compose.yml
    '';
  };

  # ── Safety ──────────────────────────────────────────────────────────
  assertions = [
    {
      assertion = kiosk.user != userParams.name;
      message = ''
        bauergroup.params.kiosk.user ("${kiosk.user}") must differ from user.name:
        the kiosk session must not run as the admin account. Kiosks set up with
        user.name = "kiosk" (older docs) should set kiosk.user to a new, unused
        name such as "kiosk-display"; do not reuse the admin's home directory.
      '';
    }
  ];

  warnings =
    lib.optional (userParams.hashedPassword == null) ''
      kiosk: user.hashedPassword is not set, so "${userParams.name}" cannot use sudo
      (sudo requires a password on kiosks). Auto-updates still work.
    ''
    ++ lib.optional (kiosk.watchdog && healthCheck == null) ''
      kiosk: watchdog is enabled but kiosk.mode = "application" supplies no
      kiosk.healthCheckCommand, so a frozen HMI cannot be detected. The session
      still restarts when the process exits, and the hardware watchdog still
      covers a kernel freeze. Add a probe that exits 0 while the HMI is
      responsive — typically a request against a health endpoint it serves.
    '';

  # Physically exposed device: the admin account needs its password for sudo
  security.sudo.wheelNeedsPassword = lib.mkForce true;

  services.fail2ban = {
    enable = lib.mkDefault true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment.enable = true;
  };
}
