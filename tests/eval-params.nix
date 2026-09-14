# tests/eval-params.nix
# ─────────────────────────────────────────────────────────────────────
# Fixed params for checks.x86_64-linux.template-eval.
# Stands in for /etc/nixos/params.nix, which pure evaluation cannot read.
# ─────────────────────────────────────────────────────────────────────
_: {
  bauergroup.params = {
    hostName = "eval-check";
    user.sshKeys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEvaluationCheckOnly check@eval" ];

    # Unquoted paths on purpose: secrets must never be copied into the store
    server = {
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
  };
}
