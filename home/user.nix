# home/user.nix
# ─────────────────────────────────────────────────────────────────────
# Parametric Home Manager configuration.
# Reads user identity from bauergroup.params.user (passed via extraSpecialArgs).
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  userParams = osConfig.bauergroup.params.user;
in
{
  imports = [ ./common.nix ];

  home.username = userParams.name;
  home.homeDirectory = "/home/${userParams.name}";

  # ── Git identity (from params) ────────────────────────────────────
  programs.git = {
    userName = lib.mkIf (userParams.fullName != "") userParams.fullName;
    userEmail = lib.mkIf (userParams.email != "") userParams.email;
  };

  # ── SSH ────────────────────────────────────────────────────────────
  programs.ssh = {
    enable = true;
    matchBlocks = {
      "*" = {
        identityFile = "~/.ssh/id_ed25519";
      };
    };
  };

  # ── Neovim ─────────────────────────────────────────────────────────
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };

  # ── Kitty Terminal (only useful on desktop templates) ──────────────
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

  # ── Extra packages (user-level) ───────────────────────────────────
  home.packages = with pkgs; [
    nix-tree
    nix-diff
    nix-output-monitor
    rclone
    restic
  ];
}
