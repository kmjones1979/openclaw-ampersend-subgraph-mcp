# OpenClaw: Subgraph MCP × ampersend

Pinata-style layout (same as [ampersend-openclaw](https://github.com/kmjones1979/ampersend-openclaw)): the repo root has **`manifest.json`** + this README; the OpenClaw home is **`workspace/`** (see [PinataCloud/agent-template](https://github.com/PinataCloud/agent-template)).

| Piece | Role |
|--------|------|
| **`manifest.json`** | Pinata Agents config: `scripts.build` installs the pinned [ampersend](https://www.ampersend.ai/) CLI; optional cron task (disabled) for `ampersend config status`. |
| **`workspace/`** | OpenClaw agent files: `AGENTS.md`, `SOUL.md`, `USER.md`, `memory/`, **`skills/ampersend/SKILL.md`**. |
| **`mcp-local-docker/`** | Docker stack: x402 proxy + Rust subgraph MCP server (The Graph). Details: [mcp-local-docker/README.md](mcp-local-docker/README.md). |

## Layout

```
manifest.json          # Pinata Agents config (remove _docs before marketplace)
README.md
workspace/
  AGENTS.md SOUL.md USER.md IDENTITY.md TOOLS.md HEARTBEAT.md BOOTSTRAP.md
  memory/
  skills/ampersend/SKILL.md
mcp-local-docker/      # Subgraph MCP + x402 gateway (see mcp-local-docker/README.md)
setup-mcp-docker.sh
…
```

## OpenClaw

Point **`agents.defaults.workspace`** at **`…/workspace`** (this repo’s `workspace` folder), **not** the repo root. See [Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace).

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

## Subgraph MCP + x402 (this repo)

Self-hosted **MCP** server for **The Graph** subgraphs, gated by **x402** micropayments (USDC on Base via Coinbase CDP). Quick start from repo root:

```bash
sudo bash setup-mcp-docker.sh
```

Full architecture, env vars, and client examples: [mcp-local-docker/README.md](mcp-local-docker/README.md) and the “Architecture” section in that file (or browse the historical technical overview in git history if needed).

## Pinata

1. Import the repo in Pinata Agents; edit `manifest.json` `agent` / `template` for your listing.
2. Remove the **`_docs`** key from `manifest.json` before marketplace submit.
3. Tag releases when versions are ready.

## License

ISC (see repository). Comply with [ampersend](https://www.ampersend.ai/) terms for CLI/APIs.
