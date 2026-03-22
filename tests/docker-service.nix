# tests/docker-service.nix
# ─────────────────────────────────────────────────────────────────────
# Verifies that Docker starts correctly with BAUER GROUP defaults.
# Run: nix build .#checks.x86_64-linux.docker-service
# ─────────────────────────────────────────────────────────────────────
{
  pkgs,
  ...
}:
pkgs.nixosTest {
  name = "docker-service";

  nodes.server =
    { ... }:
    {
      imports = [
        ../modules/services/docker.nix
        ../modules/baseline/nix.nix
      ];

      bauer.services.docker.enable = true;
      users.mutableUsers = true;
    };

  testScript = ''
    server.wait_for_unit("docker.service")

    # Verify Docker is running
    server.succeed("docker info")

    # Verify overlay2 storage driver
    server.succeed("docker info | grep -i 'storage driver: overlay2'")

    # Verify auto-prune timer is scheduled
    server.succeed("systemctl list-timers | grep docker-prune")

    # Verify IP forwarding is enabled
    server.succeed("sysctl net.ipv4.ip_forward | grep '= 1'")

    # Verify docker-compose is available
    server.succeed("which docker-compose")
  '';
}
