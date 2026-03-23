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

# ── Docker ────────────────────────────────────
echo ""
echo "Docker:"
if ssh "root@${HOST}" "systemctl is-active docker.service" >/dev/null 2>&1; then
  check "Docker running" "docker info > /dev/null 2>&1"
  CONTAINERS=$(ssh "root@${HOST}" "docker ps -q 2>/dev/null | wc -l" 2>/dev/null || echo "0")
  echo -e "  Containers running: ${CONTAINERS}"
else
  echo -e "  ${YELLOW}-${NC} Docker not enabled on this host"
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
