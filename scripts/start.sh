#!/usr/bin/env bash
# Start subgraph-mcp + mcp-front natively (no Docker).
# Secrets come from env vars (Pinata injects them) or from mcp-local-docker/.env.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/mcp-local-docker/.env"

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# Load .env if present (local dev); Pinata injects secrets as env vars directly.
if [ -f "$ENV_FILE" ]; then
  set -o allexport; source "$ENV_FILE"; set +o allexport
  echo "Loaded env from $ENV_FILE"
fi

# --- Preflight ---
if ! command -v subgraph-mcp >/dev/null 2>&1; then
  echo "ERROR: subgraph-mcp not found. Run scripts/build.sh first." >&2
  exit 1
fi
if [ -z "${GATEWAY_API_KEY:-}" ]; then
  echo "ERROR: GATEWAY_API_KEY is not set." >&2
  exit 1
fi

# --- Start subgraph-mcp (port 8000) ---
echo "Starting subgraph-mcp on :8000..."
GATEWAY_API_KEY="${GATEWAY_API_KEY}" RUST_LOG="${RUST_LOG:-info}" \
  subgraph-mcp --sse &
MCP_PID=$!

# Wait for MCP to accept connections
for i in $(seq 1 30); do
  if curl -fsS http://localhost:8000/sse >/dev/null 2>&1; then
    echo "subgraph-mcp ready (PID $MCP_PID)"
    break
  fi
  [ "$i" -eq 30 ] && echo "WARNING: subgraph-mcp not responding after 60s"
  sleep 2
done

# --- Start mcp-front (port 8080) ---
echo "Starting mcp-front on :8080..."
export MCP_HOST="http://localhost:8000"
cd "$ROOT_DIR/mcp-local-docker/mcp-front"
node server.js &
APP_PID=$!
echo "mcp-front started (PID $APP_PID)"

# Keep the script alive so Pinata sees a running process.
cleanup() {
  echo "Shutting down..."
  kill "$MCP_PID" "$APP_PID" 2>/dev/null || true
  wait
}
trap cleanup EXIT INT TERM

wait
