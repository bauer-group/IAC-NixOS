# modules/services/monitoring.nix
# ─────────────────────────────────────────────────────────────────────
# Prometheus + Grafana monitoring stack.
# Enable via: bauergroup.services.monitoring.enable = true;
#
# Deploy on ONE server (typically prod-server-01) to scrape all hosts.
# Enable node exporter on ALL servers via bauergroup.services.monitoring.exporterOnly.
# The node exporter port is only reachable from nodeExporterAllowedSources.
# The full stack requires grafanaSecretKeyFile and grafanaAdminPasswordFile
# (see docs/secrets.md). Grafana listens on localhost only by default.
# Grafana makes no outbound connections; add plugins via
# services.grafana.declarativePlugins instead of downloads from grafana.com.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  config,
  ...
}:
let
  cfg = config.bauergroup.services.monitoring;

  # iptables and ip6tables need separate rules: ip6tables rejects IPv4 CIDRs
  # and firewall-start aborts on the first failing command
  isIPv6 = lib.hasInfix ":";
  ipv4Sources = lib.filter (source: !isIPv6 source) cfg.nodeExporterAllowedSources;
  ipv6Sources = lib.filter isIPv6 cfg.nodeExporterAllowedSources;
  exporterPort = toString cfg.nodeExporterPort;

  iptablesRule =
    command: source:
    "${command} -w -A nixos-fw -p tcp -s ${source} --dport ${exporterPort} -j nixos-fw-accept\n";
  nftablesRule =
    family: sources:
    lib.optionalString (
      sources != [ ]
    ) "${family} saddr { ${lib.concatStringsSep ", " sources} } tcp dport ${exporterPort} accept\n";
