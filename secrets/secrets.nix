# secrets/secrets.nix
# ─────────────────────────────────────────────────────────────────────
# Definiert welche Keys welche Secrets entschlüsseln dürfen.
# Dieses File ist NICHT verschlüsselt und wird committet.
#
# Keys generieren:
#   ssh-keyscan -t ed25519 SERVER_IP 2>/dev/null | ssh-to-age
#   cat ~/.ssh/id_ed25519.pub | ssh-to-age
# ─────────────────────────────────────────────────────────────────────
let
  # ── Admin Keys (können Secrets editieren) ──────────────────────
  admin = "age1TODO_REPLACE_WITH_YOUR_AGE_KEY";

  # ── Machine Keys (können Secrets zur Laufzeit lesen) ───────────
  # Add each machine's age key here after deployment:
  # machine-01 = "age1...";
  # machine-02 = "age1...";

  # ── Gruppen ─────────────────────────────────────────────────────
  allMachines = [
    # machine-01
    # machine-02
  ];
in
{
  # Dateiname → wer darf entschlüsseln
  # "restic-password.age".publicKeys    = [ admin ] ++ allMachines;
  # "outline-env.age".publicKeys        = [ admin machine-01 ];
  # "grafana-password.age".publicKeys   = [ admin machine-01 ];
}
