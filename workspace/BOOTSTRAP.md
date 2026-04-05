# BOOTSTRAP.md — First run

You are booting a workspace for **ampersend** (x402 agent payments) and a repo that contains the **Subgraph MCP + x402** stack.

## 1) Human: ampersend CLI (gateway machine)

On the host where OpenClaw runs (same place shell commands execute):

```bash
npm install -g @ampersend_ai/ampersend-sdk@0.0.16
ampersend --version
```

If not configured, complete **either** the automated flow:

```bash
ampersend setup start --name "openclaw-agent"
# Open user_approve_url on the HUMAN's own browser — not one the assistant controls.

ampersend setup finish
ampersend config status
```

**or** manual config per `skills/ampersend/SKILL.md`.

## 2) Human: OpenClaw workspace path

This folder is the OpenClaw workspace (`workspace/` inside the git repo). Set **`agents.defaults.workspace`** to this directory — **not** the parent repo root. See [Agent workspace](https://docs.openclaw.ai/concepts/agent-workspace).

Ensure the **`ampersend` binary** is on `PATH` for the gateway process (skill metadata requires `bins: ["ampersend"]`).

## 3) Optional: Subgraph MCP stack (repo root)

From the **repository root** (parent of `workspace/`):

**Docker** (requires root/sudo):

```bash
sudo bash setup-mcp-docker.sh
```

**Native** (no Docker, no root — e.g. Pinata Agents):

```bash
bash scripts/build.sh   # Rust toolchain + subgraph-mcp binary + Node deps
bash scripts/start.sh   # launches subgraph-mcp :8000 + mcp-front :8080
```

Secrets come from env vars (Pinata injects them) or from `mcp-local-docker/.env`. See `../mcp-local-docker/README.md` for full details.

## 4) You + human: identity

Have a short conversation and then update:

- `IDENTITY.md` — your name, vibe, emoji
- `USER.md` — how to address them, timezone, preferences

Then refine `SOUL.md` together if needed.

## 5) Done

Delete this file when the above is complete.
