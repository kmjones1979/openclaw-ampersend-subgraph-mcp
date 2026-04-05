# Subgraph MCP + x402 Payment Gateway

A self-contained stack that serves [The Graph](https://thegraph.com/) subgraph data via the [Model Context Protocol (MCP)](https://github.com/graphops/subgraph-mcp), gated by [x402](https://www.x402.org/) micropayments in USDC on Base mainnet.

**OpenClaw:** agent instructions and the [ampersend](https://www.ampersend.ai/) skill live in the repo's **`workspace/`** folder; **`manifest.json`** is at the repo root. See the [root README](../README.md).

The **`mcp-front`** service depends on **`@ampersend_ai/ampersend-sdk@0.0.16`** (see [ampersend docs](https://docs.ampersend.ai/)); it loads at startup to confirm the SDK is present. Seller-side verify/settle for this stack still uses **Express + `@x402/core` + Coinbase CDP** as implemented in `mcp-front/server.js`.

## Architecture

```
Client (with USDC wallet)
  │
  │  x402 payment (PAYMENT-SIGNATURE header)
  ▼
┌──────────────────────────────┐
│  Node.js x402 Proxy (:8080)  │  ← verifies + settles payments via Coinbase CDP
│  Express + @x402/core        │
└──────────┬───────────────────┘
           │  proxy (free after payment)
           ▼
┌──────────────────────────────┐
│  Subgraph MCP Server (:8000) │  ← Rust, queries The Graph Gateway
│  GraphQL + MCP protocol      │
└──────────────────────────────┘
```

## What you need

| Item | Where to get it |
|---|---|
| **The Graph Gateway API key** | [thegraph.com/studio](https://thegraph.com/studio) |
| **Coinbase CDP App ID + Ed25519 secret** | [portal.cdp.coinbase.com](https://portal.cdp.coinbase.com) — create an app, generate an Ed25519 key pair |
| **A wallet address on Base mainnet** | Where USDC payments are sent |
| **Rust + Node.js** | Installed automatically by the setup script |

## Quick start

```bash
# One command — builds Rust binary (first run ~10-20 min), installs Node deps, starts both services
bash scripts/setup-mcp.sh
```

Secrets are expected as env vars (`GATEWAY_API_KEY`, `PAY_TO_ADDRESS`, `CDP_APP_ID`, `CDP_SECRET`). On Pinata Agents these are injected from the dashboard. For local dev:

```bash
cp mcp-local-docker/.env.example mcp-local-docker/.env
# Edit .env with your values, then:
bash scripts/setup-mcp.sh
```

### What the setup does

1. Checks that all 4 required env vars are present
2. Installs [Rust via rustup](https://rustup.rs/) to `~/.cargo/` (user-level, no root)
3. Clones [graphops/subgraph-mcp](https://github.com/graphops/subgraph-mcp), runs `cargo build --release`, copies the binary to `~/.local/bin/subgraph-mcp`
4. Installs `mcp-front/` Node.js dependencies (pnpm preferred, falls back to npm)
5. Starts `subgraph-mcp` on port 8000 and `mcp-front` (x402 proxy) on port 8080

Steps 2-4 are skipped on subsequent runs if already done.

### Verify

```bash
curl -s -N http://localhost:8080/sse          # Should return SSE with sessionId
curl -s -X POST http://localhost:8080/messages \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
# Should return HTTP 402 with payment requirements
```

## Endpoints

| Method | Path | Payment | Description |
|---|---|---|---|
| `GET` | `/sse` | Free | SSE session — returns `sessionId` |
| `POST` | `/messages?sessionId=<id>` | $0.01 USDC | MCP tool calls |
| `POST` | `/query?sessionId=<id>` | $0.01 USDC | Legacy MCP endpoint |

## x402 payment details

| | |
|---|---|
| **x402 Version** | 2 |
| **Scheme** | `exact` (EIP-3009) |
| **Network** | `eip155:8453` (Base mainnet) |
| **Asset** | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| **Facilitator** | Coinbase CDP (`https://api.cdp.coinbase.com/platform/v2/x402`) |

### Payment flow

1. `GET /sse` → receive `sessionId`
2. `POST /messages?sessionId=<id>` → HTTP 402 with `PAYMENT-REQUIRED` header (base64 JSON with `accepts` array)
3. Client signs EIP-3009 `transferWithAuthorization` using the requirements
4. Retry with `PAYMENT-SIGNATURE` header (base64 payment payload)
5. Server verifies + settles via CDP, returns `PAYMENT-RESPONSE` header

### Client example

```bash
npm install @x402/fetch viem
```

```js
import { wrapFetchWithPayment } from "@x402/fetch";
import { createWalletClient, http } from "viem";
import { privateKeyToAccount } from "viem/accounts";
import { base } from "viem/chains";

const wallet = createWalletClient({
  account: privateKeyToAccount("0xYOUR_KEY"),
  chain: base,
  transport: http(),
});

const paidFetch = wrapFetchWithPayment(fetch, wallet);

// Automatically handles 402 → sign → retry
const res = await paidFetch("http://<SERVER>:8080/messages?sessionId=<ID>", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    jsonrpc: "2.0", id: 1,
    method: "initialize",
    params: {
      protocolVersion: "2024-11-05",
      capabilities: {},
      clientInfo: { name: "my-client", version: "1.0" },
    },
  }),
});
```

## Environment variables

See [`.env.example`](.env.example) for the full list with descriptions.

| Variable | Required | Default | Description |
|---|---|---|---|
| `GATEWAY_API_KEY` | Yes | — | The Graph Gateway API key |
| `PAY_TO_ADDRESS` | Yes | — | Wallet address to receive USDC payments |
| `CDP_APP_ID` | Yes | — | Coinbase CDP application ID |
| `CDP_SECRET` | Yes | — | Base64-encoded Ed25519 private key from CDP |
| `X402_NETWORK` | No | `eip155:8453` | Chain in CAIP-2 format |
| `FACILITATOR_URL` | No | `https://api.cdp.coinbase.com/platform/v2/x402` | x402 facilitator endpoint |
| `PRICE_PER_CALL` | No | `0.01` | USD price per MCP call |

## Teardown

Send `Ctrl-C` to the `setup-mcp.sh` / `start.sh` process — the trap cleans up both child services.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `x402 init failed` on startup | Check CDP_APP_ID and CDP_SECRET are correct. The server queries `/supported` on the facilitator at boot. |
| 402 with `extra: {}` | USDC EIP-712 domain info missing. Make sure you're on the latest `server.js`. |
| Settlement fails after verify succeeds | Check `settleResult.success` (not `settleResult.type`). Fixed in commit `19a4c10`. |
| `invalid_payload` from facilitator | Network must be CAIP-2 format (`eip155:8453`), not named (`base`). |
