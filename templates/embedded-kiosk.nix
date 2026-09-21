# templates/embedded-kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# HMI on the machine — a panel PC bolted to a production line.
#
# Same kiosk session as desktop-kiosk, different assumptions about the
# environment it lives in:
#
#   Reboots are disruptive.  The machine may be mid-cycle at 03:00, so
#     updates are built and staged but never reboot on their own. A kernel
#     update takes effect at the next planned restart.
#
#   Storage is flash.  Industrial panels boot from eMMC or an SD card with a
#     finite erase budget, so log writes are batched and capped rather than
#     streamed, and /tmp never touches the disk.
#
#   Nobody is watching.  No keyboard, often no network path inward. Recovery
#     has to be automatic: the watchdog is the only operator on site.
#
#   The network may be down.  The PLC segment is regularly unplugged during
#     maintenance, and boot must not wait on it.
#
# Deploy: nixos-rebuild switch --flake .#embedded-kiosk --impure
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  pkgs,
  config,
  ...
}:
let
  params = config.bauergroup.params;
in
{
  imports = [
    ../modules/baseline/ntp.nix
    ../modules/baseline/ssh.nix
    ../modules/baseline/users.nix
    ../modules/baseline/networking.nix
    ../modules/baseline/nix.nix
    ../modules/baseline/auto-update.nix
    ../modules/baseline/platform.nix
    ../modules/features/kiosk.nix
    ../modules/services/monitoring.nix
  ];

  # ── Boot ────────────────────────────────────────────────────────────
  boot.loader.systemd-boot = lib.mkIf (params.boot.loader == "systemd-boot") {
    enable = true;
    # Industrial panels ship small ESPs, and every generation keeps a kernel
    # and initrd there. Three is enough to roll back twice.
    configurationLimit = 3;
  };
  boot.loader.grub = lib.mkIf (params.boot.loader == "grub") {
    enable = true;
    device = params.boot.grubDevice;
    configurationLimit = 3;
  };
  boot.loader.efi.canTouchEfiVariables = params.boot.loader == "systemd-boot";

  # Hold the menu briefly so a technician with a keyboard can still roll back;
  # systemd-boot also opens it on a held key, but not every panel makes that easy
  boot.loader.timeout = lib.mkDefault 2;

  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages;
  boot.tmp.cleanOnBoot = true;
  # A tmpfs /tmp keeps scratch writes off the flash entirely
  boot.tmp.useTmpfs = lib.mkDefault true;

  # ── Branding ───────────────────────────────────────────────────────
  bauergroup.features.branding.enable = lib.mkDefault true;

  # ── Updates ────────────────────────────────────────────────────────
  # Build and activate, but never reboot on our own: this machine may be in
  # the middle of a production cycle at any hour. A staged kernel takes effect
  # at the next planned restart.
  bauergroup.params.autoUpdate.allowReboot = lib.mkDefault false;

  # ── Watchdog ───────────────────────────────────────────────────────
  # Left to the params default, but note that panel PCs frequently need their
  # watchdog driver named explicitly — see watchdog.kernelModules and confirm
  # with `wdctl` during commissioning. Without it /dev/watchdog never appears
  # and this machine has no automatic recovery at all.
  warnings = lib.optional (params.watchdog.enable && params.watchdog.kernelModules == [ ]) ''
    embedded-kiosk: watchdog.kernelModules is empty. Many industrial boards do
    not expose a watchdog until its driver is named (iTCO_wdt, sp5100_tco,
    it87_wdt, w83627hf_wdt). Run `wdctl` on the machine: if it reports no
    device, this HMI cannot recover from a freeze on its own.
  '';

  # ── Storage / flash wear ───────────────────────────────────────────
  services.journald.extraConfig = ''
    SystemMaxUse=64M
    SystemMaxFileSize=8M
    MaxRetentionSec=14day
    # Batch writes instead of streaming them: an HMI logs steadily for years,
    # and every sync is an erase cycle on eMMC
    SyncIntervalSec=5m
  '';

  # ── Boot must not wait on the plant network ────────────────────────
  # The PLC segment is unplugged during maintenance; without this the machine
  # stalls for the full wait-online timeout before showing anything
  systemd.network.wait-online.enable = lib.mkDefault false;
  systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;

  # ── Always on ──────────────────────────────────────────────────────
  # An HMI must never suspend. logind is already told to ignore the power key
  # and idle in the kiosk module; this removes the targets entirely, so nothing
  # else can pull the machine down either.
  systemd.targets = {
    sleep.enable = false;
    suspend.enable = false;
    hibernate.enable = false;
    "hybrid-sleep".enable = false;
  };

  # ── Monitoring ─────────────────────────────────────────────────────
  bauergroup.services.monitoring.exporterOnly = lib.mkDefault true;

  # ── Networking ─────────────────────────────────────────────────────
  boot.kernel.sysctl."net.ipv6.conf.all.accept_ra" = lib.mkForce 1;

  environment.systemPackages = with pkgs; [
    curl
    htop
    # Reading the panel's own hardware during a site visit
    usbutils
    pciutils
  ];

  # ── State Version ──────────────────────────────────────────────────
  system.stateVersion = "26.05";
}
