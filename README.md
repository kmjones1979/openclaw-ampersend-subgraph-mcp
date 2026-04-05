# OpenClaw: Subgraph MCP × ampersend

Pinata-style layout (same as [ampersend-openclaw](https://github.com/kmjones1979/ampersend-openclaw)): the repo root has **`manifest.json`** + this README; the OpenClaw home is **`workspace/`** (see [PinataCloud/agent-template](https://github.com/PinataCloud/agent-template)).

| Piece | Role |
|--------|------|
| **`manifest.json`** | Pinata Agents config: `scripts.build` for lightweight deps; secrets for CDP/Graph keys; optional cron task. |
| **`workspace/`** | OpenClaw agent files: `AGENTS.md`, `SOUL.md`, `USER.md`, `memory/`, **`skills/ampersend/SKILL.md`**. |
| **`mcp-local-docker/`** | x402 proxy (`mcp-front/server.js`) + Rust MCP server source ref. Details: [mcp-local-docker/README.md](mcp-local-docker/README.md). |
| **`scripts/`** | `setup-mcp.sh` (one-command build + start), `build.sh` / `build-mcp.sh` / `start.sh` (individual steps). |

## Layout

```
manifest.json          # Pinata Agents config (remove _docs before marketplace)
README.md
scripts/
  setup-mcp.sh         # One command: build + start everything
  build.sh             # Lightweight: ampersend CLI + mcp-front Node deps
  build-mcp.sh         # Heavy: Rust toolchain + subgraph-mcp binary
  start.sh             # Start both services
workspace/
  AGENTS.md SOUL.md USER.md IDENTITY.md TOOLS.md HEARTBEAT.md BOOTSTRAP.md
  memory/
  skills/ampersend/SKILL.md
mcp-local-docker/
  mcp-front/           # Node.js x402 proxy (server.js + package.json)
```

## OpenClaw

Point **`agents.defaults.workspace`** at **`…/workspace`** (this repo's `workspace` folder), **not** the repo root. See [Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace).

## ampersend CLI

```bash
npm install -g @ampersend_ai/ampersend-sdk@0.0.16
ampersend --version
```

Setup (human approves in **their** browser):

```bash
ampersend setup start --name "my-openclaw-agent"
ampersend setup finish
ampersend config status
```

Details: `workspace/skills/ampersend/SKILL.md`.

## Subgraph MCP + x402

Self-hosted **MCP** server for **The Graph** subgraphs, gated by **x402** micropayments (USDC on Base via Coinbase CDP). No Docker required.

### Setup (one command)

```bash
bash scripts/setup-mcp.sh
```

This handles everything: installs Rust via [rustup](https://rustup.rs/) (user-level, no root), compiles [subgraph-mcp](https://github.com/graphops/subgraph-mcp) to `~/.local/bin/`, installs Node.js proxy deps, and starts both services. First run takes ~10-20 min (Rust compile); re-runs are fast.

Secrets are expected as env vars (`GATEWAY_API_KEY`, `PAY_TO_ADDRESS`, `CDP_APP_ID`, `CDP_SECRET`). On Pinata Agents these are injected from the dashboard. For local dev, copy and fill `mcp-local-docker/.env.example`.

Full architecture, env vars, and client examples: [mcp-local-docker/README.md](mcp-local-docker/README.md).

## Pinata Agents

When imported into Pinata Agents:

1. **Secrets** — set `GATEWAY_API_KEY`, `PAY_TO_ADDRESS`, `CDP_APP_ID`, `CDP_SECRET` in the Pinata dashboard. They're injected as env vars at runtime.
2. **Build** — `manifest.json` → `scripts.build` runs `scripts/build.sh` after each push (installs ampersend CLI + Node deps).
3. **MCP setup** — after the agent boots, tell it to run `bash scripts/setup-mcp.sh` (or it will follow `BOOTSTRAP.md` automatically).
4. Remove the **`_docs`** key from `manifest.json` before marketplace submit.

## License

ISC (see repository). Comply with [ampersend](https://www.ampersend.ai/) terms for CLI/APIs.
