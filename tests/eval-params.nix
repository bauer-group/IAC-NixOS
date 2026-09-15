# tests/eval-params.nix
# ─────────────────────────────────────────────────────────────────────
# Fixed params shared by all template evaluations in checks.template-eval.
# Stands in for /etc/nixos/params.nix, which pure evaluation cannot read.
# Template-specific values live in tests/eval-<template>.nix.
# ─────────────────────────────────────────────────────────────────────
_: {
  bauergroup.params = {
    hostName = "eval-check";
    user.sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvaluationCheckOnly check@eval" ];
  };

  # Stands in for /etc/nixos/hardware-configuration.nix, so the root
  # filesystem assertion passes when the whole system is evaluated
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
}
