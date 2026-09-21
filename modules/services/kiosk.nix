# modules/services/kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# Single-application kiosk runtime on cage, a Wayland compositor that shows
# exactly one window fullscreen and offers no way to move, minimise or close
# it. Two payloads share the whole session:
#
#   mode = "browser"      Chromium with --ozone-platform=wayland, so touch
#                         input and vsync go through Wayland directly rather
#                         than through XWayland.
#
#   mode = "application"  Any native binary — a .NET/Avalonia HMI, Qt, GTK.
#                         cage ships XWayland and exports DISPLAY to its child,
#                         so an X11 toolkit such as Avalonia needs no porting.
#
# Everything around the payload is identical either way: restart on exit,
# rotation, idle reset, health probing. Only the launch command differs.
#
# Enable via: bauergroup.services.kiosk.enable = true;
# This module is parameter-agnostic; modules/features/kiosk.nix binds it to
# bauergroup.params.kiosk.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.bauergroup.services.kiosk;
  inherit (cfg) browser;

  wlr-randr = "${pkgs.wlr-randr}/bin/wlr-randr";
  isBrowser = cfg.mode == "browser";

  # wl_output transforms rotate counter-clockwise, so xrandr's "left" is 90.
  # cage dropped its own -r flag in 0.1.5 in favour of wlr-output-management,
  # and cage 0.3 exits on an unknown flag, so rotation must go through wlr-randr.
  transform = {
    left = "90";
    inverted = "180";
    right = "270";
  };

  rotates = cfg.rotation != "normal";

  # Membership in any of these makes the session account root-equivalent, which
  # would defeat running the payload under its own user
  inherit (cfg) privilegedGroups;

  chromiumFlags = [
    "--ozone-platform=wayland"
    "--kiosk"
    "--no-first-run"
    "--disable-infobars"
    "--disable-session-crashed-bubble"
    "--disable-translate"
    "--noerrdialogs"
    "--disable-features=TranslateUI"
    # Chromium checks for updates it can never apply — the Nix store is read-only
    "--check-for-update-interval=31536000"
    # Without a keyring on a headless kiosk, the default password store blocks
    # startup waiting for a prompt nobody can answer
    "--password-store=basic"
    # Signage and dashboards play media with no one to click first
    "--autoplay-policy=no-user-gesture-required"
  ]
  ++ lib.optionals cfg.touchscreen [
    "--touch-events=enabled"
    # A pinch or an edge swipe on an HMI is a misfire, not navigation
    "--disable-pinch"
    "--overscroll-history-navigation=0"
  ]
  ++ lib.optional (
    browser.remoteDebuggingPort != null
  ) "--remote-debugging-port=${toString browser.remoteDebuggingPort}"
  ++ browser.extraFlags;

  launchCommand =
    if isBrowser then
      "${pkgs.chromium}/bin/chromium ${lib.concatStringsSep " " chromiumFlags} ${lib.escapeShellArg browser.url}"
    else
      cfg.application.command;

  # Runs inside cage, which sets WAYLAND_DISPLAY and DISPLAY for its children
  sessionScript = pkgs.writeShellScript "kiosk-session" ''
    set -u

    ${lib.optionalString (cfg.startupProbe != null) ''
      # Wait for what the payload depends on, but give up after about a minute:
      # the UI showing its own connection error beats an indefinite black screen
      for _ in $(seq 1 30); do
        ${cfg.startupProbe} > /dev/null 2>&1 && break
        sleep 2
      done
    ''}

    ${lib.optionalString rotates ''
      rotate() {
        # Output names are the first word of wlr-randr's non-indented lines
        for output in $(${wlr-randr} | ${pkgs.gnugrep}/bin/grep -v '^ ' | ${pkgs.coreutils}/bin/cut -d' ' -f1); do
          ${wlr-randr} --output "$output" --transform ${transform.${cfg.rotation}} \
            || echo "kiosk: could not rotate $output" >&2
        done
      }
    ''}

    app=
    ${lib.optionalString (cfg.idleTimeout != null) ''
      # swayidle sends USR1 once per idle period; killing the payload makes the
      # loop below relaunch it in its initial state. Video playback inhibits idle.
      trap '[ -n "$app" ] && kill "$app" 2>/dev/null' USR1
      ${pkgs.swayidle}/bin/swayidle timeout ${toString cfg.idleTimeout} "kill -USR1 $$" &
      idle=$!
      # cage exits only when every child is gone, so never leave swayidle behind
      trap 'kill "$idle" 2>/dev/null' EXIT
    ''}

    # The payload runs in the background so the idle trap can fire while we
    # wait, and a crashed or closed payload comes back instead of leaving a
    # dark screen in front of an operator
    while true; do
      ${lib.optionalString rotates "rotate"}
      ${launchCommand} &
      app=$!
      # Poll instead of a blocking wait: the idle trap interrupts the sleep, and
      # cage re-creates a re-plugged display with transform normal
      while kill -0 "$app" 2>/dev/null; do
        ${lib.optionalString rotates ''
          ${wlr-randr} | ${pkgs.gnugrep}/bin/grep -qx '  Transform: normal' && rotate
        ''}
        sleep 5 &
        wait $!
      done
      app=
      sleep 2
    done
  '';
