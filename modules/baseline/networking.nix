# modules/baseline/networking.nix
# ─────────────────────────────────────────────────────────────────────
# Network baseline: firewall, DNS, hostname, static/DHCP from params.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  config,
  ...
}:
let
  params = config.bauer.params;
  net = params.network;
in
{
  # ── Hostname ────────────────────────────────────────────────────────
  networking.hostName = params.hostName;

  # ── IP configuration ───────────────────────────────────────────────
  networking.useDHCP = lib.mkDefault net.useDHCP;
  networking.interfaces.${net.interface} = lib.mkIf (!net.useDHCP) {
    ipv4.addresses = [
      {
        address = net.address;
        prefixLength = net.prefixLength;
      }
    ];
  };
  networking.defaultGateway = lib.mkIf (!net.useDHCP && net.gateway != null) net.gateway;
  networking.nameservers = net.nameservers;

  # ── Firewall ────────────────────────────────────────────────────────
  networking.firewall = {
    enable = lib.mkDefault true;
    allowPing = lib.mkDefault true;
    allowedTCPPorts = net.openPorts;
    logReversePathDrops = lib.mkDefault true;
  };

  # ── DNS ─────────────────────────────────────────────────────────────
  services.resolved = {
    enable = lib.mkDefault true;
    fallbackDns = [
      "1.1.1.1"
      "8.8.8.8"
      "2606:4700:4700::1111"
    ];
    dnsovertls = "opportunistic";
  };

  # ── Kernel network parameters ──────────────────────────────────────
  boot.kernel.sysctl = {
    "net.ipv4.tcp_syncookies" = lib.mkDefault 1;
    "net.ipv4.conf.all.rp_filter" = lib.mkDefault 1;
    "net.ipv4.conf.default.rp_filter" = lib.mkDefault 1;
    "net.ipv6.conf.all.accept_ra" = lib.mkDefault 0;
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };

  # ── Locale (from params) ───────────────────────────────────────────
  time.timeZone = params.timezone;
  i18n.defaultLocale = lib.mkDefault params.locale;
  console.keyMap = lib.mkDefault params.keymap;
}
