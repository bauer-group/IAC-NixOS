# tests/container-engine.nix
# ─────────────────────────────────────────────────────────────────────
# Verifies that bauergroup.services.containers behaves identically with
# either engine: same socket path, same compose binary, same group.
# Run: nix build .#checks.x86_64-linux.container-engine
#
# The point of the Podman node is the claim this repo's compose units rest
# on — that Compose v2 drives Podman through /run/docker.sock unchanged.
# That is asserted by running a container, not by reading the config.
# ─────────────────────────────────────────────────────────────────────
{
  pkgs,
  ...
}:
let
  # Built locally: VM tests have no network, so nothing can be pulled
  helloImage = pkgs.dockerTools.buildImage {
    name = "bg-hello";
    tag = "test";
    copyToRoot = pkgs.buildEnv {
      name = "bg-hello-root";
      paths = [
        pkgs.coreutils
        pkgs.busybox
      ];
      pathsToLink = [ "/bin" ];
    };
    config.Cmd = [
      "/bin/echo"
      "container-engine-ok"
    ];
  };

  composeFile = pkgs.writeText "docker-compose.yml" ''
    services:
      hello:
        image: bg-hello:test
        command: ["/bin/echo", "compose-ok"]
  '';

  node = engine: _: {
    imports = [
      ../modules/services/containers.nix
      ../modules/baseline/nix.nix
    ];

    bauergroup.services.containers = {
      inherit engine;
      enable = true;
      storageDriver = if engine == "docker" then "overlay2" else null;
    };

    users.mutableUsers = true;
    virtualisation.diskSize = 4096;
  };
in
pkgs.testers.nixosTest {
  name = "container-engine";

  nodes = {
    docker = node "docker";
    podman = node "podman";
  };

  testScript = ''
    start_all()

    docker.wait_for_unit("docker.service")
    # Podman is daemonless: the API socket is what compose talks to
    podman.wait_for_unit("sockets.target")
    podman.wait_for_file("/run/docker.sock")

    for machine in (docker, podman):
        # Same socket path and same CLI name under either engine
        machine.succeed("docker info")
        machine.succeed("test -S /run/docker.sock")
        machine.succeed("docker-compose version")

        # -L on purpose. Under Docker this path is the socket itself, but under
        # Podman it is a symlink systemd creates through Symlinks=, and a
        # symlink is owned root:root regardless of the socket behind it. Without
        # dereferencing, this asserts the group of the wrong inode and fails on
        # Podman while passing on Docker.
        machine.succeed("stat -Lc %G /run/docker.sock | grep -x docker")

        # IP forwarding, required for container networking
        machine.succeed("sysctl net.ipv4.ip_forward | grep '= 1'")

        # End to end: load a locally built image and run it through the socket
        machine.succeed("docker load < ${helloImage}")
        machine.succeed("docker run --rm bg-hello:test | grep -x container-engine-ok")

        # The claim this repo's compose units rest on
        machine.succeed("mkdir -p /tmp/compose && cp ${composeFile} /tmp/compose/docker-compose.yml")
        machine.succeed(
            "cd /tmp/compose && docker-compose up --exit-code-from hello 2>&1 | grep compose-ok"
        )

    # Docker-only: the storageDriver option actually reaches the daemon
    docker.succeed("docker info | grep -i 'storage driver: overlay2'")
    docker.succeed("systemctl list-timers | grep docker-prune")

    # Podman must not have pulled in a Docker daemon. systemctl cat exits
    # non-zero on an unknown unit, which is a direct answer; grepping the
    # unit-file listing depends on its column layout.
    podman.fail("systemctl cat docker.service")
    podman.succeed("systemctl list-timers | grep podman-prune")
  '';
}
