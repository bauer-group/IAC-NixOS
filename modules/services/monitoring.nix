# modules/services/monitoring.nix
# ─────────────────────────────────────────────────────────────────────
# Prometheus + Grafana monitoring stack.
# Enable via: bauergroup.services.monitoring.enable = true;
#
# Deploy on ONE server (typically prod-server-01) to scrape all hosts.
# Enable node exporter on ALL servers via bauergroup.services.monitoring.exporterOnly.
# ─────────────────────────────────────────────────────────────────────
{
  lib,
  config,
  ...
}:
let
  cfg = config.bauergroup.services.monitoring;
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
      networking.firewall.allowedTCPPorts = [ cfg.nodeExporterPort ];
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
            http_addr = "0.0.0.0";
          };
          # Default admin credentials — change on first login or use agenix
          security = {
            admin_user = "admin";
            admin_password = "admin";
          };
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

      networking.firewall.allowedTCPPorts = [
        cfg.grafanaPort
      ];
    })
  ];
}
