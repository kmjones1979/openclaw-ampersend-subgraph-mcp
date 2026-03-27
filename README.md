# OpenClaw: x402-Paid Subgraph MCP

A self-contained stack that serves [The Graph](https://thegraph.com/) subgraph data via the [Model Context Protocol (MCP)](https://github.com/graphops/subgraph-mcp), gated by [x402](https://www.x402.org/) micropayments in USDC on Base mainnet. Payments are facilitated by [Coinbase CDP](https://docs.cdp.coinbase.com/).

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   CLIENT                        │
│  (Claude, AI agent, CLI tool, etc.)             │
└──────────────┬──────────────────────────────────┘
               │
               │  HTTP + SSE
               ▼
┌─────────────────────────────────────────────────┐
│          x402 PROXY (Node.js :8080)             │
│  Express server with payment middleware         │
│  - Checks for PAYMENT-SIGNATURE header          │
│  - Verifies + settles via Coinbase CDP          │
│  - Proxies to MCP backend after payment         │
└──────────────┬──────────────────────────────────┘
               │
               │  HTTP + SSE (internal)
               ▼
┌─────────────────────────────────────────────────┐
│        SUBGRAPH MCP SERVER (Rust :8000)         │
│  - MCP protocol over SSE transport              │
│  - Queries The Graph Gateway (GraphQL)          │
│  - Returns blockchain data from subgraphs       │
└─────────────────────────────────────────────────┘
```

## Quick Start

```bash
git clone https://github.com/kmjones1979/openclaw-ampersend-subgraph-mcp.git
cd openclaw-ampersend-subgraph-mcp

# Interactive setup (prompts for keys)
sudo bash setup-mcp-docker.sh
```

See [mcp-local-docker/README.md](mcp-local-docker/README.md) for manual setup, environment variables, client SDK examples, and troubleshooting.

### What You Need

| Item | Where to get it |
|---|---|
| The Graph Gateway API key | [thegraph.com/studio](https://thegraph.com/studio) |
| Coinbase CDP App ID + Ed25519 secret | [portal.cdp.coinbase.com](https://portal.cdp.coinbase.com) |
| A wallet address on Base mainnet | Where USDC payments are sent |

## How It Works

There are three layers: the **MCP protocol** for AI tool calls, **x402** for per-call payments, and the **subgraph server** for blockchain data.

### MCP Protocol (Model Context Protocol)

MCP is a standard for AI tools. It defines how a client discovers and calls **tools** on a server using JSON-RPC 2.0 -- a universal plugin API for AI agents.

The subgraph MCP server exposes 9 tools:

| Tool | Description |
|---|---|
| `search_subgraphs_by_keyword` | Find subgraphs by name |
| `execute_query_by_subgraph_id` | Run a GraphQL query on a subgraph |
| `execute_query_by_deployment_id` | Run a GraphQL query on a specific deployment |
| `execute_query_by_ipfs_hash` | Run a GraphQL query by IPFS hash |
| `get_schema_by_subgraph_id` | Get a subgraph's GraphQL schema |
| `get_schema_by_deployment_id` | Get schema by deployment ID |
| `get_schema_by_ipfs_hash` | Get schema by IPFS hash |
| `get_top_subgraph_deployments` | Find top deployments for a contract address |
| `get_deployment_30day_query_counts` | Get query volume for deployments |

### MCP SSE Transport

MCP uses **SSE (Server-Sent Events) transport**, not normal request/response. This is important to understand:

```
CLIENT                                    SERVER
  │                                          │
  │─── GET /sse ────────────────────────────>│
  │<── SSE stream opens ─────────────────────│
  │<── event: endpoint                       │
  │    data: /messages?sessionId=abc-123     │
  │                                          │
  │  (stream stays open, responses come here)│
  │                                          │
  │─── POST /messages?sessionId=abc-123 ───->│
  │    {"jsonrpc":"2.0","id":1,              │
  │     "method":"initialize",...}           │
  │<── HTTP 202 Accepted (empty body) ───────│
  │                                          │
  │<── SSE event on the open stream: ────────│
  │    data: {"jsonrpc":"2.0","id":1,        │
  │           "result":{...server info...}}  │
  │                                          │
  │─── POST /messages?sessionId=abc-123 ───->│
  │    {"jsonrpc":"2.0","id":2,              │
  │     "method":"tools/list",...}           │
  │<── HTTP 202 Accepted (empty body) ───────│
  │                                          │
  │<── SSE event: ───────────────────────────│
  │    data: {"jsonrpc":"2.0","id":2,        │
  │           "result":{"tools":[...]}}      │
  │                                          │
```

**The POST returns 202 with an empty body** -- this is by design. It means "message received." The actual result comes back on the SSE stream, matched by the JSON-RPC `id` field.

Why SSE instead of normal request/response:
- MCP supports streaming, notifications, and server-initiated messages
- The server can push progress updates mid-tool-call
- One persistent connection, many messages

### x402 Payment Layer

x402 is an HTTP payment protocol. It uses standard HTTP headers to gate access to any endpoint:

```
CLIENT                         x402 PROXY                    CDP FACILITATOR
  │                               │                               │
  │── POST /messages ────────────>│                               │
  │   (no payment header)         │                               │
  │                               │                               │
  │<── HTTP 402 ──────────────────│                               │
  │    PAYMENT-REQUIRED: base64({ │                               │
  │      x402Version: 2,          │                               │
  │      accepts: [{              │                               │
  │        scheme: "exact",       │                               │
  │        network: "eip155:8453",│                               │
  │        amount: "10000",       │  ($0.01 USDC)                 │
  │        asset: "0x833589...",  │  (USDC on Base)               │
  │        payTo: "0x89480c...",  │                               │
  │        extra: {               │                               │
  │          name: "USD Coin",    │  (EIP-712 domain for signing) │
  │          version: "2"         │                               │
  │        }                      │                               │
  │      }]                       │                               │
  │    })                         │                               │
  │                               │                               │
  │  Client signs EIP-3009        │                               │
  │  transferWithAuthorization    │                               │
  │  (off-chain signature,        │                               │
  │   no gas needed from client)  │                               │
  │                               │                               │
  │── POST /messages ────────────>│                               │
  │   PAYMENT-SIGNATURE: base64({ │                               │
  │     x402Version: 2,           │                               │
  │     accepted: {scheme,...},   │                               │
  │     payload: {                │                               │
  │       signature: "0x...",     │                               │
  │       authorization: {        │                               │
  │         from, to, value,      │                               │
  │         validAfter,           │                               │
  │         validBefore, nonce    │                               │
  │       }                       │                               │
  │     }                         │                               │
  │   })                          │                               │
  │                               │── POST /verify ──────────────>│
  │                               │   {paymentPayload,            │
  │                               │    paymentRequirements}       │
  │                               │<── {isValid: true} ───────────│
  │                               │                               │
  │                               │── POST /settle ──────────────>│
  │                               │   (CDP submits the EIP-3009   │
  │                               │    tx on-chain on Base)       │
  │                               │<── {success: true,            │
  │                               │     transaction: "0x086d..."} │
  │                               │                               │
  │<── HTTP 202 + proxy to MCP ───│                               │
  │    PAYMENT-RESPONSE: base64({ │                               │
  │      settled: true,           │                               │
  │      transaction: "0x086d..." │                               │
  │    })                         │                               │
```

**Key concepts:**

- **EIP-3009**: A USDC-specific standard. The client signs a message saying "I authorize transferring X USDC from me to address Y." No on-chain transaction needed from the client -- no gas.
- **Facilitator (Coinbase CDP)**: A trusted third party that takes the signed authorization, verifies it's valid, then submits the actual `transferWithAuthorization` transaction on Base mainnet. Coinbase pays the gas.
- **$0.01 per call**: Each MCP tool call costs 10,000 atomic USDC units (USDC has 6 decimals).

### Full End-to-End Flow

Putting it all together -- a client querying "search for Uniswap subgraphs":

```
1. GET /sse
   -> SSE stream opens
   -> Server sends: sessionId=abc-123

2. POST /messages?sessionId=abc-123  (no payment)
   Body: {"method":"initialize",...}
   <- HTTP 402 + PAYMENT-REQUIRED header

3. Client reads requirements, signs EIP-3009 authorization

4. POST /messages?sessionId=abc-123  (with PAYMENT-SIGNATURE)
   Body: {"method":"initialize",...}
   -> Proxy verifies signature with CDP    OK
   -> Proxy settles payment with CDP       OK ($0.01 USDC transferred)
   -> Proxy forwards to MCP backend
   <- HTTP 202 + PAYMENT-RESPONSE header
   <- SSE event: {"id":1,"result":{"serverInfo":{"name":"subgraph-mcp"},...}}

5. POST /messages?sessionId=abc-123  (with PAYMENT-SIGNATURE)
   Body: {"method":"tools/call","params":{
     "name":"search_subgraphs_by_keyword",
     "arguments":{"keyword":"uniswap"}
   }}
   -> Another $0.01 USDC payment
   -> Proxy forwards to MCP backend
   -> MCP server queries The Graph Gateway
   <- HTTP 202
   <- SSE event: {"id":2,"result":{"content":[{"text":"...21 uniswap subgraphs..."}]}}
```

**Every POST to `/messages` costs $0.01 USDC.** The SSE connection (`GET /sse`) is free.

### What the MCP Server Does Under the Hood

When you call a tool like `search_subgraphs_by_keyword`, the Rust MCP server:

1. Receives the JSON-RPC call
2. Builds a GraphQL query against The Graph's decentralized network
3. Sends it to the Gateway API (authenticated with `GATEWAY_API_KEY`)
4. Returns the subgraph data (names, IPFS hashes, deployment IDs)

The subgraphs themselves are indexing on-chain data -- Uniswap pools, ENS names, Aave lending positions, etc. The full chain is:

```
AI agent -> x402 payment -> MCP protocol -> The Graph Gateway -> Subgraph indexers -> Blockchain data
```

## Endpoints

| Method | Path | Payment | Description |
|---|---|---|---|
| `GET` | `/sse` | Free | SSE session -- returns `sessionId` |
| `POST` | `/messages?sessionId=<id>` | $0.01 USDC | MCP tool calls |
| `POST` | `/query?sessionId=<id>` | $0.01 USDC | Legacy MCP endpoint |

## x402 Payment Details

| | |
|---|---|
| x402 Version | 2 |
| Scheme | `exact` (EIP-3009) |
| Network | `eip155:8453` (Base mainnet) |
| Asset | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` (USDC) |
| Facilitator | Coinbase CDP |

### Client Wallet Requirements

- An EOA or smart account on **Base mainnet** (chain ID 8453)
- At least **$0.01 USDC** per call
- USDC on Base supports EIP-3009 natively -- no Permit2 approval needed, no gas needed from the client

## Client Example

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

// Automatically handles 402 -> sign -> retry
const res = await paidFetch("http://<SERVER>:8080/messages?sessionId=<ID>", {
  method: "POST",
  headers: { "Content-Type": "application/json" },
  body: JSON.stringify({
    jsonrpc: "2.0", id: 1,
    method: "tools/call",
    params: {
      name: "search_subgraphs_by_keyword",
      arguments: { keyword: "uniswap" },
    },
  }),
});
// Response comes back on the SSE stream, not in this POST body
```

## License

ISC
