# tests/eval-desktop-kiosk.nix
# ─────────────────────────────────────────────────────────────────────
# desktop-kiosk params for checks.x86_64-linux.template-eval.
# Enables the optional kiosk features so their code paths are evaluated.
# ─────────────────────────────────────────────────────────────────────
_: {
  bauergroup.params.kiosk = {
    composeFile = "/opt/kiosk/docker-compose.yml";
    touchscreen = true;
    rotation = "left";
    idleTimeout = 300;
  };
}
