# Subgraph MCP + x402 Payment Gateway

A self-contained stack that serves [The Graph](https://thegraph.com/) subgraph data via the [Model Context Protocol (MCP)](https://github.com/graphops/subgraph-mcp), gated by [x402](https://www.x402.org/) micropayments in USDC on Base mainnet.

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
| **Docker + Docker Compose** | Setup script installs these if missing |

## Quick start

```bash
# Clone the repo
git clone https://github.com/kmjones1979/openclaw-ampersend-subgraph-mcp.git
cd openclaw-ampersend-subgraph-mcp

# Run interactive setup (prompts for keys)
sudo bash setup-mcp-docker.sh
```

The setup script will:
1. Install Docker/Compose if needed
2. Prompt for your Gateway key, CDP credentials, and pay-to address
3. Build and start both containers
4. Test the endpoints

### Manual setup (non-interactive)

```bash
# 1. Copy and fill the env template
cp mcp-local-docker/.env.example mcp-local-docker/.env
# Edit .env with your values

# 2. Start the stack
cd mcp-local-docker
docker compose up -d --build

# 3. Verify
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

```bash
cd mcp-local-docker
docker compose down
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `x402 init failed` on startup | Check CDP_APP_ID and CDP_SECRET are correct. The server queries `/supported` on the facilitator at boot. |
| 402 with `extra: {}` | USDC EIP-712 domain info missing. Make sure you're on the latest `server.js`. |
| Settlement fails after verify succeeds | Check `settleResult.success` (not `settleResult.type`). Fixed in commit `19a4c10`. |
| `invalid_payload` from facilitator | Network must be CAIP-2 format (`eip155:8453`), not named (`base`). |
