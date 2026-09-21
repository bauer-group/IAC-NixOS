# modules/services/containers.nix
# ─────────────────────────────────────────────────────────────────────
# Container engine with BAUER GROUP defaults — Docker or Podman.
# Enable via: bauergroup.services.containers.enable = true;
# Select via: bauergroup.services.containers.engine = "podman";
#
# Both engines expose the same Docker API socket at /run/docker.sock, so
# every compose unit in this repo runs unchanged on either. Templates must
# call cfg.composeCommand instead of hard-coding a compose binary.
#
# Docker is the default. Podman is the choice when a machine must not run
# a root daemon in the background, or when the fleet policy requires a
# daemonless engine.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  cfg = config.bauergroup.services.containers;
  isDocker = cfg.engine == "docker";
  isPodman = cfg.engine == "podman";

  renamed =
    old:
    lib.mkRenamedOptionModule
      [ "bauergroup" "services" "docker" old ]
      [ "bauergroup" "services" "containers" old ];
in
{
  # bauergroup.services.docker was the Docker-only predecessor of this module
  imports = map renamed [
    "enable"
    "enableOnBoot"
    "storageDriver"
    "logMaxSize"
    "logMaxFiles"
    "pruneSchedule"
    "pruneKeepHours"
  ];

  options.bauergroup.services.containers = {
    enable = lib.mkEnableOption "Container engine with BAUER GROUP defaults";

    engine = lib.mkOption {
      type = lib.types.enum [
        "docker"
        "podman"
      ];
      default = "docker";
      description = ''
        Container engine for this machine. Both provide a Docker API socket at
        /run/docker.sock, so compose projects work either way.

        "docker" runs a persistent root daemon and is the fleet default.
        "podman" is daemonless: containers are plain systemd-supervised processes,
        so there is no single daemon whose crash takes every container with it.

        The engines cannot coexist — they claim the same socket — so switching
        requires re-creating containers. Named volumes are not migrated.
      '';
    };

    enableOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Start the engine at boot rather than on first use. Set to false on
        developer desktops, where containers are started by hand.

        With engine = "podman" this controls whether the API socket is
        socket-activated at boot; containers with a restart policy come up
        through their own units regardless.
      '';
    };

    storageDriver = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Storage driver, or null to let the engine choose. Only honoured by
        Docker; Podman selects overlay with fuse-overlayfs on its own.
      '';
      example = "overlay2";
    };

    logMaxSize = lib.mkOption {
      type = lib.types.str;
      default = "10m";
      description = ''
        Maximum size of a container log file before rotation (Docker only).
        Podman logs to the journal, which journald rotates.
      '';
    };

    logMaxFiles = lib.mkOption {
      type = lib.types.str;
      default = "3";
      description = "Number of rotated log files to keep per container (Docker only).";
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

    socketGroup = lib.mkOption {
      type = lib.types.str;
      default = "docker";
      description = ''
        Group granted access to the container API socket. Membership is
        root-equivalent with either engine: the socket can bind-mount any host
        path into a privileged container. Kiosk accounts must stay out of it.
      '';
    };

    composeCommand = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = "${pkgs.docker-compose}/bin/docker-compose";
      description = ''
        Compose binary to invoke from systemd units, engine-independent.
        Compose v2 speaks the Docker API, which Podman also serves, so the same
        binary drives both. Read-only: set engine instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # ── Shared ────────────────────────────────────────────────────────
      {
        environment.systemPackages = [
          pkgs.docker-compose
          pkgs.lazydocker
        ];

        # Container networking requires IP forwarding
        boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

        # users.nix adds the primary account to "docker" unconditionally, and an
        # undefined group fails activation. Podman has no such group of its own.
        users.groups.${cfg.socketGroup} = { };

        # Keeps virtualisation.oci-containers.* in step with this module, so a
        # template that uses it does not silently pull in the other engine
        virtualisation.oci-containers.backend = cfg.engine;
      }

      # ── Docker ────────────────────────────────────────────────────────
      (lib.mkIf isDocker {
        virtualisation.docker = {
          enable = true;
          inherit (cfg) enableOnBoot;
          storageDriver = lib.mkIf (cfg.storageDriver != null) cfg.storageDriver;

          # Live restore: containers keep running during daemon restart
          liveRestore = true;

          daemon.settings = {
            "log-driver" = "json-file";
            "log-opts" = {
              "max-size" = cfg.logMaxSize;
              "max-file" = cfg.logMaxFiles;
            };
          };

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
      })

      # ── Podman ────────────────────────────────────────────────────────
      (lib.mkIf isPodman {
        virtualisation.podman = {
          enable = true;

          # "docker" on PATH plus /run/docker.sock, so compose units, lazydocker
          # and muscle memory all keep working
          dockerCompat = true;
          dockerSocket.enable = true;

          # netavark only resolves container names on the default network when
          # this is set; compose projects rely on service-name DNS
          defaultNetwork.settings.dns_enabled = true;

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

        # The podman module owns the socket by group "podman". Overriding it
        # keeps socketGroup meaning the same thing under either engine, so the
        # accounts that could reach Docker can reach Podman and no others.
        systemd.sockets.podman = {
          wantedBy = lib.mkIf (!cfg.enableOnBoot) (lib.mkForce [ ]);
          socketConfig = {
            SocketGroup = lib.mkForce cfg.socketGroup;
            SocketMode = lib.mkForce "0660";
          };
        };

        # podman-compose is not used (compose v2 drives the API socket), but the
        # podman CLI itself belongs on PATH for debugging
        environment.systemPackages = [ pkgs.podman-tui ];
      })
    ]
  );
}
