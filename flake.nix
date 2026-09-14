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
        lint =
          pkgs.runCommand "lint"
            {
              nativeBuildInputs = with pkgs; [
                deadnix
              ];
            }
            ''
              cd ${self}
              deadnix . --exclude params.example.nix
              touch $out
            '';

        # Evaluates the server template with fixed params instead of /etc/nixos
        template-eval =
          let
            inherit (mkSystem "server" [ ./tests/eval-params.nix ]) config;
            upgradeFlags = toString config.system.autoUpgrade.flags;
            composePreStart = config.systemd.services.compose-app.preStart;
            resticPasswordFile = config.services.restic.backups.system.passwordFile;
            grafana = config.systemd.services.grafana;
          in
          assert nixpkgs.lib.assertMsg
            (nixpkgs.lib.hasInfix "--flake github:bauer-group/IAC-NixOS#server" upgradeFlags)
            "auto-update must target #server, got: ${upgradeFlags}";
          assert nixpkgs.lib.assertMsg (nixpkgs.lib.hasInfix "cp -f /run/agenix/app-env " composePreStart)
            "envFile must be read at runtime, not copied into the Nix store";
          assert nixpkgs.lib.assertMsg (
            resticPasswordFile == "/run/agenix/restic-password"
          ) "backup passwordFile must stay a runtime path, got: ${resticPasswordFile}";
          assert nixpkgs.lib.assertMsg (
            grafana.serviceConfig.LoadCredential == [ "secret_key:/run/agenix/grafana-secret-key" ]
          ) "grafana secret key must be passed as a systemd credential";
          assert nixpkgs.lib.assertMsg
            (nixpkgs.lib.hasInfix "$CREDENTIALS_DIRECTORY/secret_key" grafana.preStart)
            "grafana must refuse to start with an empty secret key";
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
