# modules/services/docker.nix
# ─────────────────────────────────────────────────────────────────────
# Docker Engine for production servers.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, ... }: {

  virtualisation.docker = {
    enable = true;
    enableOnBoot = lib.mkDefault true;

    # Use overlay2 storage driver
    storageDriver = lib.mkDefault "overlay2";

    # Live restore: containers keep running during daemon restart
    liveRestore = true;

    # Log rotation
    daemon.settings = {
      "log-driver" = "json-file";
      "log-opts" = {
        "max-size" = "10m";
        "max-file" = "3";
      };
    };

    # Auto-prune unused images weekly
    autoPrune = {
      enable = true;
      dates = "weekly";
      flags = [ "--all" "--filter" "until=168h" ];
    };
  };

  # Docker Compose
  environment.systemPackages = with pkgs; [
    docker-compose
    lazydocker      # TUI for Docker
  ];

  # Firewall: Docker manages its own iptables rules
  # But we need to explicitly allow forwarding for container networking
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
}
