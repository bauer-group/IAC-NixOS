# hosts/karl-desktop/hardware-configuration.nix
# ─────────────────────────────────────────────────────────────────────
# PLACEHOLDER — Replace with output of `nixos-generate-config --show-hardware-config`
# Run on your actual hardware and paste the output here.
# ─────────────────────────────────────────────────────────────────────
{ config, lib, pkgs, modulesPath, ... }: {

  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # TODO: Replace these with your actual hardware config
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];  # or kvm-amd
  boot.extraModulePackages = [ ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-YOUR-UUID";
    fsType = "ext4";  # or btrfs, zfs, etc.
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/REPLACE-WITH-YOUR-UUID";
    fsType = "vfat";
  };

  swapDevices = [
    # { device = "/dev/disk/by-uuid/REPLACE-WITH-YOUR-UUID"; }
  ];

  # High-resolution display scaling (uncomment if needed)
  # services.xserver.dpi = 192;

  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
