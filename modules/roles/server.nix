# modules/roles/server.nix
# ─────────────────────────────────────────────────────────────────────
# Production server role.
# Composes all baseline modules + adds server hardening.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, config, ... }: {

  imports = [
    ../baseline/ntp.nix
    ../baseline/ssh.nix
    ../baseline/users.nix
    ../baseline/networking.nix
    ../baseline/nix.nix
  ];

  # ── Boot ─────────────────────────────────────────────────────────
  # Servers use stable LTS kernel by default
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;

  # Clean /tmp on boot
  boot.tmp.cleanOnBoot = lib.mkDefault true;

  # ── Security ─────────────────────────────────────────────────────
  # Audit framework
  security.auditd.enable = lib.mkDefault true;
  security.audit = {
    enable = lib.mkDefault true;
    rules = [
      "-a exit,always -F arch=b64 -S execve"
    ];
  };

  # Fail2ban for SSH brute-force protection
  services.fail2ban = {
    enable = lib.mkDefault true;
    maxretry = 5;
    bantime = "1h";
    bantime-increment.enable = true;
  };

  # ── Monitoring ───────────────────────────────────────────────────
  # Node exporter for Prometheus (optional, enable per host)
  # services.prometheus.exporters.node = {
  #   enable = true;
  #   enabledCollectors = [ "systemd" "processes" ];
  #   port = 9100;
  # };

  # Journald: persistent logging with size limit
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    MaxRetentionSec=30day
  '';

  # ── Server-specific network settings ─────────────────────────────
  # Accept IPv6 RA on servers too (many hosters need it)
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 2;

  # ── Locale ───────────────────────────────────────────────────────
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";
  console.keyMap = lib.mkDefault "de-latin1";
}
