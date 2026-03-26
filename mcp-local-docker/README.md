# Local MCP + Ampersend-front (OpenClaw) — Quick Start

This bundle provides a self-contained, locally runnable stack for The Graph MCP (Subgraph MCP) with an Ampersend-enabled Node.js app fronting it. It’s designed for quick testing, experimentation, and local development.

What’s included
- Local Subgraph MCP server (Rust) to host GraphQL MCP endpoints
- Ampersend-enabled Node.js front-end that gates queries with x402 payments
- A minimal test UI (optional) and test scripts for end-to-end verification
- Convenience scripts:
  - setup-mcp-docker.sh (interactive bootstrap)
  - setup-mcp-docker-noninteractive.sh (non-interactive bootstrap)
  - test-stack.sh (end-to-end tests for MCP + Ampersend-front)
- A ready-to-download bundle (tarball) that you can move to another Linux host

Prerequisites
- Docker and Docker Compose installed on the host
- The host can reach The Graph Gateway (for real deployments via MCP)
- Optional: Ampersend API key for paid flows

Quick start options
- Option A — Interactive bootstrap (recommended for testing)
  1. Ensure you have keys (MCP gateway, Ampersend) prepared
  2. Run: sudo bash setup-mcp-docker.sh
  3. When prompted, enter the keys or edit the .env afterward at /root/.openclaw/workspace/mcp-local-docker/.env
  4. After startup, test endpoints:
     - MCP: curl -sS -X POST http://localhost:8000/graphql -H 'Content-Type: application/json' -d '{"query":"{ __schema { types { name } } }"}'
     - Ampersend-front with token: curl -sS -X POST http://localhost:8080/query -H 'Content-Type: application/json' -d '{"query":"{ __schema { types { name } } }", "ampersend": {"token":"test-token","amount":1000000}}'
     - Ampersend-front without token: curl -sS -X POST http://localhost:8080/query -H 'Content-Type: application/json' -d '{"query":"{ __schema { types { name } } }"}'
- Option B — Non-interactive bootstrap (no prompts)
  1. Pre-fill /root/.openclaw/workspace/mcp-local-docker/.env with real keys or export GATEWAY_API_KEY, AMPERSEND_API_KEY, AMPERSEND_API_URL
  2. Run: bash setup-mcp-docker-noninteractive.sh
  3. Then run test-stack.sh to verify end-to-end
- Option C — Full one-shot quick test (no prompts, all in one go)
  1. Use the one-shot script: setup-mcp-docker-oneshot.sh
  2. Run: sudo GATEWAY_API_KEY=... AMPERSEND_API_KEY=... AMPERSEND_API_URL=... bash setup-mcp-docker-oneshot.sh

Post-setup testing
- Test MCP GraphQL schema as above
- Test the Ampersend front-end with a paid token and without a token to verify behavior
- Check last logs:
  - docker-compose logs mcp | tail -n 80
  - docker-compose logs app | tail -n 80

Tearing down
- docker-compose down (from within the mcp-local-docker directory)

Keeping this bundle up-to-date
- If you update or modify files, re-pack the bundle to share or move it easily on another machine

Downloadable tarball
- A ready-to-use bundle tarball is available as a new file at the repository bundle location (mcp-local-docker-bundle-v2.tar.gz), containing the same structure plus this README.md. Use: tar -xzvf mcp-local-docker-bundle-v2.tar.gz

Tips
- For production, replace the placeholders with real keys and consider securing keys using proper secret management.
- If you want a README in a specific format (Markdown vs plain text) or want additional sections (e.g., architecture diagram, troubleshooting), tell me and I’ll adjust.

Happy testing!