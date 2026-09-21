# modules/baseline/platform.nix
# ─────────────────────────────────────────────────────────────────────
# Binds the three things every template configures the same way to their
# service modules: container engine, watchdog and boot splash.
#
# The service modules themselves stay parameter-agnostic so they can be
# instantiated directly in tests. This file is the only place that knows
# bauergroup.params exists.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  config,
  ...
}:
let
  params = config.bauergroup.params;
in
{
  imports = [
    ../services/containers.nix
    ../services/watchdog.nix
    ../features/branding.nix
  ];

  bauergroup.services.containers = {
    inherit (params.containers) enable engine;
  };

  bauergroup.services.watchdog = {
    inherit (params.watchdog)
      enable
      runtimeTime
      rebootTime
      kernelModules
      useSoftdog
      ;
  };

  # A concrete value in params beats the template's own default; null leaves
  # the template's mkDefault in charge, which is what "follow the template"
  # means for this option.
  bauergroup.features.branding = {
    enable = lib.mkIf (params.branding.enable != null) params.branding.enable;
    inherit (params.branding) silentBoot;
  };
}
