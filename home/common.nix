# home/common.nix
# ─────────────────────────────────────────────────────────────────────
# Shared Home Manager settings for all users.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, ... }:
{

  # ── Git ──────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    lfs.enable = true;
    delta.enable = true; # Better diff viewer
    extraConfig = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.autocrlf = "input";
    };
  };

  # ── Shell (Zsh) ─────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    history = {
      size = 50000;
      save = 50000;
      ignoreDups = true;
      share = true;
    };
    shellAliases = {
      ll = "ls -la";
      gs = "git status";
      gd = "git diff";
      gp = "git push";
      gl = "git log --oneline --graph --all";
      dc = "docker compose";
      dps = "docker ps --format 'table {{.Names}}\\t{{.Status}}\\t{{.Ports}}'";

      # NixOS
      nrs = "sudo nixos-rebuild switch --flake .";
      nrt = "sudo nixos-rebuild test --flake .";
      nrb = "nixos-rebuild build --flake .";
      nfu = "nix flake update";
    };
    initExtra = ''
      # Quick CAN-Bus aliases
      alias candump0='candump vcan0'
      alias cansend0='cansend vcan0'
    '';
  };

  # ── Starship Prompt ─────────────────────────────────────────────
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
      };
      nix_shell = {
        symbol = "❄️ ";
        format = "via [$symbol$state]($style) ";
      };
    };
  };

  # ── Direnv (auto-activate nix shells) ───────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ── FZF ─────────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
  };

  # ── Home State Version ──────────────────────────────────────────
  home.stateVersion = "25.11";
}
