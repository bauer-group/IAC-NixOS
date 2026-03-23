# templates/desktop-dev.nix
# ─────────────────────────────────────────────────────────────────────
# Development desktop template.
# Full KDE Plasma 6 desktop with development tools, editors, and
# optional CAN-Bus/embedded development support.
#
# Deploy: nixos-rebuild switch --flake .#desktop-dev --impure
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  params = config.bauergroup.params;
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
    ../modules/features/embedded-dev.nix
  ];

  # ── Boot ────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = lib.mkIf (params.boot.loader == "systemd-boot") {
    enable = true;
    configurationLimit = 10;
  };
  boot.loader.grub = lib.mkIf (params.boot.loader == "grub") {
    enable = true;
    device = params.boot.grubDevice;
  };
  boot.loader.efi.canTouchEfiVariables = params.boot.loader == "systemd-boot";

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;

  # ── Allow unfree packages (VSCode, Chrome, etc.) ───────────────────
  nixpkgs.config.allowUnfree = lib.mkForce true;

  # ── Display / Desktop Environment ──────────────────────────────────
  services.xserver.enable = true;
  services.displayManager.sddm.enable = lib.mkDefault true;
  services.desktopManager.plasma6.enable = lib.mkDefault true;
  programs.xwayland.enable = true;

  # ── Audio ──────────────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # ── Networking (Desktop uses NetworkManager) ───────────────────────
  networking.networkmanager.enable = lib.mkDefault true;
  networking.useDHCP = lib.mkForce false; # NetworkManager handles networking
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 1;

  # ── Fonts ──────────────────────────────────────────────────────────
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-emoji
      fira-code
      fira-code-symbols
      jetbrains-mono
      liberation_ttf
    ];
    fontconfig.defaultFonts = {
      monospace = [
        "JetBrains Mono"
        "Fira Code"
      ];
      sansSerif = [ "Noto Sans" ];
      serif = [ "Noto Serif" ];
    };
  };

  # ── Development Tools ──────────────────────────────────────────────
  environment.systemPackages =
    with pkgs;
    [
      # Editors
      vscode
      neovim

      # Terminal
      kitty
      tmux
      zellij

      # Version control
      git
      git-lfs
      lazygit
      gh

      # Languages & Runtimes
      rustup
      gcc
      cmake
      gnumake
      python3
      python3Packages.pip
      python3Packages.virtualenv
      nodejs_22
      nodePackages.pnpm
      go
      dotnet-sdk_8

      # Containers
      docker
      docker-compose
      lazydocker
      podman

      # Network / Debug
      wireshark
      nmap
      dig
      tcpdump
      mtr

      # Productivity
      firefox
      chromium
      thunderbird
      libreoffice
      obsidian

      # Communication
      signal-desktop

      # File management
      yazi
      p7zip
      file
    ]
    ++ params.dev.extraPackages;

  # ── Docker (on-demand, not on boot) ────────────────────────────────
  bauergroup.services.docker = {
    enable = lib.mkDefault true;
    enableOnBoot = lib.mkDefault false;
  };

  # ── Keyboard ───────────────────────────────────────────────────────
  services.xserver.xkb = {
    layout = lib.mkDefault params.xkbLayout;
    variant = lib.mkDefault "";
  };

  # ── Printing ───────────────────────────────────────────────────────
  services.printing.enable = lib.mkDefault true;

  # ── Flatpak (escape hatch) ────────────────────────────────────────
  services.flatpak.enable = lib.mkDefault true;

  # ── Bluetooth ──────────────────────────────────────────────────────
  hardware.bluetooth.enable = lib.mkDefault true;
  services.blueman.enable = lib.mkDefault true;

  # ── State Version ──────────────────────────────────────────────────
  system.stateVersion = "25.11";
}
