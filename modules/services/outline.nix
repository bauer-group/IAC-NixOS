# modules/services/outline.nix
# ─────────────────────────────────────────────────────────────────────
# Outline Wiki — runs as Docker Compose stack.
# Depends on: docker.nix
#
# Secrets (DB password, SECRET_KEY, UTILS_SECRET) should be managed
# via agenix — see docs/secrets.md for setup instructions.
# ─────────────────────────────────────────────────────────────────────
{ lib, pkgs, config, ... }: {

  # Ensure Docker is available
  assertions = [{
    assertion = config.virtualisation.docker.enable;
    message = "Outline module requires Docker. Import modules/services/docker.nix first.";
  }];

  # ── Compose Project Directory ────────────────────────────────────
  # The actual docker-compose.yml lives in /opt/outline/
  # and is managed outside of Nix (or via a derivation if you prefer).
  # This module only sets up the systemd service wrapper.

  systemd.services.outline = {
    description = "Outline Wiki (Docker Compose)";
    wantedBy = [ "multi-user.target" ];
    after = [ "docker.service" "network-online.target" ];
    requires = [ "docker.service" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      WorkingDirectory = "/opt/outline";
      ExecStart = "${pkgs.docker-compose}/bin/docker-compose up -d";
      ExecStop = "${pkgs.docker-compose}/bin/docker-compose down";
      TimeoutStartSec = "120";
    };
  };

  # ── Firewall ─────────────────────────────────────────────────────
  # Outline typically runs behind a reverse proxy (Traefik/nginx)
  # Only open the proxy port, not Outline directly
  # networking.firewall.allowedTCPPorts = [ 443 80 ];

  # ── Backup hint ──────────────────────────────────────────────────
  # Outline stores data in PostgreSQL + S3/MinIO.
  # Ensure both are included in your backup strategy.
  # See docs/backup.md for details.
}
