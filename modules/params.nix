# modules/params.nix
# ─────────────────────────────────────────────────────────────────────
# Defines all parameters that customize a template for a specific machine.
# Each target machine provides values via /etc/nixos/params.nix
#
# Usage on target machine:
#   Create /etc/nixos/params.nix with your values, then:
#   nixos-rebuild switch --flake .#server --impure
#
# See params.example.nix in the repo root for a full reference.
# ─────────────────────────────────────────────────────────────────────
{ lib, ... }:
{
  options.bauergroup.params = {
    # ── Identity ──────────────────────────────────────────────────────
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for this machine.";
      example = "kiosk-lobby-01";
    };

    # ── User ──────────────────────────────────────────────────────────
    user = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Primary user account name.";
      };

      fullName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Full name for display and git config.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Email address for git config.";
      };

      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys for authorized login. At least one of sshKeys or hashedPassword is required.";
        example = [ "ssh-ed25519 AAAAC3Nza... user@host" ];
      };

      hashedPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Hashed password (mkpasswd -m sha-512). If null, only SSH key login works, so sshKeys must not be empty.";
      };

      extraGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional groups beyond the template defaults.";
      };
    };

    # ── Network ───────────────────────────────────────────────────────
    network = {
      useDHCP = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use DHCP for network configuration. Set to false for static IP.";
      };

      interface = lib.mkOption {
        type = lib.types.str;
        default = "eth0";
        description = "Primary network interface (only used with static IP).";
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static IPv4 address (only used when useDHCP = false).";
        example = "10.0.0.5";
      };

      prefixLength = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Network prefix length (subnet mask).";
      };

      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default gateway (only used when useDHCP = false).";
        example = "10.0.0.1";
      };

      nameservers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "1.1.1.1"
          "8.8.8.8"
        ];
        description = "DNS servers.";
      };

      openPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Additional TCP ports to open in the firewall.";
        example = [
          80
          443
        ];
      };
    };

    # ── Boot ──────────────────────────────────────────────────────────
    boot = {
      loader = lib.mkOption {
        type = lib.types.enum [
          "systemd-boot"
          "grub"
        ];
        default = "systemd-boot";
        description = "Boot loader to use. systemd-boot for EFI, grub for BIOS/legacy.";
      };

      grubDevice = lib.mkOption {
        type = lib.types.str;
        default = "/dev/sda";
        description = "Disk device for GRUB installation (only used with grub loader).";
      };
    };

    # ── Locale ────────────────────────────────────────────────────────
    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Berlin";
      description = "System timezone.";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      description = "System locale.";
    };

    keymap = lib.mkOption {
      type = lib.types.str;
      default = "de-latin1";
      description = "Console keyboard layout.";
    };

    xkbLayout = lib.mkOption {
      type = lib.types.str;
      default = "de";
      description = "X11/Wayland keyboard layout.";
    };

    # ── Kiosk-specific ────────────────────────────────────────────────
    kiosk = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "browser"
          "application"
        ];
        default = "browser";
        description = ''
          What fills the screen.

          "browser" runs Chromium against kiosk.url, natively on Wayland.
          "application" runs kiosk.application.command — a native HMI such as a
          .NET/Avalonia binary, which reaches the screen through the XWayland
          server that the compositor provides.
        '';
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:3000";
        description = "URL to display (kiosk.mode = \"browser\").";
      };

      extraFlags = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional Chromium flags (kiosk.mode = \"browser\").";
        example = [ "--force-device-scale-factor=1.5" ];
      };

      application = {
        command = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = ''
            Command line to run fullscreen (kiosk.mode = "application"). Use
            absolute paths — it runs from a systemd unit, not a login shell.

            The command may be a binary deployed to /opt, a Nix package, or a
            container invocation; see docs/kiosk.md for the trade-offs.
          '';
          example = "/opt/hmi/BauerGroup.Hmi";
        };

        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = ''
            Extra environment for the session. A .NET app that does not ship
            ICU needs its globalization mode set here.
          '';
          example = {
            DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1";
          };
        };

        foreignBinaries = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Set this when the command is a binary that was not built for NixOS
            — the output of a `dotnet publish`, or an HMI from a supplier.

            Such a binary is linked against /lib64/ld-linux-x86-64.so.2, which
            does not exist on NixOS, and fails with "No such file or directory"
            even though the file is plainly there. This provides that loader
            plus the libraries a .NET/Avalonia application expects.

            Leave off when the application is packaged as a Nix derivation or
            runs inside a container: both bring their own libraries.
          '';
        };

        extraLibraries = lib.mkOption {
          type = lib.types.listOf lib.types.package;
          default = [ ];
          description = ''
            Further libraries for foreignBinaries, for an application that
            needs something beyond the .NET and Avalonia baseline. Find the
            missing name with `ldd` on the binary.
          '';
          example = lib.literalExpression "with pkgs; [ alsa-lib ]";
        };
      };

      watchdog = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Restart the session when the interface stops responding, escalating
          to a reboot if restarting repeatedly fails to help.

          A frozen interface keeps its process alive and keeps systemd healthy,
          so neither the hardware watchdog nor the session's own restart-on-exit
          notices it. Only an explicit probe does.

          With kiosk.mode = "browser" the probe is Chromium's DevTools endpoint
          on loopback, configured automatically. With "application" there is
          nothing generic to probe, so set kiosk.healthCheckCommand as well —
          without it this option has no effect and the build warns.
        '';
      };

      healthCheckCommand = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Command that exits 0 while the interface is healthy, overriding the
          default probe. Runs as root on a timer, so give it a timeout and use
          absolute paths.
        '';
        example = "/run/current-system/sw/bin/curl -sf --max-time 5 http://127.0.0.1:8080/healthz";
      };

      startupGrace = lib.mkOption {
        type = lib.types.ints.positive;
        default = 120;
        description = ''
          Seconds after the session starts during which failed health probes
          are ignored, counted per start rather than from boot so a restart
          gets the same grace.

          The session waits up to a minute for its backend before launching
          anything, and the interface then needs time to appear, so the first
          probes after every start fail legitimately. Without this the watchdog
          would restart a session that is merely starting, and three such
          rounds escalate to a reboot that repeats after every boot.

          Raise it where the backend is slow — a large Compose project on eMMC.
        '';
      };

      startupProbe = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Command retried for about a minute before the interface starts, so a
          backend that is still coming up after a cold boot is not greeted with
          a connection error on screen.

          In "browser" mode this defaults to reaching kiosk.url. In
          "application" mode there is no default — set it when the HMI has a
          backend it cannot usefully start without.
        '';
        example = "/run/current-system/sw/bin/curl -sf --max-time 5 http://localhost:8080/ready";
      };

      multiMonitor = lib.mkOption {
        type = lib.types.enum [
          "last"
          "extend"
        ];
        default = "last";
        description = ''
          Behaviour with several outputs connected. "last" uses the most
          recently connected monitor, which keeps the interface on the panel
          when a service laptop's display is plugged in; "extend" spans all of
          them.
        '';
      };

      allowVtSwitch = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Allow Ctrl+Alt+F<n> to leave the session for a text console. Off by
          default: on a machine in a public area or on a production line, that
          is an unauthenticated path to a login prompt. Turn on temporarily
          while commissioning hardware.
        '';
      };

      user = lib.mkOption {
        type = lib.types.str;
        default = "kiosk";
        description = ''
          Unprivileged account that runs the kiosk browser session. It has no password,
          no sudo and no Docker access, and must differ from user.name.
        '';
      };

      composeFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to docker-compose.yml for kiosk backend services.";
      };

      composeDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/opt/kiosk";
        description = "Working directory for the Compose backend.";
      };

      touchscreen = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable touchscreen support for kiosk.";
      };

      extraGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Additional groups for the kiosk session account, beyond the video and
          render groups it always gets. An HMI that talks to a PLC over a serial
          adapter needs "dialout"; one that reads a USB device needs "plugdev".

          The build rejects "wheel", "docker" and "podman" here: each makes the
          session account effectively root, which defeats running the interface
          under its own user.
        '';
        example = [ "dialout" ];
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
          Screen rotation for kiosk display, as in xrandr: "left" rotates the picture
          counter-clockwise, "right" clockwise (both give portrait on a landscape panel).
        '';
      };

      idleTimeout = lib.mkOption {
        type = lib.types.nullOr lib.types.ints.positive;
        default = null;
        description = "Seconds without touch, mouse or keyboard input before the browser restarts at the home URL. Null = disabled.";
      };
    };

    # ── Container engine ──────────────────────────────────────────────
    containers = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Install a container engine. Turn off on machines that run no
          containers — an embedded HMI with a native application and little
          flash has no use for one.
        '';
      };

      engine = lib.mkOption {
        type = lib.types.enum [
          "docker"
          "podman"
        ];
        default = "docker";
        description = ''
          Container engine for this machine. Both serve the Docker API at
          /run/docker.sock, so every Compose project in this repo runs on
          either without changes.

          "docker" runs a persistent root daemon and is the fleet default.
          "podman" is daemonless: each container is an ordinary systemd-managed
          process, so no single daemon's crash takes them all down.

          Switching re-creates containers and does not migrate named volumes.
          Back up data volumes before changing this on a running machine.
        '';
      };
    };

    # ── Watchdog ──────────────────────────────────────────────────────
    watchdog = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Let the hardware watchdog reset the machine when systemd stops
          responding — a kernel lockup, a storage stall, an out-of-memory
          spiral. This is the only recovery layer that survives a dead kernel.

          Harmless where no watchdog hardware exists: systemd notes the missing
          device and carries on. See watchdog.useSoftdog for those machines.
        '';
      };

      runtimeTime = lib.mkOption {
        type = lib.types.str;
        default = "60s";
        description = ''
          Watchdog timeout while running. Do not go below about 30s on machines
          that do heavy I/O: a long fsync storm can stall systemd briefly, and a
          short timeout turns that into a spurious reset.
        '';
      };

      rebootTime = lib.mkOption {
        type = lib.types.str;
        default = "3min";
        description = ''
          Watchdog timeout during shutdown and reboot. Bounds how long a hung
          unit can block a reboot — the difference between a machine that comes
          back on its own and one that needs a site visit.
        '';
      };

      kernelModules = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          Watchdog drivers to load explicitly. Desktop boards are usually
          matched automatically; industrial and embedded boards often are not,
          and then /dev/watchdog never appears at all.

          Common: "iTCO_wdt" (Intel PCH), "sp5100_tco" (AMD), "it87_wdt" and
          "w83627hf_wdt" (Super-I/O on industrial boards). Verify with `wdctl`
          after boot — a driver that does not match the hardware simply fails
          to load.
        '';
        example = [ "iTCO_wdt" ];
      };

      useSoftdog = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Load softdog, a watchdog implemented by the kernel itself, for
          virtual machines and boards with no watchdog hardware.

          It recovers a hung userspace but not a hung kernel, because the timer
          that would fire the reset is part of what has stopped. Treat it as a
          weaker guarantee, not an equivalent one, and leave it off where real
          watchdog hardware exists: whichever driver registers first becomes
          /dev/watchdog, and that race is not worth losing.
        '';
      };
    };

    # ── Branding ──────────────────────────────────────────────────────
    branding = {
      enable = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = ''
          Show the BAUER GROUP boot splash instead of kernel messages. Null
          follows the template default: on for kiosk and HMI machines, which
          are looked at while they start, off for servers and developer
          desktops, where the messages are worth having.
        '';
      };

      silentBoot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Quieten the kernel and initrd so the splash is not overdrawn by log
          output. Turn off while commissioning hardware, when the messages the
          splash hides are exactly the ones worth reading. Errors still reach
          the journal either way.
        '';
      };
    };

    # ── Server-specific ───────────────────────────────────────────────
    server = {
      composeProjects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              directory = lib.mkOption {
                type = lib.types.str;
                description = "Directory containing docker-compose.yml.";
              };
              envFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to .env file (e.g. from agenix).";
              };
            };
          }
        );
        default = { };
        description = "Docker Compose projects to run as systemd services.";
        example = {
          outline = {
            directory = "/opt/outline";
          };
          traefik = {
            directory = "/opt/traefik";
          };
        };
      };

      monitoring = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prometheus node exporter for monitoring.";
      };

      backup = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable automated restic backups.";
        };

        repository = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Restic repository URL.";
          example = "sftp:backup@storage:/backups/hostname";
        };

        passwordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to restic repository password file.";
        };

        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          # /etc/nixos holds params.nix and hardware-configuration.nix, the only
          # machine-specific files needed to rebuild this host
          default = [
            "/opt"
            "/var/lib"
            "/home"
            "/etc/nixos"
          ];
          description = "Paths to back up.";
        };
      };
    };

    # ── Auto-Update ────────────────────────────────────────────────────
    autoUpdate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically pull latest config from Git and rebuild daily.";
      };

      flake = lib.mkOption {
        type = lib.types.str;
        default = "github:bauer-group/IAC-NixOS";
        description = "Flake URI to pull updates from. Without #attribute, the template name is appended.";
      };

      template = lib.mkOption {
        type = lib.types.str;
        internal = true;
        description = "nixosConfigurations attribute of this machine's template. Set by flake.nix.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Time to check for updates (24h format).";
      };

      allowReboot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow automatic reboot when kernel or critical services change.";
      };

      rebootWindowStart = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Earliest time for automatic reboot.";
      };

      rebootWindowEnd = lib.mkOption {
        type = lib.types.str;
        default = "03:30";
        description = "Latest time for automatic reboot.";
      };
    };

    # ── Development-specific ──────────────────────────────────────────
    dev = {
      embeddedDev = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable CAN-Bus / embedded development tools and kernel modules.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Additional packages to install on development desktop.";
      };
    };
  };
}
