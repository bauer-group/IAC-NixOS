# modules/baseline/nix.nix
# ─────────────────────────────────────────────────────────────────────
# Nix daemon & store settings baseline.
# Flakes enabled, garbage collection, binary caches.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, ... }: {

  # Enable Flakes and new CLI
  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];

    # Binary caches
    substituters = [
      "https://cache.nixos.org"
      "https://nix-community.cachix.org"
    ];
    trusted-public-keys = [
      "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
    ];

    # Trust users in wheel group
    trusted-users = [ "root" "@wheel" ];

    # Auto-optimise store (deduplication via hard links)
    auto-optimise-store = true;
  };

  # Garbage collection: weekly, keep last 7 days
  nix.gc = {
    automatic = lib.mkDefault true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };

  # Keep nix-index updated for command-not-found
  programs.command-not-found.enable = false;
  programs.nix-index.enable = true;

  # System packages available everywhere
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    tree
    jq
    ripgrep
    fd
    unzip
  ];

  # Auto-upgrade (opt-in, disabled by default for safety)
  system.autoUpgrade.enable = lib.mkDefault false;
}
