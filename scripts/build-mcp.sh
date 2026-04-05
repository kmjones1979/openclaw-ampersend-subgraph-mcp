#!/usr/bin/env bash
# Heavy build: Rust toolchain + subgraph-mcp binary.
# Run this AFTER the agent is online — it takes ~10-20 min on first run.
# Safe to re-run; skips steps that are already done.
set -euo pipefail

echo "=== Building subgraph-mcp (native) ==="

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

export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"

# --- Build subgraph-mcp from source ---
SUBGRAPH_BIN="$HOME/.local/bin/subgraph-mcp"
if [ -x "$SUBGRAPH_BIN" ]; then
  echo "subgraph-mcp: already built at $SUBGRAPH_BIN"
else
  echo "Cloning and compiling subgraph-mcp (this takes a while)..."
  BUILD_DIR=$(mktemp -d)
  git clone --depth 1 https://github.com/graphops/subgraph-mcp.git "$BUILD_DIR"
  # --jobs 1: compile one crate at a time to stay under memory limits on
  # constrained containers (Pinata Agents, CI). Slower but won't OOM.
  (cd "$BUILD_DIR" && cargo build --release --jobs 1)
  mkdir -p "$HOME/.local/bin"
  cp "$BUILD_DIR/target/release/subgraph-mcp" "$SUBGRAPH_BIN"
  chmod +x "$SUBGRAPH_BIN"
  rm -rf "$BUILD_DIR"
  echo "subgraph-mcp: installed to $SUBGRAPH_BIN"
fi

echo "=== subgraph-mcp build complete ==="
echo "Start the services with: bash scripts/start.sh"
