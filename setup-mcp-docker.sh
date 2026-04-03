#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="${SCRIPT_DIR}/mcp-local-docker"
ENV_FILE="$ROOT_DIR/.env"

echo "============================================"
echo "  Subgraph MCP + x402 Payment Gateway Setup"
echo "============================================"
echo

# --- Check stack directory ---
if [ ! -d "$ROOT_DIR" ]; then
  echo "ERROR: Stack directory not found at $ROOT_DIR"
  exit 1
fi

# --- Install Docker if needed ---
if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
  [ -n "${SUDO_USER:-}" ] && sudo usermod -aG docker "$SUDO_USER"
else
  echo "Docker: installed"
fi

# --- Install Docker Compose if needed ---
if docker compose version >/dev/null 2>&1; then
  echo "Docker Compose: installed (plugin)"
  DC="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
  echo "Docker Compose: installed (standalone)"
  DC="docker-compose"
else
  echo "Installing docker-compose..."
  ARCH=$(uname -m)
  sudo curl -L "https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-${ARCH}" \
    -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
  DC="docker-compose"
fi

# --- Gather credentials ---
echo
echo "=== Configuration ==="
echo

if [ -f "$ENV_FILE" ]; then
  echo "Existing .env found at $ENV_FILE"
  echo "Do you want to (K)eep it or (R)econfigure? [K/R]"
  read -r CHOICE
  if [[ ! "$CHOICE" =~ ^[Rr]$ ]]; then
    echo "Keeping existing .env"
    set -o allexport; source "$ENV_FILE"; set +o allexport
  else
    RECONFIGURE=true
  fi
else
  RECONFIGURE=true
fi

if [ "${RECONFIGURE:-false}" = "true" ]; then
  echo
  echo "--- Required ---"
  echo
  read -rp "The Graph Gateway API Key: " GATEWAY_API_KEY
  read -rp "Pay-to wallet address (Base mainnet): " PAY_TO_ADDRESS
  echo
  echo "--- Coinbase CDP (for x402 payment facilitation) ---"
  echo "Create an app at https://portal.cdp.coinbase.com"
  echo "Generate an Ed25519 API key pair"
  echo
  read -rp "CDP App ID: " CDP_APP_ID
  read -rp "CDP Secret (base64 Ed25519 key): " CDP_SECRET
  echo
  echo "--- Optional (press Enter for defaults) ---"
  echo
  read -rp "x402 Network [eip155:8453]: " X402_NETWORK
  X402_NETWORK="${X402_NETWORK:-eip155:8453}"
  read -rp "Price per call in USD [0.01]: " PRICE_PER_CALL
  PRICE_PER_CALL="${PRICE_PER_CALL:-0.01}"

  cat > "$ENV_FILE" <<EOF
GATEWAY_API_KEY=${GATEWAY_API_KEY}
PAY_TO_ADDRESS=${PAY_TO_ADDRESS}
CDP_APP_ID=${CDP_APP_ID}
CDP_SECRET=${CDP_SECRET}
X402_NETWORK=${X402_NETWORK}
FACILITATOR_URL=https://api.cdp.coinbase.com/platform/v2/x402
PRICE_PER_CALL=${PRICE_PER_CALL}
EOF
  echo
  echo "Saved configuration to $ENV_FILE"

  set -o allexport; source "$ENV_FILE"; set +o allexport
fi

# --- Build and start ---
echo
echo "=== Starting stack ==="
cd "$ROOT_DIR"
$DC up -d --build

# --- Wait for MCP backend ---
echo
echo "=== Waiting for MCP server ==="
for i in $(seq 1 30); do
  if curl -fsS "http://localhost:8000/graphql" >/dev/null 2>&1; then
    echo "MCP server ready (port 8000)"
    break
  fi
  [ "$i" -eq 30 ] && echo "WARNING: MCP server not responding after 60s" && break
  sleep 2
done

# --- Wait for x402 proxy ---
for i in $(seq 1 15); do
  if curl -fsS "http://localhost:8080/sse" >/dev/null 2>&1; then
    echo "x402 proxy ready (port 8080)"
    break
  fi
  sleep 2
done

# --- Test ---
echo
echo "=== Testing endpoints ==="
echo

echo "1. SSE session (free):"
SESSION_ID=$(timeout 3 curl -sN http://localhost:8080/sse 2>/dev/null | grep -oP 'sessionId=\K[a-f0-9-]+' || echo "")
if [ -n "$SESSION_ID" ]; then
  echo "   Session ID: $SESSION_ID"
else
  echo "   WARNING: Could not get SSE session"
fi

echo
echo "2. Paid endpoint without payment (expect 402):"
RESP=$(curl -s -o /dev/null -w "%{http_code}" -X POST "http://localhost:8080/messages?sessionId=test" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}')
if [ "$RESP" = "402" ]; then
  echo "   HTTP $RESP - x402 payment gating is working"
else
  echo "   HTTP $RESP - unexpected (expected 402)"
fi

echo
echo "3. Payment requirements:"
curl -s -X POST "http://localhost:8080/messages?sessionId=test" \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}' 2>/dev/null | head -c 500
echo
echo

echo "=== Logs ==="
$DC logs --tail 10 mcp 2>/dev/null | grep -v "level=warning"
$DC logs --tail 10 app 2>/dev/null | grep -v "level=warning"

echo
echo "============================================"
echo "  Setup complete!"
echo
echo "  Endpoints:"
echo "    SSE (free):  http://$(hostname -I | awk '{print $1}'):8080/sse"
echo "    MCP (paid):  http://$(hostname -I | awk '{print $1}'):8080/messages"
echo
echo "  Payment: \$${PRICE_PER_CALL:-0.01} USDC per call on ${X402_NETWORK:-eip155:8453}"
echo "  Pay-to:  ${PAY_TO_ADDRESS:-<not set>}"
echo
echo "  Teardown: cd $ROOT_DIR && $DC down"
echo "============================================"
