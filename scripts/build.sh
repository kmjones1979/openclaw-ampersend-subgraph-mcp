#!/usr/bin/env bash
# Native build: Rust toolchain, subgraph-mcp binary, mcp-front deps, ampersend CLI.
# Designed for environments without Docker/root (e.g. Pinata Agents).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Native build ==="

# --- ampersend CLI ---
echo "Installing ampersend CLI..."
npm install -g @ampersend_ai/ampersend-sdk@0.0.16

# --- Rust toolchain (user-level, no root needed) ---
if command -v cargo >/dev/null 2>&1; then
  echo "Rust: $(cargo --version)"
else
  echo "Installing Rust via rustup..."
  curl https://sh.rustup.rs -sSf | sh -s -- -y
  # shellcheck source=/dev/null
  source "$HOME/.cargo/env"
  echo "Rust: $(cargo --version)"
fi

# --- Build subgraph-mcp from source ---
SUBGRAPH_BIN="$HOME/.local/bin/subgraph-mcp"
if [ -x "$SUBGRAPH_BIN" ]; then
  echo "subgraph-mcp: already built at $SUBGRAPH_BIN"
else
  echo "Building subgraph-mcp from source..."
  BUILD_DIR=$(mktemp -d)
  git clone --depth 1 https://github.com/graphops/subgraph-mcp.git "$BUILD_DIR"
  (cd "$BUILD_DIR" && cargo build --release)
  mkdir -p "$HOME/.local/bin"
  cp "$BUILD_DIR/target/release/subgraph-mcp" "$SUBGRAPH_BIN"
  chmod +x "$SUBGRAPH_BIN"
  rm -rf "$BUILD_DIR"
  echo "subgraph-mcp: installed to $SUBGRAPH_BIN"
fi

# --- mcp-front Node.js deps ---
echo "Installing mcp-front dependencies..."
cd "$ROOT_DIR/mcp-local-docker/mcp-front"
if command -v pnpm >/dev/null 2>&1; then
  pnpm install
else
  npm install
fi

echo
echo "=== Build complete ==="
echo "  subgraph-mcp: $SUBGRAPH_BIN"
echo "  mcp-front:    $ROOT_DIR/mcp-local-docker/mcp-front"
echo "  ampersend:    $(command -v ampersend 2>/dev/null || echo 'not on PATH')"
