# modules/params.nix
# ─────────────────────────────────────────────────────────────────────
# Defines all parameters that customize a template for a specific machine.
# Each target machine provides values via /etc/nixos/params.nix
#
# Usage on target machine:
#   Create /etc/nixos/params.nix with your values, then:
#   nixos-rebuild switch --flake .#server --impure
#
# See params.example.nix in the repo root for a full reference.
# ─────────────────────────────────────────────────────────────────────
{ lib, ... }:
{
  options.bauergroup.params = {
    # ── Identity ──────────────────────────────────────────────────────
    hostName = lib.mkOption {
      type = lib.types.str;
      description = "Hostname for this machine.";
      example = "kiosk-lobby-01";
    };

    # ── User ──────────────────────────────────────────────────────────
    user = {
      name = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Primary user account name.";
      };

      fullName = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Full name for display and git config.";
      };

      email = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "Email address for git config.";
      };

      sshKeys = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "SSH public keys for authorized login.";
        example = [ "ssh-ed25519 AAAAC3Nza... user@host" ];
      };

      hashedPassword = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Hashed password (mkpasswd -m sha-512). If null, only SSH login works.";
      };

      extraGroups = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Additional groups beyond the template defaults.";
      };
    };

    # ── Network ───────────────────────────────────────────────────────
    network = {
      useDHCP = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Use DHCP for network configuration. Set to false for static IP.";
      };

      interface = lib.mkOption {
        type = lib.types.str;
        default = "eth0";
        description = "Primary network interface (only used with static IP).";
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Static IPv4 address (only used when useDHCP = false).";
        example = "10.0.0.5";
      };

      prefixLength = lib.mkOption {
        type = lib.types.int;
        default = 24;
        description = "Network prefix length (subnet mask).";
      };

      gateway = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Default gateway (only used when useDHCP = false).";
        example = "10.0.0.1";
      };

      nameservers = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [
          "1.1.1.1"
          "8.8.8.8"
        ];
        description = "DNS servers.";
      };

      openPorts = lib.mkOption {
        type = lib.types.listOf lib.types.port;
        default = [ ];
        description = "Additional TCP ports to open in the firewall.";
        example = [
          80
          443
        ];
      };
    };

    # ── Boot ──────────────────────────────────────────────────────────
    boot = {
      loader = lib.mkOption {
        type = lib.types.enum [
          "systemd-boot"
          "grub"
        ];
        default = "systemd-boot";
        description = "Boot loader to use. systemd-boot for EFI, grub for BIOS/legacy.";
      };

      grubDevice = lib.mkOption {
        type = lib.types.str;
        default = "/dev/sda";
        description = "Disk device for GRUB installation (only used with grub loader).";
      };
    };

    # ── Locale ────────────────────────────────────────────────────────
    timezone = lib.mkOption {
      type = lib.types.str;
      default = "Europe/Berlin";
      description = "System timezone.";
    };

    locale = lib.mkOption {
      type = lib.types.str;
      default = "en_US.UTF-8";
      description = "System locale.";
    };

    keymap = lib.mkOption {
      type = lib.types.str;
      default = "de-latin1";
      description = "Console keyboard layout.";
    };

    xkbLayout = lib.mkOption {
      type = lib.types.str;
      default = "de";
      description = "X11/Wayland keyboard layout.";
    };

    # ── Kiosk-specific ────────────────────────────────────────────────
    kiosk = {
      url = lib.mkOption {
        type = lib.types.str;
        default = "http://localhost:3000";
        description = "URL to display in kiosk mode.";
      };

      composeFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Path to docker-compose.yml for kiosk backend services.";
      };

      composeDirectory = lib.mkOption {
        type = lib.types.str;
        default = "/opt/kiosk";
        description = "Working directory for Docker Compose backend.";
      };

      touchscreen = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable touchscreen support for kiosk.";
      };

      rotation = lib.mkOption {
        type = lib.types.enum [
          "normal"
          "left"
          "right"
          "inverted"
        ];
        default = "normal";
        description = "Screen rotation for kiosk display.";
      };

      idleTimeout = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        description = "Seconds of inactivity before resetting browser to home URL. Null = disabled.";
      };
    };

    # ── Server-specific ───────────────────────────────────────────────
    server = {
      composeProjects = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              directory = lib.mkOption {
                type = lib.types.str;
                description = "Directory containing docker-compose.yml.";
              };
              envFile = lib.mkOption {
                type = lib.types.nullOr lib.types.path;
                default = null;
                description = "Path to .env file (e.g. from agenix).";
              };
            };
          }
        );
        default = { };
        description = "Docker Compose projects to run as systemd services.";
        example = {
          outline = {
            directory = "/opt/outline";
          };
          traefik = {
            directory = "/opt/traefik";
          };
        };
      };

      monitoring = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Prometheus node exporter for monitoring.";
      };

      backup = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Enable automated restic backups.";
        };

        repository = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Restic repository URL.";
          example = "sftp:backup@storage:/backups/hostname";
        };

        passwordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.path;
          default = null;
          description = "Path to restic repository password file.";
        };

        paths = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "/opt"
            "/var/lib"
            "/home"
          ];
          description = "Paths to back up.";
        };
      };
    };

    # ── Auto-Update ────────────────────────────────────────────────────
    autoUpdate = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Automatically pull latest config from Git and rebuild daily.";
      };

      flake = lib.mkOption {
        type = lib.types.str;
        default = "github:bauer-group/IAC-NixOS";
        description = "Flake URI to pull updates from.";
      };

      schedule = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Time to check for updates (24h format).";
      };

      allowReboot = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow automatic reboot when kernel or critical services change.";
      };

      rebootWindowStart = lib.mkOption {
        type = lib.types.str;
        default = "03:00";
        description = "Earliest time for automatic reboot.";
      };

      rebootWindowEnd = lib.mkOption {
        type = lib.types.str;
        default = "03:30";
        description = "Latest time for automatic reboot.";
      };
    };

    # ── Development-specific ──────────────────────────────────────────
    dev = {
      embeddedDev = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Enable CAN-Bus / embedded development tools and kernel modules.";
      };

      extraPackages = lib.mkOption {
        type = lib.types.listOf lib.types.package;
        default = [ ];
        description = "Additional packages to install on development desktop.";
      };
    };
  };
}
