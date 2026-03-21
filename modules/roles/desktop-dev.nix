# modules/roles/desktop-dev.nix
# ─────────────────────────────────────────────────────────────────────
# Developer desktop role.
# Inherits server baseline, adds GUI, dev tooling, productivity apps.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, config, ... }: {

  imports = [
    ./server.nix
  ];

  # ── Desktop overrides ────────────────────────────────────────────
  nixpkgs.config.allowUnfree = lib.mkForce true;

  # Disable server-only services on desktop
  services.fail2ban.enable = lib.mkForce false;
  security.auditd.enable = lib.mkForce false;
  security.audit.enable = lib.mkForce false;

  # Accept IPv6 RA normally on desktop
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 1;

  # ── Display / Desktop Environment ────────────────────────────────
  services.xserver.enable = true;
  services.displayManager.sddm.enable = lib.mkDefault true;
  services.desktopManager.plasma6.enable = lib.mkDefault true;

  # Wayland
  programs.xwayland.enable = true;

  # ── Audio ────────────────────────────────────────────────────────
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  # ── Networking (Desktop) ─────────────────────────────────────────
  networking.networkmanager.enable = lib.mkDefault true;

  # ── Fonts ────────────────────────────────────────────────────────
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
      monospace = [ "JetBrains Mono" "Fira Code" ];
      sansSerif = [ "Noto Sans" ];
      serif = [ "Noto Serif" ];
    };
  };

  # ── Development Tools ────────────────────────────────────────────
  environment.systemPackages = with pkgs; [
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
    gh  # GitHub CLI

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
    yazi          # TUI file manager
    p7zip
    file
  ];

  # ── Docker ───────────────────────────────────────────────────────
  virtualisation.docker = {
    enable = lib.mkDefault true;
    enableOnBoot = lib.mkDefault false;  # start on demand on desktop
  };

  # ── Keyboard ─────────────────────────────────────────────────────
  services.xserver.xkb = {
    layout = lib.mkDefault "de";
    variant = lib.mkDefault "";
  };
  console.keyMap = lib.mkForce "de-latin1";

  # ── Printing ─────────────────────────────────────────────────────
  services.printing.enable = lib.mkDefault true;

  # ── Flatpak (escape hatch for apps not in Nixpkgs) ──────────────
  services.flatpak.enable = lib.mkDefault true;
}