in
{
  options.bauergroup.services.kiosk = {
    enable = lib.mkEnableOption "single-application kiosk session on cage";

    user = lib.mkOption {
      type = lib.types.str;
      default = "kiosk";
      description = ''
        Unprivileged account that runs the session. It must not be the admin
        account and must not be in the container socket group: a compromised
        page or HMI would otherwise reach SSH keys, sudo or a root-equivalent
        container socket.
      '';
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional groups for the session account, beyond the video and render
        groups it always gets. An HMI that talks to a PLC over a serial adapter
        needs "dialout"; one that reads a USB device needs "plugdev".

        Never add the container socket group here: it is root-equivalent, and
        the point of a separate session account is that a compromised interface
        gains nothing.
      '';
      example = [ "dialout" ];
    };

    privilegedGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "wheel"
        "docker"
        "podman"
      ];
      description = ''
        Groups the session account is refused. Each grants a path to root —
        sudo, or a container socket that can bind-mount any host path into a
        privileged container — so membership would make separating the session
        from the admin account pointless.

        Extend this rather than replacing it when a site renames its container
        socket group; modules/features/kiosk.nix already adds whatever
        bauergroup.services.containers.socketGroup is set to.
      '';
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "browser"
        "application"
      ];
      default = "browser";
      description = ''
        What fills the screen. "browser" runs Chromium against browser.url;
        "application" runs application.command, which may be a native binary
        or a container invocation.
      '';
    };

    browser = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:3000";
        description = "URL to display (mode = \"browser\").";
      };

      remoteDebuggingPort = lib.mkOption {
        type = lib.types.nullOr lib.types.port;
        default = null;
        description = ''
          Bind Chromium's DevTools endpoint to this port on loopback, which
          gives the watchdog something to probe: the endpoint stops answering
          when the browser process wedges, which is the freeze that leaves a
          still image on screen while systemd stays healthy.

          The endpoint is bound to loopback, but it is not authenticated, and
          it does more than report health: anything that can reach it can run
          JavaScript in the page, navigate the kiosk and read what is on
          screen. "Loopback" therefore means every local process, not only
          this watchdog — a lower bar than the separate session account the
          rest of this module sets up.

          That is usually an acceptable trade for catching a frozen browser on
          a single-purpose appliance. Where it is not, set a
          healthCheckCommand of your own instead and leave this null: the
          watchdog then probes whatever the interface itself exposes and no
          debug port is opened.
        '';
        example = 9222;
      };

      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional Chromium command-line flags.";
        example = [ "--force-device-scale-factor=1.5" ];
      };
    };

    application = {
      command = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = ''
          Command line to run fullscreen (mode = "application"). Use absolute
          paths: it runs from a systemd unit, not a login shell.

          cage forces the first window fullscreen, so the application does not
          need to request it. A .NET/Avalonia binary works over XWayland
          without changes; see docs/kiosk.md for packaging notes.
        '';
        example = "/opt/hmi/BauerGroup.Hmi";
      };

      environment = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = { };
        description = ''
          Extra environment for the session. .NET usually needs a globalization
          setting here unless the app ships ICU itself.
        '';
        example = {
          DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1";
        };
      };

      foreignBinaries = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Run a binary that was not built for NixOS — the output of a
          `dotnet publish`, or an HMI delivered by a supplier.

          Such a binary is linked against /lib64/ld-linux-x86-64.so.2, a path
          that does not exist here, so it fails with "No such file or
          directory" even though the file is plainly present. This provides
          that loader and the libraries an Avalonia or Qt application expects.

          Not needed when the application is packaged as a Nix derivation or
          run inside a container, both of which bring their own libraries.
        '';
      };

      extraLibraries = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = ''
          Further libraries for foreignBinaries, for an application that loads
          something beyond the .NET and Avalonia baseline. Find the missing
          name with `ldd` on the binary.
        '';
        example = lib.literalExpression "[ pkgs.alsa-lib ]";
      };
    };

    startupProbe = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Command retried for about a minute before the payload starts, to avoid
        showing a connection error while a backend is still coming up. Null
        starts the payload immediately.
      '';
      example = "curl -sf --max-time 5 http://localhost:3000";
    };

    touchscreen = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Tune the session for touch input (no pinch zoom, no edge-swipe navigation).";
    };

    rotation = lib.mkOption {
      type = lib.types.enum [
        "normal"
        "left"
        "right"
        "inverted"
      ];
      default = "normal";
      description = ''
        Screen rotation, as in xrandr: "left" rotates the picture
        counter-clockwise, "right" clockwise (both give portrait on a landscape
        panel). Touch input is rotated to match when touchscreen is set.
      '';
    };

    multiMonitor = lib.mkOption {
      type = lib.types.enum [
        "last"
        "extend"
      ];
      default = "last";
      description = ''
        With several outputs connected, "last" shows the payload on the most
        recently connected monitor and is the safe default for a panel that may
        be joined by a service laptop's display; "extend" spans all outputs.
      '';
    };

    allowVtSwitch = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Allow Ctrl+Alt+F<n> to leave the session for a text console. Off by
        default: on a machine in a public area or on a production line, that
        key combination is an unauthenticated path to a login prompt. Turn it
        on temporarily when commissioning hardware.
      '';
    };

    idleTimeout = lib.mkOption {
      type = lib.types.nullOr lib.types.ints.positive;
      default = null;
      description = ''
        Seconds without touch, mouse or keyboard input before the payload is
        relaunched in its initial state. Null disables it. Useful where a
        visitor may leave a form half-filled; pointless for an HMI that must
        hold its state.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.mode != "application" || cfg.application.command != "";
        message = ''
          kiosk mode = "application" needs a command to run fullscreen — the HMI
          binary, for example "/opt/hmi/BauerGroup.Hmi". Templates take it from
          bauergroup.params.kiosk.application.command in /etc/nixos/params.nix.
        '';
      }
      {
        assertion = lib.intersectLists cfg.extraGroups privilegedGroups == [ ];
        message = ''
          kiosk.extraGroups may not contain ${lib.concatStringsSep ", " privilegedGroups}.
          A container socket can bind-mount any host path into a privileged
          container, and wheel is sudo — either makes the session account
          effectively root, and separating it from the admin account then buys
          nothing. Grant the specific device group instead (dialout, plugdev).
        '';
      }
    ];

    # cage opens its own PAM session for the kiosk user, so no console
    # auto-login is needed and every other TTY keeps its login prompt
    services.cage = {
      enable = true;
      inherit (cfg) user;
      program = sessionScript;
      extraArguments = [
        "-m"
        cfg.multiMonitor
      ]
      ++ lib.optional cfg.allowVtSwitch "-s";
      environment = cfg.application.environment;
    };

    # The payload runs as its own account: a compromised page or HMI must not
    # reach the admin's SSH keys, sudo or the container socket (root-equivalent)
    users.users.${cfg.user} = {
      isNormalUser = true;
      # mkDefault so a template that also describes this account, or an
      # overlapping admin name, surfaces as its own assertion instead of a
      # conflicting-definition error
      description = lib.mkDefault "Kiosk session";
      # Direct rendering and hardware video decode; logind grants input and DRM
      # master through the seat, so no input group is needed
      extraGroups = [
        "video"
        "render"
      ]
      ++ cfg.extraGroups;
    };

    # Without a display manager, getty.target wants autovt@tty1. Every switch
    # starts all active targets, and that start would stop cage-tty1 through its
    # Conflicts= (a job-requested stop that Restart= does not undo). Masking
    # both names keeps tty1 for cage, as nixpkgs does for display managers.
    systemd.services."getty@tty1".enable = false;
    systemd.services."autovt@tty1".enable = false;

    # wlroots does not map touchscreens to an output, so the wlr-randr transform
    # never reaches touch input; rotate it in libinput with the same matrix
    services.udev.extraRules = lib.mkIf (cfg.touchscreen && rotates) ''
      ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="${
        {
          left = "0 -1 1 1 0 0";
          inverted = "-1 0 1 0 -1 1";
          right = "0 1 0 -1 0 1";
        }
        .${cfg.rotation}
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

    environment.systemPackages = [
      pkgs.wlr-randr
    ]
    ++ lib.optional isBrowser pkgs.chromium;

    # Chromium ships unfree codecs; an HMI is useless without fonts
    nixpkgs.config.allowUnfree = true;
    fonts.enableDefaultPackages = true;

    # The dynamic loader and runtime libraries a non-Nix binary expects.
    # The list is the .NET and Avalonia baseline: ICU and OpenSSL for the
    # runtime, the X11 client libraries Avalonia draws through under XWayland,
    # fontconfig and freetype for text, libGL for accelerated rendering.
    programs.nix-ld = lib.mkIf (cfg.mode == "application" && cfg.application.foreignBinaries) {
      enable = true;
      libraries =
        (with pkgs; [
          stdenv.cc.cc.lib
          icu
          openssl
          zlib
          krb5
          fontconfig
          freetype
          libGL
          libxkbcommon

          # X11 client libraries, under their top-level names: the xorg.*
          # package set is deprecated in this nixpkgs
          libx11
          libxcursor
          libxi
          libxrandr
          libxext
          libxrender
          libsm
          libice
        ])
        ++ cfg.application.extraLibraries;
    };

    # The screen must never blank or suspend, and the power button on an
    # exposed machine must not shut it down
    services.logind.settings.Login = {
      HandleLidSwitch = "ignore";
      HandlePowerKey = "ignore";
      IdleAction = "ignore";
    };
  };
}
