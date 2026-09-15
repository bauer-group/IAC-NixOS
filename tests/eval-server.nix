# tests/eval-server.nix
# ─────────────────────────────────────────────────────────────────────
# Server-specific params for checks.x86_64-linux.template-eval.
# Enables every optional feature so all of its code paths are evaluated.
# ─────────────────────────────────────────────────────────────────────
_: {
  # Unquoted paths on purpose: secrets must never be copied into the store
  bauergroup.params.server = {
    composeProjects.app = {
      directory = "/opt/app";
      envFile = /run/agenix/app-env;
    };
    backup = {
      enable = true;
      repository = "sftp:backup@storage:/backups/eval-check";
      passwordFile = /run/agenix/restic-password;
    };
  };

  bauergroup.services.monitoring = {
    enable = true;
    grafanaSecretKeyFile = /run/agenix/grafana-secret-key;
  };
}
