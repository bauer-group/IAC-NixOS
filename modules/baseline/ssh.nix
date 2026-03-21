# modules/baseline/ssh.nix
# ─────────────────────────────────────────────────────────────────────
# Hardened SSH baseline for all machines.
# ─────────────────────────────────────────────────────────────────────
{ lib, ... }: {

  services.openssh = {
    enable = lib.mkDefault true;

    settings = {
      # Key-only auth (no passwords)
      PasswordAuthentication = lib.mkDefault false;
      KbdInteractiveAuthentication = lib.mkDefault false;
      PermitRootLogin = lib.mkDefault "prohibit-password";

      # Modern crypto only
      KexAlgorithms = [
        "curve25519-sha256"
        "curve25519-sha256@libssh.org"
      ];

      # Idle timeout
      ClientAliveInterval = 300;
      ClientAliveCountMax = 2;
    };

    # Disable host key types we don't need
    hostKeys = [
      { path = "/etc/ssh/ssh_host_ed25519_key"; type = "ed25519"; }
    ];
  };

  # Firewall: allow SSH
  networking.firewall.allowedTCPPorts = [ 22 ];
}