in
{
  options.bauergroup.services.monitoring = {
    enable = lib.mkEnableOption "Full monitoring stack (Prometheus + Grafana)";

    exporterOnly = lib.mkEnableOption "Only run node exporter (for scraped hosts)";

    grafanaPort = lib.mkOption {
      type = lib.types.port;
      default = 3100;
      description = "Port for Grafana web UI.";
    };

    grafanaListenAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = ''
        Address Grafana listens on. The default keeps it reachable only through a
        reverse proxy or an SSH tunnel. Grafana serves plain HTTP, so a non-loopback
        address also needs a firewall rule of your own (e.g. network.openPorts).
      '';
    };

    grafanaAdminPasswordFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path on the target machine to the file holding the Grafana admin password
        (e.g. an agenix secret). The file may stay root-only; it is passed to Grafana
        as a systemd credential. Grafana applies it only when it creates the admin
        user on first start; change an existing password with
        `grafana cli admin reset-admin-password`.
      '';
      example = "/run/agenix/grafana-admin-password";
    };

    grafanaSecretKeyFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path on the target machine to the file holding Grafana's secret key
        (e.g. an agenix secret or a file placed during deployment). Grafana
        encrypts data source and alerting credentials with it. The file may stay
        root-only; it is passed to Grafana as a systemd credential.
        Generate with: head -c 32 /dev/urandom | base64
      '';
      example = "/run/agenix/grafana-secret-key";
    };

    prometheusPort = lib.mkOption {
      type = lib.types.port;
      default = 9090;
      description = "Port for Prometheus.";
    };

    nodeExporterPort = lib.mkOption {
      type = lib.types.port;
      default = 9100;
      description = "Port for Prometheus node exporter.";
    };

    nodeExporterAllowedSources = lib.mkOption {
      # Validated here because the entries end up in the firewall script, which
      # aborts on the first bad rule and would leave the host without a firewall
      type = lib.types.listOf (
        lib.types.strMatching "([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?|[0-9a-fA-F:]*:[0-9a-fA-F:.]*(/[0-9]{1,3})?"
      );
      default = [ ];
      description = ''
        IPv4/IPv6 addresses or CIDRs (no hostnames) allowed to reach the node exporter, typically the
        monitoring server. The exporter serves unauthenticated host metrics, so its
        port stays closed when this is empty; local scrapes via localhost still work.
      '';
      example = [
        "10.0.0.10/32"
        "fd00::10/128"
      ];
    };

    scrapeTargets = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "localhost:9100" ];
      description = "List of host:port targets for Prometheus to scrape.";
      example = [
        "prod-server-01:9100"
        "prod-server-02:9100"
      ];
    };

    alertRules = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [
        {
          alert = "HighDiskUsage";
          expr = ''(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"}) * 100 < 15'';
          for = "5m";
          labels.severity = "warning";
          annotations.summary = "Disk usage above 85% on {{ $labels.instance }}";
        }
        {
          alert = "HighMemoryUsage";
          expr = "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 > 90";
          for = "5m";
          labels.severity = "warning";
          annotations.summary = "Memory usage above 90% on {{ $labels.instance }}";
        }
        {
          alert = "HighCPULoad";
          expr = "100 - (avg by(instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100) > 80";
          for = "10m";
          labels.severity = "warning";
          annotations.summary = "CPU usage above 80% for 10 minutes on {{ $labels.instance }}";
        }
        {
          alert = "SystemdServiceFailed";
          expr = "node_systemd_unit_state{state=\"failed\"} == 1";
          for = "1m";
          labels.severity = "critical";
          annotations.summary = "Service {{ $labels.name }} failed on {{ $labels.instance }}";
        }
        {
          alert = "NodeDown";
          expr = "up == 0";
          for = "2m";
          labels.severity = "critical";
          annotations.summary = "Node {{ $labels.instance }} is unreachable";
        }
      ];
      description = "Prometheus alert rules.";
    };
  };

  config = lib.mkMerge [
    # Node exporter — runs on every monitored host
    (lib.mkIf (cfg.enable || cfg.exporterOnly) {
      services.prometheus.exporters.node = {
        enable = true;
        port = cfg.nodeExporterPort;
        enabledCollectors = [
          "systemd"
          "processes"
          "filesystem"
          "diskstats"
          "netdev"
          "meminfo"
          "loadavg"
        ];
      };

      # Source-restricted rules instead of allowedTCPPorts, which would
      # accept every source before these rules are reached
      networking.firewall.extraCommands = lib.mkIf (!config.networking.nftables.enable) (
        lib.concatMapStrings (iptablesRule "iptables") ipv4Sources
        + lib.optionalString config.networking.enableIPv6 (
          lib.concatMapStrings (iptablesRule "ip6tables") ipv6Sources
        )
      );
      networking.firewall.extraInputRules = lib.mkIf config.networking.nftables.enable (
        nftablesRule "ip" ipv4Sources + nftablesRule "ip6" ipv6Sources
      );

      assertions = [
        {
          assertion =
            config.networking.firewall.backend != "firewalld" || cfg.nodeExporterAllowedSources == [ ];
          message = "bauergroup.services.monitoring.nodeExporterAllowedSources supports the iptables and nftables firewall backends only.";
        }
      ];
    })

    # Full stack — only on the monitoring server
    (lib.mkIf cfg.enable {
      services.prometheus = {
        enable = true;
        port = cfg.prometheusPort;
        retentionTime = "30d";

        scrapeConfigs = [
          {
            job_name = "node";
            scrape_interval = "15s";
            static_configs = [
              { targets = cfg.scrapeTargets; }
            ];
          }
        ];

        rules = [
          (builtins.toJSON {
            groups = [
              {
                name = "bauergroup-alerts";
                rules = cfg.alertRules;
              }
            ];
          })
        ];
      };

      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_port = cfg.grafanaPort;
            http_addr = cfg.grafanaListenAddress;
          };
          security = {
            admin_user = "admin";
            # Expanded by Grafana at startup from the credentials loaded below
            admin_password = "$__file{/run/credentials/grafana.service/admin_password}";
            secret_key = "$__file{/run/credentials/grafana.service/secret_key}";
            # Browsers would otherwise load avatars (email hashes) from gravatar.com
            disable_gravatar = true;
          };

          # No outbound connections: set explicitly, independent of NixOS defaults
          analytics = {
            reporting_enabled = false;
            check_for_updates = false;
            check_for_plugin_updates = false;
          };
          plugins = {
            preinstall_disabled = true;
            # Verify plugin signatures with the key built into Grafana
            public_key_retrieval_disabled = true;
          };
          news.news_feed_enabled = false;
          snapshots.external_enabled = false;
        };

        provision = {
          datasources.settings.datasources = [
            {
              name = "Prometheus";
              type = "prometheus";
              url = "http://localhost:${toString cfg.prometheusPort}";
              isDefault = true;
            }
          ];
        };
      };

      systemd.services.grafana = {
        # systemd reads the files as root, so the sources can stay root-only.
        # toString keeps a path literal from being copied into the Nix store.
        serviceConfig.LoadCredential = [
          "secret_key:${toString cfg.grafanaSecretKeyFile}"
          "admin_password:${toString cfg.grafanaAdminPasswordFile}"
        ];

        # Grafana starts silently with an empty key or password, so refuse that here
        preStart = lib.mkBefore ''
          if ! grep -q '[^[:space:]]' "$CREDENTIALS_DIRECTORY/secret_key"; then
            echo "Grafana secret key ${toString cfg.grafanaSecretKeyFile} is empty" >&2
            exit 1
          fi
          if ! grep -q '[^[:space:]]' "$CREDENTIALS_DIRECTORY/admin_password"; then
            echo "Grafana admin password ${toString cfg.grafanaAdminPasswordFile} is empty" >&2
            exit 1
          fi
        '';
      };
    })
  ];
}
