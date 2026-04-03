# TOOLS.md - Local Notes

Skills define _how_ tools work. This file is for _your_ specifics — the stuff that's unique to your setup.

## This repository

- **Subgraph MCP + x402 (Docker):** `../mcp-local-docker/` — proxy port 8080, MCP 8000 after `docker compose up`. See `../README.md` and `../mcp-local-docker/README.md`.
- **ampersend CLI:** global install via `manifest.json` `scripts.build` or `npm install -g @ampersend_ai/ampersend-sdk@0.0.16`. Skill: `skills/ampersend/SKILL.md`.

## What Goes Here

Things like:

- Gateway URL for the x402 MCP proxy (if not localhost)
- The Graph Studio API key location (env name only — not the secret)
- Camera names, SSH hosts, TTS voices, device nicknames

## Examples

```markdown
### Subgraph MCP

- local proxy: http://localhost:8080/sse
- paid POSTs: /messages?sessionId=… ($0.01 USDC per call on Base)

### SSH

- home-server → 192.168.1.100, user: admin
```

## Why Separate?

Skills are shared. Your setup is yours. Keeping them apart means you can update skills without losing your notes, and share skills without leaking your infrastructure.

---

Add whatever helps you do your job. This is your cheat sheet.
