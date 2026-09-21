{
  description = "BAUER GROUP Infrastructure — Parametric NixOS Templates";

  inputs = {
    # Stable channel for production
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    # Unstable channel for latest kernel & bleeding-edge packages
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager for user-level config
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Deployment
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Declarative disk partitioning
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Secret management
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Code formatting
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Pre-commit hooks
    git-hooks-nix = {
      url = "github:cachix/git-hooks.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
      home-manager,
      disko,
      agenix,
      treefmt-nix,
      git-hooks-nix,
      ...
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        config.allowUnfree = true;
      };

      # ── Overlays ────────────────────────────────────────────────────
      overlays = import ./overlays { inherit nixpkgs-unstable; };
      unstableOverlay = overlays.unstable;

      specialArgs = { inherit inputs self; };

      # ── Base modules (shared by all templates) ──────────────────────
      baseModules = [
        { nixpkgs.overlays = [ unstableOverlay ]; }

        # Parameter definitions
        ./modules/params.nix

        # Home Manager
        home-manager.nixosModules.home-manager
        {
          home-manager.useGlobalPkgs = true;
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = specialArgs;
        }

        # Agenix + Disko
        agenix.nixosModules.default
        disko.nixosModules.disko
      ];

      # Machine-local params + hardware config (requires --impure)
      machineModules = [
        /etc/nixos/params.nix
      ]
      ++ (
        if builtins.pathExists /etc/nixos/hardware-configuration.nix then
          [ /etc/nixos/hardware-configuration.nix ]
        else
          [ ]
      );

      # ── Home Manager wiring ─────────────────────────────────────────
      # Dynamically sets home-manager.users.<name> from bauergroup.params.user
      homeManagerModule =
        { config, ... }:
        {
          home-manager.users.${config.bauergroup.params.user.name} = import ./home/user.nix;
        };

      # ── Template builder ────────────────────────────────────────────
      # name = nixosConfigurations attribute = templates/<name>.nix
      mkSystem =
        name: extraModules:
        nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules =
            baseModules
            ++ extraModules
            ++ [
              ./templates/${name}.nix
              homeManagerModule
              { bauergroup.params.autoUpdate.template = name; }
            ];
        };

      mkTemplate = name: mkSystem name machineModules;

      # ── Formatting ──────────────────────────────────────────────────
      treefmtEval = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      # ── Pre-commit hooks ────────────────────────────────────────────
      pre-commit-check = git-hooks-nix.lib.${system}.run {
        src = self;
        hooks = {
          nixfmt.enable = true;
          statix.enable = true;
          deadnix.enable = true;
          check-merge-conflicts.enable = true;
        };
      };

    in
    {
      # ── NixOS Templates ──────────────────────────────────────────────
      # Deploy with: nixos-rebuild switch --flake .#<template> --impure
      nixosConfigurations = {
        desktop-dev = mkTemplate "desktop-dev";
        desktop-kiosk = mkTemplate "desktop-kiosk";
        embedded-kiosk = mkTemplate "embedded-kiosk";
        server = mkTemplate "server";
      };

      # ── Overlays ────────────────────────────────────────────────────
      overlays.default = unstableOverlay;

      # ── Formatter ───────────────────────────────────────────────────
      formatter.${system} = treefmtEval.config.build.wrapper;

      # ── Checks ──────────────────────────────────────────────────────
      checks.${system} = {
        formatting = treefmtEval.config.build.check self;
        pre-commit = pre-commit-check;

        # NixOS VM tests (need KVM; CI enables it on the runner)
        firewall = import ./tests/firewall.nix { inherit pkgs; };
        ssh-hardening = import ./tests/ssh-hardening.nix { inherit pkgs; };
        container-engine = import ./tests/container-engine.nix { inherit pkgs; };
        # Example files are edited per machine and keep placeholder bindings
        lint =
          pkgs.runCommand "lint"
            {
              nativeBuildInputs = with pkgs; [
                deadnix
                statix
              ];
            }
            ''
              cd ${self}
              deadnix --fail . --exclude params.example.nix secrets/secrets.nix
              # statix exits 0 when it cannot read its config, so require the file
              test -f statix.toml
              statix check --config statix.toml .
              touch $out
            '';

        # Evaluates every template with fixed params instead of /etc/nixos
        template-eval =
          let
            evalTemplate =
              name:
              (mkSystem name [
                ./tests/eval-params.nix
                ./tests/eval-${name}.nix
              ]).config;

            # The drvPath forces every module, assertion and Home Manager config
            # without building anything; dropping the context avoids a build dependency
            evaluates = cfg: builtins.unsafeDiscardStringContext cfg.system.build.toplevel.drvPath != "";

            inherit (nixpkgs.lib) hasInfix;

            dev = evalTemplate "desktop-dev";
            kiosk = evalTemplate "desktop-kiosk";
            embedded = evalTemplate "embedded-kiosk";

            # A board with no watchdog silicon still wants freeze detection, so
            # turning off the hardware reset must not take the application
            # probe with it
            kioskNoHwWatchdog =
              (mkSystem "desktop-kiosk" [
                ./tests/eval-params.nix
                ./tests/eval-desktop-kiosk.nix
                { bauergroup.params.watchdog.enable = false; }
              ]).config;
            kioskSession = kiosk.services.cage.program.text;
            embeddedSession = embedded.services.cage.program.text;
            cage = kiosk.systemd.services.cage-tty1;
            homeOf = cfg: cfg.home-manager.users.admin;

            # Every template must arm the hardware watchdog, and must do it
            # through the option that is not deprecated
            watchdogOf = cfg: cfg.systemd.settings.Manager;
            containersOf = cfg: cfg.bauergroup.services.containers;
            appWatchdogOf = cfg: cfg.bauergroup.services.watchdog.application;

            config = evalTemplate "server";
            upgradeFlags = toString config.system.autoUpgrade.flags;
            composePreStart = config.systemd.services.compose-app.preStart;
            resticPasswordFile = config.services.restic.backups.system.passwordFile;
            grafana = config.systemd.services.grafana;
            grafanaSettings = config.services.grafana.settings;
            inherit (config.networking) firewall;
          in
          assert nixpkgs.lib.all evaluates [
            dev
            kiosk
            embedded
            config
          ];
          assert nixpkgs.lib.assertMsg (
            !builtins.elem "-r" kiosk.services.cage.extraArguments && hasInfix "--transform 90" kioskSession
          ) "kiosk rotation must use wlr-randr: cage 0.3 exits on -r";
          assert nixpkgs.lib.assertMsg (
            !builtins.elem "-s" kiosk.services.cage.extraArguments
            && !builtins.elem "-s" embedded.services.cage.extraArguments
          ) "kiosk must not allow VT switching: Ctrl+Alt+F2 would reach a login prompt";
          assert nixpkgs.lib.assertMsg (
            cage.serviceConfig.Restart == "always" && cage.restartIfChanged
          ) "kiosk session must restart after a crash and on config changes";
          assert nixpkgs.lib.assertMsg (
            !kiosk.systemd.services."getty@tty1".enable
            && !kiosk.systemd.services."autovt@tty1".enable
            && hasInfix ''LIBINPUT_CALIBRATION_MATRIX}="0 -1 1 1 0 0"'' kiosk.services.udev.extraRules
          ) "kiosk must keep tty1 for cage on switch and rotate touch input with the display";
          assert nixpkgs.lib.assertMsg (
            kiosk.services.cage.user == "kiosk"
            && kiosk.services.getty.autologinUser == null
            && !builtins.elem "wheel" kiosk.users.users.kiosk.extraGroups
          ) "kiosk browser must run as an unprivileged user without console auto-login";
          assert nixpkgs.lib.assertMsg (hasInfix "swayidle timeout 300 " kioskSession)
            "kiosk idleTimeout must reset the browser";
          assert nixpkgs.lib.assertMsg (nixpkgs.lib.all
            (
              groups:
              nixpkgs.lib.intersectLists groups [
                "wheel"
                "docker"
                "podman"
              ] == [ ]
            )
            [
              kiosk.users.users.kiosk.extraGroups
              embedded.users.users.kiosk.extraGroups
            ]
          ) "kiosk session account must not be root-equivalent through wheel or a container socket group";

          # ── Kiosk payloads ────────────────────────────────────────────
          assert nixpkgs.lib.assertMsg (
            hasInfix "--ozone-platform=wayland" kioskSession && hasInfix "--kiosk" kioskSession
          ) "browser kiosk must run Chromium natively on Wayland, not through XWayland";
          assert nixpkgs.lib.assertMsg (
            hasInfix "/opt/hmi/BauerGroup.Hmi" embeddedSession && !hasInfix "chromium" embeddedSession
          ) "application kiosk must launch the HMI binary and pull in no browser";
          assert nixpkgs.lib.assertMsg (
            embedded.services.cage.environment ? DOTNET_SYSTEM_GLOBALIZATION_INVARIANT
            && builtins.elem "dialout" embedded.users.users.kiosk.extraGroups
          ) "application kiosk must pass its environment and device groups to the session";
          assert nixpkgs.lib.assertMsg (
            embedded.programs.nix-ld.enable && !kiosk.programs.nix-ld.enable
          ) "a dotnet publish output needs the loader NixOS lacks; a browser kiosk does not";

          # ── Container engine ──────────────────────────────────────────
          assert nixpkgs.lib.assertMsg (
            (containersOf kiosk).engine == "docker" && kiosk.virtualisation.docker.enable
          ) "desktop-kiosk must default to the Docker engine";
          assert nixpkgs.lib.assertMsg (
            (containersOf embedded).engine == "podman"
            && embedded.virtualisation.podman.dockerCompat
            && embedded.virtualisation.podman.dockerSocket.enable
            && embedded.virtualisation.podman.defaultNetwork.settings.dns_enabled
            && !embedded.virtualisation.docker.enable
          ) "podman must serve the Docker socket with DNS and must not pull in a Docker daemon";
          assert nixpkgs.lib.assertMsg (
            (containersOf kiosk).composeCommand == (containersOf embedded).composeCommand
          ) "compose units must be engine-independent: both engines take the same compose binary";
          assert nixpkgs.lib.assertMsg (
            kiosk.systemd.services.kiosk-backend.requires == [ "docker.service" ]
            && embedded.systemd.services.kiosk-backend.requires == [ "podman.socket" ]
          ) "a compose backend must order behind whatever its engine actually provides";

          # ── Watchdog ──────────────────────────────────────────────────
          assert nixpkgs.lib.assertMsg (nixpkgs.lib.all (cfg: (watchdogOf cfg).RuntimeWatchdogSec != null) [
            dev
            kiosk
            embedded
            config
          ]) "every template must arm the hardware watchdog";
          assert nixpkgs.lib.assertMsg (
            (watchdogOf dev).RuntimeWatchdogSec == "5min"
          ) "desktop-dev needs a long watchdog timeout: a heavy build must not trigger a reset";
          assert nixpkgs.lib.assertMsg (
            (appWatchdogOf kiosk).enable
            && (appWatchdogOf kiosk).unit == "cage-tty1.service"
            && hasInfix "9222/json/version" (appWatchdogOf kiosk).healthCheckCommand
            && hasInfix "--remote-debugging-port=9222" kioskSession
          ) "browser kiosk must probe the DevTools endpoint it actually opens";
          # The unit itself, not just the option: the probe once lived inside
          # the hardware watchdog's mkIf and silently vanished without it
          assert nixpkgs.lib.assertMsg (
            kiosk.systemd.timers ? bauergroup-app-watchdog
            && kioskNoHwWatchdog.systemd.timers ? bauergroup-app-watchdog
            && !(kioskNoHwWatchdog.systemd.settings.Manager ? RuntimeWatchdogSec)
          ) "freeze detection must not depend on the hardware watchdog being enabled";
          # Without a grace period the session's own backend wait fails the
          # first probes, and restart escalates to reboot to a boot loop
          assert nixpkgs.lib.assertMsg (
            (appWatchdogOf kiosk).startupGrace > 60
          ) "the probe must ignore failures while the session is still starting";
          assert nixpkgs.lib.assertMsg (
            (appWatchdogOf embedded).enable
            && hasInfix "8080/healthz" (appWatchdogOf embedded).healthCheckCommand
            && !hasInfix "--remote-debugging-port" embeddedSession
          ) "application kiosk must use its own probe and open no browser debug port";
          assert nixpkgs.lib.assertMsg (builtins.elem "iTCO_wdt" embedded.boot.kernelModules)
            "embedded-kiosk must load the watchdog driver named in params";

          # ── Boot splash ───────────────────────────────────────────────
          assert nixpkgs.lib.assertMsg (
            kiosk.boot.plymouth.enable
            && kiosk.boot.plymouth.theme == "bauergroup"
            && embedded.boot.plymouth.enable
            && !config.boot.plymouth.enable
            && !dev.boot.plymouth.enable
          ) "the boot splash belongs on kiosk machines, not on servers or developer desktops";
          assert nixpkgs.lib.assertMsg (
            builtins.elem "quiet" kiosk.boot.kernelParams && builtins.elem "splash" kiosk.boot.kernelParams
          ) "a branded splash must not be overdrawn by kernel log output";

          # ── Embedded update policy ────────────────────────────────────
          assert nixpkgs.lib.assertMsg (
            !embedded.bauergroup.params.autoUpdate.allowReboot
            && embedded.system.autoUpgrade.enable
            && kiosk.bauergroup.params.autoUpdate.allowReboot
          ) "an HMI on a production line must update without rebooting itself";
          assert nixpkgs.lib.assertMsg (
            (homeOf dev).programs.kitty.enable
            && !(homeOf config).programs.kitty.enable
            && (homeOf dev).programs.zsh.shellAliases ? candump0
            && !((homeOf config).programs.zsh.shellAliases ? candump0)
            &&
              (homeOf config).programs.zsh.shellAliases.nrs
              == "sudo nixos-rebuild switch --flake .#server --impure"
          ) "Home Manager must only ship desktop and CAN tooling where it applies";
          assert nixpkgs.lib.assertMsg
            (nixpkgs.lib.hasInfix "--flake github:bauer-group/IAC-NixOS#server" upgradeFlags)
            "auto-update must target #server, got: ${upgradeFlags}";
          assert nixpkgs.lib.assertMsg (nixpkgs.lib.hasInfix "cp -f /run/agenix/app-env " composePreStart)
            "envFile must be read at runtime, not copied into the Nix store";
          assert nixpkgs.lib.assertMsg (
            resticPasswordFile == "/run/agenix/restic-password"
          ) "backup passwordFile must stay a runtime path, got: ${resticPasswordFile}";
          assert nixpkgs.lib.assertMsg (
            grafana.serviceConfig.LoadCredential == [
              "secret_key:/run/agenix/grafana-secret-key"
              "admin_password:/run/agenix/grafana-admin-password"
            ]
          ) "grafana secret key and admin password must be passed as systemd credentials";
          assert nixpkgs.lib.assertMsg (
            nixpkgs.lib.hasInfix "$CREDENTIALS_DIRECTORY/secret_key" grafana.preStart
            && nixpkgs.lib.hasInfix "$CREDENTIALS_DIRECTORY/admin_password" grafana.preStart
          ) "grafana must refuse to start with an empty secret key or admin password";
          assert nixpkgs.lib.assertMsg (
            grafanaSettings.security.admin_password
            == "$__file{/run/credentials/grafana.service/admin_password}"
            && grafanaSettings.server.http_addr == "127.0.0.1"
            && !builtins.elem 3100 firewall.allowedTCPPorts
          ) "grafana must not ship default credentials or listen publicly";
          assert nixpkgs.lib.assertMsg (
            !builtins.elem 9100 firewall.allowedTCPPorts
            && nixpkgs.lib.hasInfix "iptables -w -A nixos-fw -p tcp -s 10.0.0.10/32 --dport 9100 -j nixos-fw-accept" firewall.extraCommands
            && nixpkgs.lib.hasInfix "ip6tables -w -A nixos-fw -p tcp -s fd00::10/128 --dport 9100 -j nixos-fw-accept" firewall.extraCommands
          ) "node exporter must only be reachable from nodeExporterAllowedSources";
          assert nixpkgs.lib.assertMsg (
            !grafanaSettings.analytics.reporting_enabled
            && !grafanaSettings.analytics.check_for_updates
            && !grafanaSettings.analytics.check_for_plugin_updates
            && grafanaSettings.plugins.preinstall_disabled
            && grafanaSettings.plugins.public_key_retrieval_disabled
            && !grafanaSettings.news.news_feed_enabled
            && !grafanaSettings.snapshots.external_enabled
            && grafanaSettings.security.disable_gravatar
          ) "grafana must not make outbound connections";
          pkgs.runCommand "template-eval" { } "touch $out";
      };

      # ── Dev Shell ───────────────────────────────────────────────────
      devShells.${system}.default = pkgs.mkShell {
        inherit (pre-commit-check) shellHook;
        buildInputs = with pkgs; [
          # Deployment
          nixos-rebuild
          inputs.colmena.packages.${system}.colmena
          agenix.packages.${system}.default
          git
          ssh-to-age

          # Code quality
          statix
          deadnix
          treefmtEval.config.build.wrapper
        ];
      };
    };
}
