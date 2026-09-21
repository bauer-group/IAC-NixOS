# tests/eval-embedded-kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# embedded-kiosk params for checks.x86_64-linux.template-eval.
#
# Deliberately the mirror image of eval-desktop-kiosk.nix: that one covers
# browser mode on Docker, this one covers native-application mode on Podman
# with an explicit health probe. Between them every branch in the kiosk,
# container and watchdog modules is evaluated.
# ─────────────────────────────────────────────────────────────────────
_: {
  bauergroup.params = {
    kiosk = {
      mode = "application";
      application = {
        command = "/opt/hmi/BauerGroup.Hmi";
        environment.DOTNET_SYSTEM_GLOBALIZATION_INVARIANT = "1";
        # A dotnet publish output, so it needs the loader NixOS does not have
        # at the usual path
        foreignBinaries = true;
      };
      # No generic probe exists for a native binary, so the HMI supplies one
      healthCheckCommand = "/run/current-system/sw/bin/curl -sf --max-time 5 http://127.0.0.1:8080/healthz";
      touchscreen = true;
      extraGroups = [ "dialout" ];
      # Exercises the compose backend against Podman rather than Docker
      composeFile = "/opt/kiosk/docker-compose.yml";
    };

    containers.engine = "podman";

    watchdog.kernelModules = [ "iTCO_wdt" ];
  };
}
