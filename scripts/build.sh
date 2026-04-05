#!/usr/bin/env bash
# Lightweight build: ampersend CLI + mcp-front Node deps.
# Rust/subgraph-mcp is handled separately by build-mcp.sh (run after boot).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=== Build (lightweight) ==="

# --- ampersend CLI ---
echo "Installing ampersend CLI..."
npm install -g @ampersend_ai/ampersend-sdk@0.0.16

# --- mcp-front Node.js deps ---
if [ -f "$ROOT_DIR/mcp-local-docker/mcp-front/package.json" ]; then
  echo "Installing mcp-front dependencies..."
  cd "$ROOT_DIR/mcp-local-docker/mcp-front"
  if command -v pnpm >/dev/null 2>&1; then
    pnpm install
  else
    npm install
  fi
  # Symlink the global ampersend-sdk into mcp-front so ESM import() finds it
  # without adding the heavy wagmi/walletconnect tree to the local install.
  echo "Linking ampersend-sdk from global install..."
  npm link @ampersend_ai/ampersend-sdk 2>/dev/null || echo "  (link skipped — SDK not globally installed yet)"
fi

echo "=== Build complete ==="
echo "Run 'bash scripts/build-mcp.sh' after boot to compile subgraph-mcp (takes ~10 min)."
