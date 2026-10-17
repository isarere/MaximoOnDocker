#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -f mcp/.local/local-api.env || ! -f mcp/.local/local-tls/tls.crt ]]; then
  echo "Run python3 mcp/prepare.py --local and set MAXIMO_API_KEY in mcp/.local/local-api.env." >&2
  exit 1
fi
echo "MCP: https://localhost:9443/mcp — backend: local Maximo at http://localhost:9080/maximo/api"
docker compose -f docker-compose.mcp up
