#!/usr/bin/env bash
# Start subgraph-mcp + mcp-front natively (no Docker).
# Secrets come from env vars (Pinata injects them) or from mcp-local-docker/.env.
#
# This script must stay alive — Pinata treats its exit as "agent down."
# If the MCP services can't start (missing binary, missing secrets), log a
# warning and keep the process running so the agent remains reachable.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/mcp-local-docker/.env"

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# Load .env if present (local dev); Pinata injects secrets as env vars directly.
if [ -f "$ENV_FILE" ]; then
  set -o allexport; source "$ENV_FILE"; set +o allexport
  echo "Loaded env from $ENV_FILE"
fi

MCP_PID=""
APP_PID=""

cleanup() {
  echo "Shutting down..."
  [ -n "$MCP_PID" ] && kill "$MCP_PID" 2>/dev/null
  [ -n "$APP_PID" ] && kill "$APP_PID" 2>/dev/null
  wait 2>/dev/null
}
trap cleanup EXIT INT TERM

# --- Try to start subgraph-mcp (port 8000) ---
if ! command -v subgraph-mcp >/dev/null 2>&1; then
  echo "WARNING: subgraph-mcp binary not found. Run scripts/build.sh first."
  echo "The agent will stay online but the MCP server won't be available."
elif [ -z "${GATEWAY_API_KEY:-}" ]; then
  echo "WARNING: GATEWAY_API_KEY is not set. Skipping subgraph-mcp."
  echo "Set it in the Pinata dashboard under Secrets."
else
  echo "Starting subgraph-mcp on :8000..."
  GATEWAY_API_KEY="${GATEWAY_API_KEY}" RUST_LOG="${RUST_LOG:-info}" \
    subgraph-mcp --sse &
  MCP_PID=$!

  for i in $(seq 1 30); do
    if curl -fsS http://localhost:8000/sse >/dev/null 2>&1; then
      echo "subgraph-mcp ready (PID $MCP_PID)"
      break
    fi
    [ "$i" -eq 30 ] && echo "WARNING: subgraph-mcp not responding after 60s"
    sleep 2
  done
fi

# --- Try to start mcp-front (port 8080) ---
if [ -n "$MCP_PID" ] && [ -f "$ROOT_DIR/mcp-local-docker/mcp-front/server.js" ]; then
  echo "Starting mcp-front on :8080..."
  export MCP_HOST="http://localhost:8000"
  cd "$ROOT_DIR/mcp-local-docker/mcp-front"
  node server.js &
  APP_PID=$!
  echo "mcp-front started (PID $APP_PID)"
elif [ -z "$MCP_PID" ]; then
  echo "Skipping mcp-front (subgraph-mcp not running)."
else
  echo "WARNING: mcp-front/server.js not found."
fi

echo "=== start.sh: staying alive ==="

# Keep the script running indefinitely so Pinata sees a live process.
# If child processes exist, wait on them; otherwise just sleep.
while true; do
  if [ -n "$MCP_PID" ] || [ -n "$APP_PID" ]; then
    wait -n 2>/dev/null || true
    # A child exited — check which one and log it
    if [ -n "$MCP_PID" ] && ! kill -0 "$MCP_PID" 2>/dev/null; then
      echo "WARNING: subgraph-mcp (PID $MCP_PID) exited unexpectedly"
      MCP_PID=""
    fi
    if [ -n "$APP_PID" ] && ! kill -0 "$APP_PID" 2>/dev/null; then
      echo "WARNING: mcp-front (PID $APP_PID) exited unexpectedly"
      APP_PID=""
    fi
  fi
  sleep 30
done
