{
  description = "BAUER GROUP Infrastructure — NixOS Fleet Configuration";

  inputs = {
    # Stable channel for production servers
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    # Unstable channel for latest kernel & bleeding-edge packages
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Home Manager for user-level config (dotfiles, shell, editors)
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
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

    # Secret management (age-encrypted secrets in Git)
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ self, nixpkgs, nixpkgs-unstable, home-manager, disko, agenix, colmena, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };

      # Overlay: makes pkgs.unstable.* available everywhere
      unstableOverlay = final: prev: {
        unstable = import nixpkgs-unstable {
          inherit (final) config;
          inherit (final.stdenv.hostPlatform) system;
        };
      };

      # Shared specialArgs passed to all modules
      specialArgs = { inherit inputs self; };

      # Helper: generate a NixOS system configuration
      mkHost = { hostname, modules ? [], isDesktop ? false }:
        nixpkgs.lib.nixosSystem {
          inherit system specialArgs;
          modules = [
            # Global overlay
            { nixpkgs.overlays = [ unstableOverlay ]; }

            # Host-specific config
            ./hosts/${hostname}

            # Home Manager as NixOS module
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = specialArgs;
            }

            # Agenix secrets module
            agenix.nixosModules.default

            # Disko disk management
            disko.nixosModules.disko
          ] ++ modules;
        };

    in {
      # ── NixOS Configurations ──────────────────────────────────────────
      nixosConfigurations = {

        # Developer Desktop (Karl)
        karl-desktop = mkHost {
          hostname = "karl-desktop";
          isDesktop = true;
          modules = [
            ./modules/roles/desktop-dev.nix
            ./modules/roles/embedded-dev.nix
          ];
        };

        # Production Server 01
        prod-server-01 = mkHost {
          hostname = "prod-server-01";
          modules = [
            ./modules/roles/server.nix
            ./modules/services/docker.nix
            ./modules/services/outline.nix
          ];
        };

        # Production Server 02
        prod-server-02 = mkHost {
          hostname = "prod-server-02";
          modules = [
            ./modules/roles/server.nix
            ./modules/services/docker.nix
          ];
        };
      };

      # ── Colmena Deployment ────────────────────────────────────────────
      colmena = {
        meta = {
          nixpkgs = import nixpkgs {
            inherit system;
            overlays = [ unstableOverlay ];
          };
          specialArgs = specialArgs;
        };

        defaults = { ... }: {
          imports = [
            ./modules/roles/server.nix
            agenix.nixosModules.default
            disko.nixosModules.disko
          ];
        };

        prod-server-01 = { name, ... }: {
          deployment = {
            targetHost = "10.0.0.1";    # TODO: set real IP
            targetUser = "root";
            tags = [ "production" "hetzner" ];
          };
          imports = [ ./hosts/prod-server-01 ];
        };

        prod-server-02 = { name, ... }: {
          deployment = {
            targetHost = "10.0.0.2";    # TODO: set real IP
            targetUser = "root";
            tags = [ "production" "hetzner" ];
          };
          imports = [ ./hosts/prod-server-02 ];
        };
      };

      # ── Dev Shell ─────────────────────────────────────────────────────
      # `nix develop` gives you all deployment tools
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          nixos-rebuild
          colmena.packages.${system}.colmena
          agenix.packages.${system}.default
          git
          ssh-to-age
        ];
        shellHook = ''
          echo "╔══════════════════════════════════════════╗"
          echo "║  BAUER GROUP NixOS Infrastructure Shell  ║"
          echo "╠══════════════════════════════════════════╣"
          echo "║  colmena apply --on @production          ║"
          echo "║  colmena apply --on prod-server-01       ║"
          echo "║  nixos-rebuild switch --flake .#hostname  ║"
          echo "╚══════════════════════════════════════════╝"
        '';
      };
    };
}
