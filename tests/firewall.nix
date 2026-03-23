# tests/firewall.nix
# ─────────────────────────────────────────────────────────────────────
# Verifies that the firewall baseline is correctly configured.
# Run: nix build .#checks.x86_64-linux.firewall
# ─────────────────────────────────────────────────────────────────────
{
  pkgs,
  ...
}:
pkgs.nixosTest {
  name = "firewall";

  nodes.server =
    _:
    {
      imports = [
        ../modules/baseline/networking.nix
        ../modules/baseline/nix.nix
        ../modules/params.nix
      ];

      # Provide required params for networking module
      bauergroup.params = {
        hostName = "test-firewall";
        network = {
          useDHCP = true;
          openPorts = [
            80
            443
          ];
        };
      };

      users.mutableUsers = true;
    };

  testScript = ''
    server.wait_for_unit("firewall.service")

    # Verify firewall is active
    server.succeed("systemctl is-active firewall.service")

    # Verify web ports are allowed
    server.succeed("iptables -L INPUT -n | grep '80'")
    server.succeed("iptables -L INPUT -n | grep '443'")

    # Verify TCP SYN cookies are enabled
    server.succeed("sysctl net.ipv4.tcp_syncookies | grep '= 1'")

    # Verify reverse path filtering
    server.succeed("sysctl net.ipv4.conf.all.rp_filter | grep '= 1'")

    # Verify BBR congestion control
    server.succeed("sysctl net.ipv4.tcp_congestion_control | grep 'bbr'")
  '';
}
