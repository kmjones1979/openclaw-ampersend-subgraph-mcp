#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/root/.openclaw/workspace/mcp-local-docker"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -d "$ROOT_DIR" ]; then
  echo "ERROR: Stack directory not found at $ROOT_DIR"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  cat > "$ENV_FILE" <<EOF
GATEWAY_API_KEY=
AMPERSEND_API_KEY=
AMPERSEND_API_URL=https://api.ampersend.ai
EOF
  echo "Created $ENV_FILE with placeholders. Edit them before running."
fi
set -o allexport
source "$ENV_FILE"
set +o allexport

cd "$ROOT_DIR"
docker-compose up -d

wait_for_http() {
  local url="$1"; local retries="$2"; local i=0
  while [ $i -lt "$retries" ]; do
    if curl -fsS "$url" >/dev/null 2>&1; then echo "✔ Ready: $url"; return 0; fi; i=$((i+1)); sleep 2; done
  echo "✖ Timed out waiting for $url"; return 1
}
wait_for_http http://localhost:8000/graphql 60

RESP_MCP=$(curl -sS -X POST http://localhost:8000/graphql -H "Content-Type: application/json" -d '{"query":"{ __schema { types { name } } }"}')
echo "MCP response:"
echo "$RESP_MCP"

PAYLOAD_TOKEN='{"query":"{ __schema { types { name } } }", "ampersend": {"token":"test-token","amount":1000000}}'
RESP_APP_TOKEN=$(curl -sS -X POST http://localhost:8080/query -H "Content-Type: application/json" -d "$PAYLOAD_TOKEN")
echo "APP /query with token response:"
echo "$RESP_APP_TOKEN"

RESP_APP_NO_TOKEN=$(curl -sS -X POST http://localhost:8080/query -H "Content-Type: application/json" -d '{"query":"{ __schema { types { name } } }"}')
echo "APP /query without token response:"
echo "$RESP_APP_NO_TOKEN"

LOGS_MCP=$(docker-compose logs mcp | tail -n 80)
LOGS_APP=$(docker-compose logs app | tail -n 80)
echo "$LOGS_MCP\n$LOGS_APP"

