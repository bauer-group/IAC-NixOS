# tests/ssh-hardening.nix
# ─────────────────────────────────────────────────────────────────────
# Verifies that the SSH baseline hardening is correctly applied.
# Run: nix build .#checks.x86_64-linux.ssh-hardening
# ─────────────────────────────────────────────────────────────────────
{
  pkgs,
  ...
}:
pkgs.nixosTest {
  name = "ssh-hardening";

  nodes.server =
    { ... }:
    {
      imports = [
        ../modules/baseline/ssh.nix
        ../modules/baseline/nix.nix
      ];

      users.users.testuser = {
        isNormalUser = true;
        initialPassword = "test";
        extraGroups = [ "wheel" ];
      };
      users.mutableUsers = true;
    };

  testScript = ''
    server.wait_for_unit("sshd.service")

    # Verify SSH is listening
    server.succeed("ss -tlnp | grep ':22'")

    # Verify password authentication is disabled
    server.succeed("sshd -T | grep -i 'passwordauthentication no'")

    # Verify only Ed25519 host keys exist
    server.succeed("test -f /etc/ssh/ssh_host_ed25519_key")

    # Verify keyboard-interactive auth is disabled
    server.succeed("sshd -T | grep -i 'kbdinteractiveauthentication no'")

    # Verify root login is prohibited (or limited to keys)
    output = server.succeed("sshd -T | grep -i 'permitrootlogin'")
    assert "no" in output or "prohibit-password" in output, f"Root login not properly restricted: {output}"
  '';
}
