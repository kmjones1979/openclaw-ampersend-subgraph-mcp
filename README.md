# OpenClaw: Subgraph MCP × ampersend

Pinata-style layout (same as [ampersend-openclaw](https://github.com/kmjones1979/ampersend-openclaw)): the repo root has **`manifest.json`** + this README; the OpenClaw home is **`workspace/`** (see [PinataCloud/agent-template](https://github.com/PinataCloud/agent-template)).

| Piece | Role |
|--------|------|
| **`manifest.json`** | Pinata Agents config: `scripts.build` + `scripts.start` for native build/run; secrets for CDP/Graph keys; optional cron task. |
| **`workspace/`** | OpenClaw agent files: `AGENTS.md`, `SOUL.md`, `USER.md`, `memory/`, **`skills/ampersend/SKILL.md`**. |
| **`mcp-local-docker/`** | x402 proxy + Rust subgraph MCP server (The Graph). Details: [mcp-local-docker/README.md](mcp-local-docker/README.md). |
| **`scripts/`** | `build.sh` (native compile) and `start.sh` (launch without Docker). |

## Layout

```
manifest.json          # Pinata Agents config (remove _docs before marketplace)
README.md
scripts/
  build.sh             # Native build: Rust + subgraph-mcp + mcp-front deps
  start.sh             # Start both services without Docker
workspace/
  AGENTS.md SOUL.md USER.md IDENTITY.md TOOLS.md HEARTBEAT.md BOOTSTRAP.md
  memory/
  skills/ampersend/SKILL.md
mcp-local-docker/      # Subgraph MCP + x402 gateway (see mcp-local-docker/README.md)
setup-mcp-docker.sh    # Docker-based setup (requires sudo + Docker)
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

Self-hosted **MCP** server for **The Graph** subgraphs, gated by **x402** micropayments (USDC on Base via Coinbase CDP).

### Option A: Docker (requires root/sudo)

```bash
sudo bash setup-mcp-docker.sh
```

### Option B: Native (no Docker, no root)

For environments without Docker — e.g. Pinata Agents, CI containers, unprivileged hosts. Requires `git`, `curl`, a C toolchain (`gcc`, `pkg-config`, `libssl-dev`), and Node.js.

```bash
# Build everything (Rust toolchain + subgraph-mcp binary + mcp-front deps)
bash scripts/build.sh

# Create .env with your secrets (or set them as env vars)
cp mcp-local-docker/.env.example mcp-local-docker/.env
# Edit .env with your values

# Start both services
bash scripts/start.sh
```

The build script installs Rust via [rustup](https://rustup.rs/) (user-level, no root), clones and compiles [subgraph-mcp](https://github.com/graphops/subgraph-mcp) to `~/.local/bin/`, and installs the Node.js proxy deps.

Full architecture, env vars, and client examples: [mcp-local-docker/README.md](mcp-local-docker/README.md).

## Pinata Agents

When imported into Pinata Agents:

1. **Secrets** — set `GATEWAY_API_KEY`, `PAY_TO_ADDRESS`, `CDP_APP_ID`, `CDP_SECRET` in the Pinata dashboard. They're injected as env vars at runtime.
2. **Build** — `manifest.json` → `scripts.build` runs `scripts/build.sh` after each push (installs Rust + compiles subgraph-mcp + installs Node deps).
3. **Start** — `scripts.start` runs `scripts/start.sh` on boot (launches both services on ports 8000/8080).
4. **Routes** — port 8080 is forwarded via `manifest.json` → `routes`.
5. Remove the **`_docs`** key from `manifest.json` before marketplace submit.

## License

ISC (see repository). Comply with [ampersend](https://www.ampersend.ai/) terms for CLI/APIs.
