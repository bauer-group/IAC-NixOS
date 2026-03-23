# modules/baseline/ntp.nix
# ─────────────────────────────────────────────────────────────────────
# Global NTP/time synchronisation baseline.
# Uses chrony (modern, accurate, handles VM clock drift well).
# All values use mkDefault so hosts can override if needed.
# ─────────────────────────────────────────────────────────────────────
{ lib, ... }:
{

  # Disable systemd-timesyncd (conflicts with chrony)
  services.timesyncd.enable = lib.mkDefault false;

  # Chrony as NTP client
  services.chrony = {
    enable = lib.mkDefault true;

    # BAUER GROUP primary, de.pool.ntp.org as fallback
    servers = lib.mkDefault [
      "time.bauer-group.com"
      "0.de.pool.ntp.org"
      "1.de.pool.ntp.org"
      "2.de.pool.ntp.org"
    ];

    # Extra config: allow large initial correction, log stats
    extraConfig = lib.mkDefault ''
      # Allow large time step on first sync (useful after reboot)
      makestep 1.0 3
      # Log time tracking statistics
      logdir /var/log/chrony
      log tracking measurements statistics
    '';
  };

  # Default timezone — override per host if needed
  # e.g. Thailand hosts: time.timeZone = "Asia/Bangkok";
  time.timeZone = lib.mkDefault "Europe/Berlin";
}
