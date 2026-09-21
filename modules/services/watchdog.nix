# modules/services/watchdog.nix
# ─────────────────────────────────────────────────────────────────────
# Two watchdogs, for two different kinds of freeze.
#
#   hardware — systemd pings /dev/watchdog. If systemd itself stops running
#              (kernel lockup, storage stall, OOM storm), the chip resets the
#              board with no software involvement. This is the only layer that
#              survives a dead kernel.
#
#   application — a timer probes whether the UI is still doing its job. A
#              frozen Chromium showing a still image keeps its process alive
#              and keeps systemd healthy, so the hardware watchdog never fires
#              and Restart=always never triggers. Nothing but an explicit probe
#              catches that case.
#
# The application layer escalates: restart the unit first, reboot only if
# restarting has repeatedly failed to help. Rebooting on the first failed
# probe turns one flaky check into a boot loop.
#
# Enable via: bauergroup.services.watchdog.enable = true;
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.bauergroup.services.watchdog;
  app = cfg.application;

  stateDir = "/run/bauergroup-watchdog";

  # /run is a tmpfs, so every counter starts clean after a reboot — a reboot
  # that did fix things must not count towards the next escalation
  probeScript = pkgs.writeShellScript "kiosk-watchdog-probe" ''
    set -u
    # Prepended, not replaced: a healthCheckCommand may name tools from
    # environment.systemPackages, which systemd's default PATH already covers
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.systemd
        pkgs.gawk
      ]
    }:$PATH

    failures=${stateDir}/failures
    restarts=${stateDir}/restarts
    mkdir -p ${stateDir}

    # A unit that is not running is not this watchdog's problem: Restart= brings
    # a crashed session back. This exists for the opposite case — running, but
    # no longer responding.
    if ! systemctl is-active --quiet ${app.unit}; then
      rm -f "$failures"
      exit 0
    fi

    # Do not hold a starting session against itself. The kiosk session waits for
    # its backend before it launches anything, and the payload then needs time
    # to come up, so the first probes after every start legitimately fail.
    # Measured from the unit's own start, not from boot, so a restart gets the
    # same grace — otherwise a slow backend turns restart into reboot into a
    # boot loop, with the watchdog bricking the machine it exists to protect.
    uptime_us=$(awk '{printf "%d", $1 * 1000000}' /proc/uptime)
    active_us=$(systemctl show ${app.unit} -p ActiveEnterTimestampMonotonic --value 2>/dev/null || echo 0)
    case "$active_us" in
      "" | *[!0-9]*) active_us=0 ;;
    esac
    if [ "$active_us" -eq 0 ] || [ $(( (uptime_us - active_us) / 1000000 )) -lt ${toString app.startupGrace} ]; then
      rm -f "$failures"
      exit 0
    fi

    if ${app.healthCheckCommand}; then
      rm -f "$failures"
      exit 0
    fi

    count=$(( $(cat "$failures" 2>/dev/null || echo 0) + 1 ))
    echo "$count" > "$failures"
    echo "watchdog: health check failed ($count/${toString app.failuresBeforeRestart})" >&2

    [ "$count" -lt ${toString app.failuresBeforeRestart} ] && exit 0

    # Escalating now, so the failure streak restarts from zero either way
    rm -f "$failures"

    now=$(date +%s)
    window_start=$(( now - ${toString app.restartWindow} ))
    # Keep only restarts inside the window, then record this one. On any awk
    # failure keep the old file rather than the half-written replacement:
    # under-counting delays a reboot, losing the file would prevent it.
    if [ -f "$restarts" ] && awk -v s="$window_start" '$1 > s' "$restarts" > "$restarts.new"; then
      mv "$restarts.new" "$restarts"
    else
      rm -f "$restarts.new"
    fi
    echo "$now" >> "$restarts"

    recent=$(wc -l < "$restarts")
    if [ "$recent" -ge ${toString app.restartsBeforeReboot} ]; then
      echo "watchdog: ${app.unit} restarted $recent times in ${toString app.restartWindow}s, rebooting" >&2
      exec systemctl reboot
    fi

    echo "watchdog: restarting ${app.unit} (attempt $recent in window)" >&2
    exec systemctl restart ${app.unit}
  '';
