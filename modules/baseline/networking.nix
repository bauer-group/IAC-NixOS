# modules/baseline/networking.nix
# ─────────────────────────────────────────────────────────────────────
# Network baseline: firewall defaults, DNS, hostname conventions.
# ─────────────────────────────────────────────────────────────────────
{ lib, ... }: {

  # Enable firewall by default — services opt-in to open ports
  networking.firewall = {
    enable = lib.mkDefault true;
    allowPing = lib.mkDefault true;

    # Log dropped packets (useful for debugging, not too noisy)
    logReversePathDrops = lib.mkDefault true;
  };

  # Use systemd-resolved for DNS
  services.resolved = {
    enable = lib.mkDefault true;
    # Cloudflare + Google as fallback
    fallbackDns = [
      "1.1.1.1"
      "8.8.8.8"
      "2606:4700:4700::1111"
    ];
    dnsovertls = "opportunistic";
  };

  # Sane kernel network parameters
  boot.kernel.sysctl = {
    # TCP hardening
    "net.ipv4.tcp_syncookies" = lib.mkDefault 1;
    "net.ipv4.conf.all.rp_filter" = lib.mkDefault 1;
    "net.ipv4.conf.default.rp_filter" = lib.mkDefault 1;

    # Disable IPv6 router advertisements on servers (override on desktops)
    "net.ipv6.conf.all.accept_ra" = lib.mkDefault 0;

    # BBR congestion control (better throughput)
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
  };
}
