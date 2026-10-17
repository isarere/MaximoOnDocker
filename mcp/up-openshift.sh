#!/usr/bin/env bash
# Keep cluster forwards alive for the duration of the local MCP session.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f mcp/.local/compose.env ]]; then
  echo "Run python3 mcp/prepare.py first." >&2
  exit 1
fi
pids=()
cleanup() {
  docker compose --env-file mcp/.local/compose.env -f docker-compose.mcp.openshift stop mcp >/dev/null 2>&1 || true
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
}
trap cleanup EXIT
trap 'exit 130' INT TERM
forward() {
  local namespace="$1" service="$2" port="$3"
  # Colima's host.lima.internal cannot reach a Mac loopback-only listener.
  oc port-forward --address 0.0.0.0 -n "$namespace" "service/$service" "$port:443" \
    >"mcp/.local/forward-$port.log" 2>&1 &
  pids+=("$!")
}
forward mas-adp-manage adp-mas-integration 18443
forward mas-adp-core internalapi 18444
forward mas-adp-core coreidp 18445
for attempt in {1..30}; do
  ready=true
  for port in 18443 18444 18445; do
    if ! nc -z 127.0.0.1 "$port"; then ready=false; fi
  done
  for pid in "${pids[@]}"; do
    if ! kill -0 "$pid" 2>/dev/null; then
      echo "A cluster tunnel failed; see mcp/.local/forward-*.log." >&2
      exit 1
    fi
  done
  if [[ "$ready" == true ]]; then break; fi
  sleep 1
done
if [[ "$ready" != true ]]; then
  echo "Timed out waiting for cluster tunnels." >&2
  exit 1
fi
echo "MCP: https://localhost:9443/mcp — Ctrl-C stops MCP and the tunnels."
docker compose --env-file mcp/.local/compose.env -f docker-compose.mcp.openshift up
