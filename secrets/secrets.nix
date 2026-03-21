# secrets/secrets.nix
# ─────────────────────────────────────────────────────────────────────
# Definiert welche Host-/User-Keys welche Secrets entschlüsseln dürfen.
# Dieses File ist NICHT verschlüsselt und wird committet.
#
# Keys generieren:
#   ssh-keyscan -t ed25519 SERVER_IP 2>/dev/null | ssh-to-age
#   cat ~/.ssh/id_ed25519.pub | ssh-to-age
# ─────────────────────────────────────────────────────────────────────
let
  # ── User Keys (können Secrets editieren) ────────────────────────
  karl = "age1TODO_REPLACE_WITH_YOUR_AGE_KEY";

  # ── Host Keys (können Secrets zur Laufzeit lesen) ───────────────
  karl-desktop   = "age1TODO_REPLACE_WITH_HOST_KEY";
  prod-server-01 = "age1TODO_REPLACE_WITH_HOST_KEY";
  prod-server-02 = "age1TODO_REPLACE_WITH_HOST_KEY";

  # ── Gruppen ─────────────────────────────────────────────────────
  allServers = [ prod-server-01 prod-server-02 ];
  allHosts = allServers ++ [ karl-desktop ];
in {
  # Dateiname → wer darf entschlüsseln
  # "db-password.age".publicKeys        = [ karl ] ++ allServers;
  # "outline-secret-key.age".publicKeys = [ karl prod-server-01 ];
  # "wireguard-private.age".publicKeys  = [ karl ] ++ allHosts;
}
