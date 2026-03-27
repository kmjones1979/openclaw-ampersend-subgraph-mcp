#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/root/.openclaw/workspace/mcp-local-docker"
ENV_FILE="$ROOT_DIR/.env"

if [ ! -d "$ROOT_DIR" ]; then
  echo "ERROR: Stack directory not found at $ROOT_DIR"
  exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: No .env file found at $ENV_FILE"
  echo "Copy .env.example and fill in your credentials:"
  echo "  cp $ROOT_DIR/.env.example $ENV_FILE"
  exit 1
fi

set -o allexport
source "$ENV_FILE"
set +o allexport

# Validate required vars
for VAR in GATEWAY_API_KEY PAY_TO_ADDRESS CDP_APP_ID CDP_SECRET; do
  if [ -z "${!VAR:-}" ]; then
    echo "ERROR: $VAR is not set in $ENV_FILE"
    exit 1
  fi
done

cd "$ROOT_DIR"

echo "=== Building and starting stack ==="
docker compose up -d --build

echo "=== Waiting for services ==="
for i in $(seq 1 30); do
  curl -fsS "http://localhost:8000/graphql" >/dev/null 2>&1 && echo "MCP server ready" && break
  [ "$i" -eq 30 ] && echo "WARNING: MCP server not responding" && break
  sleep 2
done

for i in $(seq 1 15); do
  curl -fsS "http://localhost:8080/sse" >/dev/null 2>&1 && echo "x402 proxy ready" && break
  sleep 2
done

echo "=== Testing ==="

echo "SSE session:"
timeout 3 curl -sN http://localhost:8080/sse 2>/dev/null | head -2 || echo "(timeout - ok for SSE)"

echo
echo "Paid endpoint (no payment, expect 402):"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:8080/messages?sessionId=test" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
echo "HTTP $HTTP_CODE"

echo
echo "=== Logs ==="
docker compose logs --tail 10 2>/dev/null | grep -v "level=warning"

echo
echo "Done. Endpoints:"
echo "  SSE:  http://localhost:8080/sse"
echo "  MCP:  http://localhost:8080/messages"
echo "  Teardown: cd $ROOT_DIR && docker compose down"
