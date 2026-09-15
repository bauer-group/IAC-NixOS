# home/common.nix
# ─────────────────────────────────────────────────────────────────────
# Shared Home Manager settings for all users.
# ─────────────────────────────────────────────────────────────────────
{ lib, osConfig, ... }:
let
  params = osConfig.bauergroup.params;
  inherit (params.autoUpdate) template;

  # Configurations are named after templates, not hostnames, and read
  # /etc/nixos/params.nix, so every rebuild needs #<template> and --impure
  rebuild = action: "nixos-rebuild ${action} --flake .#${template} --impure";
in
{

  # ── Git ──────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    lfs.enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase = true;
      push.autoSetupRemote = true;
      core.autocrlf = "input";
    };
  };

  # Better diff viewer
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
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
      nrs = "sudo ${rebuild "switch"}";
      nrt = "sudo ${rebuild "test"}";
      nrb = rebuild "build";
      nfu = "nix flake update";
    }
    # can-utils and vcan0 only exist with the embedded feature of desktop-dev
    // lib.optionalAttrs (template == "desktop-dev" && params.dev.embeddedDev) {
      candump0 = "candump vcan0";
      cansend0 = "cansend vcan0";
    };
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
  home.stateVersion = "26.05";
}
