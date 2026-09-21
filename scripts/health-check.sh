#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# Post-deployment health check for NixOS servers.
# Usage: ./scripts/health-check.sh <hostname-or-ip>
#
# Run after `colmena apply` to verify the deployment was successful.
# Exit code 0 = all checks passed, non-zero = issues found.
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

HOST="${1:?Usage: health-check.sh <hostname-or-ip>}"
FAILURES=0

check() {
  local name="$1"
  shift
  if ssh "root@${HOST}" "$@" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} ${name}"
  else
    echo -e "  ${RED}✗${NC} ${name}"
    FAILURES=$((FAILURES + 1))
  fi
}

echo ""
echo "═══════════════════════════════════════════"
echo "  Health Check: ${HOST}"
echo "═══════════════════════════════════════════"

# ── System ────────────────────────────────────
echo ""
echo "System:"
VERSION=$(ssh "root@${HOST}" "nixos-version" 2>/dev/null || echo "unknown")
echo -e "  Version: ${VERSION}"
check "SSH reachable" "true"
check "System booted" "systemctl is-system-running --wait 2>/dev/null || systemctl is-system-running 2>/dev/null | grep -qE 'running|degraded'"

# ── Failed Services ──────────────────────────
echo ""
echo "Services:"
FAILED=$(ssh "root@${HOST}" "systemctl --failed --no-pager --no-legend 2>/dev/null | wc -l" 2>/dev/null || echo "?")
if [ "$FAILED" = "0" ]; then
  echo -e "  ${GREEN}✓${NC} No failed services"
else
  echo -e "  ${YELLOW}!${NC} ${FAILED} failed service(s):"
  ssh "root@${HOST}" "systemctl --failed --no-pager --no-legend" 2>/dev/null | sed 's/^/    /'
  FAILURES=$((FAILURES + 1))
fi

# ── Disk ──────────────────────────────────────
echo ""
echo "Disk:"
check "Root filesystem < 85% full" "test \$(df / --output=pcent | tail -1 | tr -d ' %') -lt 85"

# ── Containers ────────────────────────────────
# Both engines answer on /run/docker.sock, so probe the socket rather than a
# daemon unit: Podman is daemonless and has no docker.service to look for
echo ""
echo "Containers:"
if ssh "root@${HOST}" "test -S /run/docker.sock" >/dev/null 2>&1; then
  ENGINE=$(ssh "root@${HOST}" "docker version --format '{{.Server.Product}}' 2>/dev/null || echo unknown" 2>/dev/null)
  echo -e "  Engine: ${ENGINE}"
  check "Container engine responding" "docker info > /dev/null 2>&1"
  CONTAINERS=$(ssh "root@${HOST}" "docker ps -q 2>/dev/null | wc -l" 2>/dev/null || echo "0")
  echo -e "  Containers running: ${CONTAINERS}"
else
  echo -e "  ${YELLOW}-${NC} No container engine on this host"
fi

# ── Watchdog ──────────────────────────────────
# A panel with no /dev/watchdog has no automatic recovery at all, and that is
# invisible until the day it freezes — so surface it at deployment time
echo ""
echo "Watchdog:"
if ssh "root@${HOST}" "test -c /dev/watchdog" >/dev/null 2>&1; then
  WDINFO=$(ssh "root@${HOST}" "wdctl --noheadings --output=FLAG,DESCRIPTION 2>/dev/null | head -1 || true" 2>/dev/null)
  check "Hardware watchdog present" "test -c /dev/watchdog"
  [ -n "${WDINFO}" ] && echo -e "  ${WDINFO}"
else
  echo -e "  ${YELLOW}!${NC} No /dev/watchdog — this host cannot recover from a freeze"
  echo -e "    Name the driver in watchdog.kernelModules (iTCO_wdt, sp5100_tco, it87_wdt)"
fi

# ── Kiosk session ─────────────────────────────
echo ""
echo "Kiosk:"
# systemctl cat fails outright on an unknown unit, unlike list-unit-files,
# which happily exits 0 with an empty list
if ssh "root@${HOST}" "systemctl cat cage-tty1.service" >/dev/null 2>&1; then
  check "Kiosk session running" "systemctl is-active cage-tty1.service"
  RESTARTS=$(ssh "root@${HOST}" "systemctl show cage-tty1.service -p NRestarts --value 2>/dev/null" 2>/dev/null || echo "?")
  echo -e "  Session restarts since boot: ${RESTARTS}"
  if ssh "root@${HOST}" "systemctl is-active bauergroup-app-watchdog.timer" >/dev/null 2>&1; then
    echo -e "  ${GREEN}✓${NC} Freeze watchdog armed"
  else
    echo -e "  ${YELLOW}-${NC} Freeze watchdog not armed (no health probe configured)"
  fi
else
  echo -e "  ${YELLOW}-${NC} Not a kiosk host"
fi

# ── Network ───────────────────────────────────
echo ""
echo "Network:"
check "Firewall active" "systemctl is-active firewall.service"
check "DNS resolving" "host nixos.org > /dev/null 2>&1"

# ── Monitoring ────────────────────────────────
echo ""
echo "Monitoring:"
if ssh "root@${HOST}" "systemctl is-active prometheus-node-exporter.service" >/dev/null 2>&1; then
  check "Node exporter responding" "curl -sf http://localhost:9100/metrics > /dev/null"
else
  echo -e "  ${YELLOW}-${NC} Node exporter not enabled"
fi

# ── Summary ───────────────────────────────────
echo ""
echo "═══════════════════════════════════════════"
if [ "$FAILURES" -eq 0 ]; then
  echo -e "  ${GREEN}All checks passed${NC}"
else
  echo -e "  ${RED}${FAILURES} check(s) failed${NC}"
fi
echo "═══════════════════════════════════════════"
echo ""

exit "$FAILURES"
