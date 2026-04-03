#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/mcp-local-docker"
cd "$ROOT_DIR"

# Ensure env exists
ENV_FILE="$ROOT_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<EOF
GATEWAY_API_KEY=
AMPERSEND_API_KEY=
AMPERSEND_API_URL=https://api.ampersend.ai
EOF
  echo "Created $ENV_FILE with placeholders. Edit before running tests."
fi

# Start stack
echo "Starting MCP stack (docker-compose) ..."
docker-compose up -d

# Wait helper
wait_for_http() {
  local url="$1"; local retries="$2"; local i=0
  while [ $i -lt "$retries" ]; do
    if curl -fsS "$url" >/dev/null 2>&1; then echo "Ready: $url"; return 0; fi; i=$((i+1)); sleep 2; done
  echo "Timed out waiting for $url"; return 1
}

wait_for_http http://localhost:8000/graphql 60

echo "=== Test MCP schema (GraphQL) ==="
RESP_MCP=$(curl -sS -X POST http://localhost:8000/graphql -H "Content-Type: application/json" -d '{"query":"{ __schema { types { name } } }"}')
echo "MCP /graphql response:"
echo "$RESP_MCP"
echo

echo "=== Test Ampersend-front with token (paid) ==="
PAYLOAD_TOKEN='{"query":"{ __schema { types { name } } }", "ampersend": {"token":"test-token","amount":1000000}}'
RESP_APP_TOKEN=$(curl -sS -X POST http://localhost:8080/query -H "Content-Type: application/json" -d "$PAYLOAD_TOKEN")
echo "APP /query with token response:"
echo "$RESP_APP_TOKEN"
echo

echo "=== Test Ampersend-front without token (expected 402 or placeholder) ==="
RESP_APP_NO_TOKEN=$(curl -sS -X POST http://localhost:8080/query -H "Content-Type: application/json" -d '{"query":"{ __schema { types { name } } }"}')
echo "APP /query without token response:"
echo "$RESP_APP_NO_TOKEN"
echo

echo "=== Logs (last 80 lines) ==="
docker-compose logs mcp | tail -n 80
docker-compose logs app | tail -n 80
echo

echo "Done. To tear down: docker-compose down"
