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

    # PTB (Physikalisch-Technische Bundesanstalt) + pool
    servers = lib.mkDefault [
      "ptbtime1.ptb.de"
      "ptbtime2.ptb.de"
      "ptbtime3.ptb.de"
      "de.pool.ntp.org"
    ];

    # Extra config: allow large initial correction, log stats
    extraConfig = lib.mkDefault ''
      # Allow large time step on first sync (useful after reboot)
      makestep 1.0 3
      # Log time tracking statistics
      logdir /var/log/chrony
      log tracking measurements statistics
      # RTC synchronisation (bare metal only, ignored in VMs)
      rtcsync
    '';
  };

  # Default timezone — override per host if needed
  # e.g. Thailand hosts: time.timeZone = "Asia/Bangkok";
  time.timeZone = lib.mkDefault "Europe/Berlin";
}
