#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="/root/.openclaw/workspace/mcp-local-docker"

echo "=== Ensure stack directory exists ==="
if [ ! -d "$ROOT_DIR" ]; then
  echo "ERROR: Stack directory not found at $ROOT_DIR"
  echo "Please place the prepared docker-compose.yml and related files there."
  exit 1
fi

echo "=== Install Docker (if needed) ==="
if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Installing via official script..."
  curl -fsSL https://get.docker.com -o /tmp/get-docker.sh
  sudo sh /tmp/get-docker.sh
  # Ensure user can run docker without sudo for convenience
  if [ -n "${SUDO_USER:-}" ]; then
    sudo usermod -aG docker "$SUDO_USER"
    echo "Note: You may need to log out/in for docker group changes to take effect."
  fi
else
  echo "Docker is installed."
fi

echo "=== Install Docker Compose (if needed) ==="
# Prefer Docker's plugin (docker compose) if available; otherwise install standalone
if ! docker compose version >/dev/null 2>&1; then
  if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Installing standalone docker-compose..."
    DOCKER_COMPOSE_VERSION="2.20.0"
    ARCH=$(uname -m)
    URL="https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-${ARCH}"
    sudo curl -L "$URL" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
  else
    echo "Using existing docker-compose (standalone)."
  fi
else
  echo "Using 'docker compose' (plugin)."
fi

echo "=== Prepare environment variables (interactive) ==="
ENV_VARS_FILE="$ROOT_DIR/.env"
if [ ! -f "$ENV_VARS_FILE" ]; then
  cat > "$ENV_VARS_FILE" <<EOF
GATEWAY_API_KEY=REPLACE_WITH_YOUR_GATEWAY_API_KEY
AMPERSEND_API_KEY=REPLACE_WITH_YOUR_AMPERSEND_API_KEY
AMPERSEND_API_URL=https://api.ampersend.ai
EOF
  echo "Created $ENV_VARS_FILE with placeholders. Edit and fill real keys as needed."
fi

echo "Would you like to (A) fill keys now interactively, or (B) keep placeholders and edit later? [A/B]"
read -r CHOICE
if [[ "$CHOICE" =~ ^[Aa]$ ]]; then
  echo "Enter MCP Gateway API Key (for MCP):"
  read -r GATEWAY_API_KEY
  echo "Enter Ampersend API Key (for Ampersend):"
  read -r AMPERSEND_API_KEY
  echo "Enter Ampersend API URL (default: https://api.ampersend.ai):"
  read -r AMPERSEND_API_URL
  AMPERSEND_API_URL="${AMPERSEND_API_URL:-https://api.ampersend.ai}"
  cat > "$ENV_VARS_FILE" <<EOF
GATEWAY_API_KEY=${GATEWAY_API_KEY}
AMPERSEND_API_KEY=${AMPERSEND_API_KEY}
AMPERSEND_API_URL=${AMPERSEND_API_URL}
EOF
  echo "Saved keys to $ENV_VARS_FILE"
else
  echo "Using placeholders in $ENV_VARS_FILE. Edit them later as needed."
fi
set -o allexport
source "$ENV_VARS_FILE"
set +o allexport

echo "=== Start stack (docker-compose) ==="
cd "$ROOT_DIR"
docker-compose up -d

echo "=== Wait for MCP GraphQL endpoint to be ready ==="
function wait_for_http {
  local url="$1"
  local retries="$2"
  local i=0
  while [ $i -lt "$retries" ]; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "✔ Ready: $url"
      return 0
    fi
    i=$((i+1))
    sleep 2
  done
  echo "✖ Timed out waiting for $url" >&2
  return 1
}
wait_for_http "http://localhost:8000/graphql" 60

echo "=== Test MCP schema (GraphQL) ==="
RESP_MCP=$(curl -sS -X POST http://localhost:8000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { types { name } } }" }')
echo "MCP /graphql response:"
echo "$RESP_MCP"
echo

echo "=== Test Ampersend-front with token (paid) ==="
PAYLOAD_TOKEN='{"query":"{ __schema { types { name } } }", "ampersend": {"token":"test-token","amount":1000000}}'
RESP_APP_TOKEN=$(curl -sS -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD_TOKEN")
echo "APP /query with token response:"
echo "$RESP_APP_TOKEN"
echo

echo "=== Test Ampersend-front without token (expected 402 or placeholder) ==="
RESP_APP_NO_TOKEN=$(curl -sS -X POST http://localhost:8080/query \
  -H "Content-Type: application/json" \
  -d '{"query":"{ __schema { types { name } } }"}')
echo "APP /query without token response:"
echo "$RESP_APP_NO_TOKEN"
echo

echo "=== Logs (last 80 lines) ==="
docker-compose logs mcp | tail -n 80
docker-compose logs app | tail -n 80
echo

echo "Done. To tear down: docker-compose down"