in
{
  options.bauergroup.services.watchdog = {
    enable = lib.mkEnableOption "hardware watchdog supervision of systemd";

    runtimeTime = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = ''
        Hardware watchdog timeout while the system is running. systemd re-arms
        it at half this interval, so the board resets somewhere between one half
        and one times this value after systemd stops responding.

        Do not go below ~30s on machines that do heavy I/O: a long fsync storm
        can stall systemd briefly, and a short timeout turns that into a reset.
      '';
    };

    rebootTime = lib.mkOption {
      type = lib.types.str;
      default = "3min";
      description = ''
        Watchdog timeout during shutdown and reboot. Bounds how long a hung
        unit can block a reboot before the hardware forces it — the difference
        between a machine that comes back and one that needs a site visit.
      '';
    };

    device = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Watchdog device, or null for systemd's default (/dev/watchdog). Set
        explicitly when a board exposes several and the first is not the one
        wired to the reset line.
      '';
      example = "/dev/watchdog0";
    };

    kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Watchdog drivers to load explicitly. Most desktop boards are matched
        automatically over ACPI or PCI; industrial and embedded boards often
        are not, and then /dev/watchdog never appears.

        Common choices: "iTCO_wdt" (Intel PCH), "sp5100_tco" (AMD), "it87_wdt"
        and "w83627hf_wdt" (Super-I/O on industrial boards). Check with
        `wdctl` after boot — a module that does not match the hardware simply
        fails to load and is otherwise harmless.
      '';
      example = [ "iTCO_wdt" ];
    };

    useSoftdog = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Load the softdog driver, a watchdog implemented by the kernel itself.

        It recovers a hung userspace — systemd stopping its pings still triggers
        a reset — but it cannot recover a hung kernel, because the timer that
        would fire the reset is part of what has stopped. Use it on virtual
        machines and on boards with no watchdog hardware, and treat it as a
        weaker guarantee rather than an equivalent one.

        Leave off where real watchdog hardware exists: whichever driver
        registers first becomes /dev/watchdog, and that race is not worth
        losing.
      '';
    };

    application = {
      enable = lib.mkEnableOption "probing an application and restarting it when it stops responding";

      unit = lib.mkOption {
        type = lib.types.str;
        description = "systemd unit to restart when the health check fails.";
        example = "cage-tty1.service";
      };

      healthCheckCommand = lib.mkOption {
        type = lib.types.str;
        description = ''
          Shell command that exits 0 while the application is healthy. It runs
          as root on a timer, so it must terminate on its own — give every
          network probe a timeout.
        '';
        example = "curl -sf --max-time 5 http://127.0.0.1:9222/json/version";
      };

      interval = lib.mkOption {
        type = lib.types.str;
        default = "30s";
        description = "How often to run the health check (systemd time span).";
      };

      startupGrace = lib.mkOption {
        type = lib.types.ints.positive;
        default = 120;
        description = ''
          Seconds after the unit becomes active during which failed probes are
          ignored, measured per start rather than from boot.

          A kiosk session waits for its backend before launching anything and
          the payload then needs time to appear, so the first probes after
          every start fail legitimately. Without this grace a slow backend
          escalates restart into reboot into a boot loop, and the watchdog
          bricks the machine it exists to protect.

          Raise it where a backend is slow to come up — a large compose project
          on an embedded panel — and keep it above the startup budget plus the
          payload's own cold-start time.
        '';
      };

      failuresBeforeRestart = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = ''
          Consecutive failed probes before the unit is restarted. Above 1 so a
          single slow response — a garbage collection pause, a busy CPU — does
          not restart a healthy UI in front of a user.
        '';
      };

      restartsBeforeReboot = lib.mkOption {
        type = lib.types.ints.positive;
        default = 3;
        description = ''
          Restarts within restartWindow before the machine reboots instead.
          Reaching this means restarting the unit is not fixing the problem,
          so the fault is likely below the application — a wedged GPU driver,
          an exhausted resource — and only a reboot clears it.
        '';
      };

      restartWindow = lib.mkOption {
        type = lib.types.ints.positive;
        default = 600;
        description = ''
          Seconds over which restarts are counted towards restartsBeforeReboot.
          Restarts older than this are forgotten, so a machine that recovers
          and runs fine for hours does not reboot over unrelated history.
        '';
      };
    };
  };

  # The two layers are independent on purpose. A board with no watchdog
  # silicon still wants freeze detection, and turning off the hardware reset
  # must not silently take application monitoring with it.
  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # systemd.watchdog.* was renamed to systemd.settings.Manager.* upstream;
      # the old names still work but warn on every rebuild
      systemd.settings.Manager = {
        RuntimeWatchdogSec = cfg.runtimeTime;
        RebootWatchdogSec = cfg.rebootTime;
      }
      // lib.optionalAttrs (cfg.device != null) {
        WatchdogDevice = cfg.device;
      };

      boot.kernelModules = cfg.kernelModules ++ lib.optional cfg.useSoftdog "softdog";

      # wdctl reports which driver claimed the device and its real timeout,
      # which is the only way to confirm the chip is actually armed
      environment.systemPackages = [ pkgs.util-linux ];
    })

    (lib.mkIf app.enable {
      systemd.services.bauergroup-app-watchdog = {
        description = "Application health probe for ${app.unit}";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = probeScript;

          # Needs to restart units and reboot, so it stays privileged; limit
          # everything it does not need
          ProtectSystem = "strict";
          ProtectHome = true;
          PrivateTmp = true;
          ReadWritePaths = [ stateDir ];
          RestrictNamespaces = true;
          RestrictSUIDSGID = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
        };
      };

      systemd.timers.bauergroup-app-watchdog = {
        description = "Application health probe for ${app.unit}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          # Relative to finish, so a slow probe cannot queue up behind itself
          OnUnitInactiveSec = app.interval;
          OnBootSec = app.interval;
          AccuracySec = "1s";
        };
      };

      systemd.tmpfiles.rules = [ "d ${stateDir} 0700 root root -" ];
    })
  ];
}
