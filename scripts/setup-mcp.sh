#!/usr/bin/env bash
# One-command setup: build subgraph-mcp (if needed) + start both services.
# Secrets are expected as env vars (Pinata injects them) or from mcp-local-docker/.env.
# Safe to re-run — skips completed build steps and restarts services.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/mcp-local-docker/.env"

# Load .env only if env vars aren't already set (local dev fallback).
if [ -z "${GATEWAY_API_KEY:-}" ] && [ -f "$ENV_FILE" ]; then
  set -o allexport; source "$ENV_FILE"; set +o allexport
  echo "Loaded env from $ENV_FILE"
fi

# --- Preflight: check secrets ---
MISSING=""
[ -z "${GATEWAY_API_KEY:-}" ] && MISSING="$MISSING GATEWAY_API_KEY"
[ -z "${PAY_TO_ADDRESS:-}" ] && MISSING="$MISSING PAY_TO_ADDRESS"
[ -z "${CDP_APP_ID:-}" ] && MISSING="$MISSING CDP_APP_ID"
[ -z "${CDP_SECRET:-}" ] && MISSING="$MISSING CDP_SECRET"
if [ -n "$MISSING" ]; then
  echo "ERROR: Missing required env vars:$MISSING"
  echo "These should be set as Pinata Secrets or in mcp-local-docker/.env"
  exit 1
fi
echo "Secrets: all 4 required env vars present"

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# ========================
# Phase 1: Build (if needed)
# ========================

SUBGRAPH_BIN="$HOME/.local/bin/subgraph-mcp"
if [ -x "$SUBGRAPH_BIN" ]; then
  echo "subgraph-mcp: already built at $SUBGRAPH_BIN"
else
  echo "=== Building subgraph-mcp (this takes ~10-20 min on first run) ==="

  # Rust toolchain
  if command -v cargo >/dev/null 2>&1; then
    echo "Rust: $(cargo --version)"
  else
    echo "Installing Rust via rustup..."
    curl https://sh.rustup.rs -sSf | sh -s -- -y
    # shellcheck source=/dev/null
    source "$HOME/.cargo/env"
    export PATH="$HOME/.cargo/bin:$PATH"
    echo "Rust: $(cargo --version)"
  fi

  # Compile
  BUILD_DIR=$(mktemp -d)
  echo "Cloning graphops/subgraph-mcp..."
  git clone --depth 1 https://github.com/graphops/subgraph-mcp.git "$BUILD_DIR"
  echo "Compiling (release, --jobs 1 to avoid OOM on constrained containers)..."
  (cd "$BUILD_DIR" && cargo build --release --jobs 1)
  mkdir -p "$HOME/.local/bin"
  cp "$BUILD_DIR/target/release/subgraph-mcp" "$SUBGRAPH_BIN"
  chmod +x "$SUBGRAPH_BIN"
  rm -rf "$BUILD_DIR"
  echo "subgraph-mcp: installed to $SUBGRAPH_BIN"
fi

# ========================
# Phase 2: Install mcp-front deps (if needed)
# ========================

FRONT_DIR="$ROOT_DIR/mcp-local-docker/mcp-front"
if [ ! -d "$FRONT_DIR/node_modules" ]; then
  echo "Installing mcp-front Node.js deps..."
  cd "$FRONT_DIR"
  if command -v pnpm >/dev/null 2>&1; then
    pnpm install
  else
    npm install
  fi
else
  echo "mcp-front: node_modules present"
fi

# Symlink global ampersend-sdk into mcp-front (ESM import needs it local).
if [ ! -d "$FRONT_DIR/node_modules/@ampersend_ai/ampersend-sdk" ]; then
  echo "Linking ampersend-sdk from global install..."
  cd "$FRONT_DIR"
  npm link @ampersend_ai/ampersend-sdk 2>/dev/null || echo "  (link skipped — SDK not globally installed yet)"
fi

# ========================
# Phase 3: Start services
# ========================

echo "=== Starting services ==="

# Start subgraph-mcp on :8000
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

# Start mcp-front on :8080
echo "Starting mcp-front on :8080..."
export MCP_HOST="http://localhost:8000"
cd "$FRONT_DIR"
node server.js &
APP_PID=$!
echo "mcp-front started (PID $APP_PID)"

echo
echo "=== MCP stack running ==="
echo "  subgraph-mcp: http://localhost:8000 (PID $MCP_PID)"
echo "  x402 proxy:   http://localhost:8080 (PID $APP_PID)"
echo "  Payment:      \$${PRICE_PER_CALL:-0.01} USDC per call on ${X402_NETWORK:-eip155:8453}"
