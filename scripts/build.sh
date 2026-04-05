#!/usr/bin/env bash
# Pinata build script — runs after git push.
# Keep this lightweight so it finishes fast. Heavy work (Rust compile,
# mcp-front deps, npm link) happens in setup-mcp.sh after the agent boots.
set -euo pipefail

echo "=== Build ==="

echo "Installing ampersend CLI..."
npm install -g --force @ampersend_ai/ampersend-sdk@0.0.16

echo "=== Build complete ==="
