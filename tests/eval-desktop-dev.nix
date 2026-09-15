# tests/eval-desktop-dev.nix
# ─────────────────────────────────────────────────────────────────────
# desktop-dev params for checks.x86_64-linux.template-eval.
# Enables the embedded feature so embedded-dev.nix is evaluated too.
# ─────────────────────────────────────────────────────────────────────
_: {
  bauergroup.params.dev.embeddedDev = true;
}
