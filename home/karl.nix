# home/karl.nix
# ─────────────────────────────────────────────────────────────────────
# Karl's personal Home Manager configuration.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, config, ... }: {

  imports = [ ./common.nix ];

  home.username = "karl";
  home.homeDirectory = "/home/karl";

  # ── Git identity ────────────────────────────────────────────────
  programs.git = {
    userName = "Karl";                           # TODO: full name
    userEmail = "karl@bauer-group.com";          # TODO: real email
    signing = {
      # signByDefault = true;
      # key = "~/.ssh/id_ed25519";               # SSH signing
    };
  };

  # ── SSH Config ──────────────────────────────────────────────────
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "prod-01" = {
        hostname = "10.0.0.1";               # TODO: real IP
        user = "root";
        identityFile = "~/.ssh/id_ed25519";
      };
      "prod-02" = {
        hostname = "10.0.0.2";
        user = "root";
        identityFile = "~/.ssh/id_ed25519";
      };
      # Wildcard for all Hetzner hosts
      "*.hetzner" = {
        user = "root";
        identityFile = "~/.ssh/id_ed25519";
        serverAliveInterval = 60;
      };
    };
  };

  # ── Neovim ──────────────────────────────────────────────────────
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # ── Kitty Terminal ──────────────────────────────────────────────
  programs.kitty = {
    enable = true;
    settings = {
      font_family = "JetBrains Mono";
      font_size = 12;
      enable_audio_bell = false;
      copy_on_select = "clipboard";
      scrollback_lines = 10000;
    };
  };

  # ── Desktop Entries / XDG ───────────────────────────────────────
  xdg.mimeApps.enable = true;

  # ── Extra packages (user-level, not system-wide) ────────────────
  home.packages = with pkgs; [
    # Nix tools
    nix-tree             # Visualise Nix store dependencies
    nix-diff             # Diff closures
    nix-output-monitor   # Pretty build output (nom)

    # File sync
    rclone
    restic               # Backup tool
  ];
}
