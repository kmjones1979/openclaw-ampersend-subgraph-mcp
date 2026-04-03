/**
 * x402 seller proxy: Express + @x402/core + Coinbase CDP verify/settle, forwards to the Rust MCP backend.
 * @ampersend_ai/ampersend-sdk is installed and verified at startup (ESM); see https://docs.ampersend.ai/
 */
const express = require('express');
const fetch = require('node-fetch');
const crypto = require('crypto');
const path = require('path');
const {
  x402ResourceServer,
  x402HTTPResourceServer,
  HTTPFacilitatorClient,
} = require('@x402/core/server');
const { getUsdcAddressForChain } = require('x402/shared/evm');

const app = express();
app.use(express.json());

const MCP_BASE = process.env.MCP_HOST || 'http://mcp:8000';
const PAY_TO = process.env.PAY_TO_ADDRESS || '0x0000000000000000000000000000000000000000';
const FACILITATOR_URL = process.env.FACILITATOR_URL || 'https://api.cdp.coinbase.com/platform/v2/x402';
const PRICE_PER_CALL = process.env.PRICE_PER_CALL || '0.01'; // $0.01 USDC
const NETWORK = process.env.X402_NETWORK || 'eip155:8453'; // Base mainnet
const CDP_APP_ID = process.env.CDP_APP_ID || '';
const CDP_SECRET = process.env.CDP_SECRET || '';

// CDP JWT auth for the facilitator (Ed25519/EdDSA)
function createCdpAuthHeaders() {
  if (!CDP_APP_ID || !CDP_SECRET) return null;

  const keyData = Buffer.from(CDP_SECRET, 'base64');
  if (keyData.length !== 64) {
    console.error('CDP_SECRET should decode to 64 bytes, got', keyData.length);
    return null;
  }
  const seed = keyData.slice(0, 32);

  const pkcs8Prefix = Buffer.from('302e020100300506032b657004220420', 'hex');
  const privateKey = crypto.createPrivateKey({
    key: Buffer.concat([pkcs8Prefix, seed]),
    format: 'der',
    type: 'pkcs8',
  });

  const facilitatorUrl = new URL(FACILITATOR_URL);
  const host = facilitatorUrl.host;
  const basePath = facilitatorUrl.pathname;

  function signJwt(uri) {
    const now = Math.floor(Date.now() / 1000);
    const nonce = crypto.randomBytes(16).toString('hex');
    const header = { alg: 'EdDSA', kid: CDP_APP_ID, typ: 'JWT', nonce };
    const payload = {
      sub: CDP_APP_ID,
      iss: 'cdp',
      aud: ['cdp_service'],
      nbf: now,
      iat: now,
      exp: now + 120,
      uris: [uri],
    };
    const b64url = (obj) => Buffer.from(JSON.stringify(obj)).toString('base64url');
    const signingInput = `${b64url(header)}.${b64url(payload)}`;
    const sig = crypto.sign(null, Buffer.from(signingInput), privateKey);
    return `${signingInput}.${sig.toString('base64url')}`;
  }

  return async () => {
    const paths = {
      supported: { method: 'GET', path: 'supported' },
      verify: { method: 'POST', path: 'verify' },
      settle: { method: 'POST', path: 'settle' },
    };
    const result = {};
    for (const [key, { method, path }] of Object.entries(paths)) {
      const uri = `${method} ${host}${basePath}/${path}`;
      result[key] = { 'Authorization': `Bearer ${signJwt(uri)}` };
    }
    return result;
  };
}

// USDC has 6 decimals
function usdToUsdcBaseUnits(usdAmount) {
  return String(Math.round(parseFloat(usdAmount) * 1_000_000));
}

function getChainId(network) {
  // network format: "eip155:<chainId>"
  return parseInt(network.split(':')[1], 10);
}

// USDC EIP-712 domain info per chain (required by EIP-3009 facilitators)
const USDC_DOMAIN = {
  8453:  { name: 'USD Coin',  version: '2' },  // Base mainnet
  84532: { name: 'USDC',      version: '2' },  // Base Sepolia
};

// Server-side scheme implementation for exact EVM payments
function createEvmExactSchemeServer(network) {
  const chainId = getChainId(network);
  const usdcAddress = getUsdcAddressForChain(chainId);
  const domain = USDC_DOMAIN[chainId] || { name: 'USD Coin', version: '2' };

  return {
    scheme: 'exact',

    async parsePrice(price, net) {
      if (typeof price === 'object' && price.amount && price.asset) {
        return price;
      }
      return {
        amount: usdToUsdcBaseUnits(price),
        asset: usdcAddress,
        extra: {
          name: domain.name,
          version: domain.version,
        },
      };
    },

    async enhancePaymentRequirements(requirements, supportedKind, facilitatorExtensions) {
      // Ensure EIP-712 domain info is always present
      requirements.extra = {
        name: domain.name,
        version: domain.version,
        ...requirements.extra,
        ...(supportedKind.extra || {}),
      };
      return requirements;
    },
  };
}

// x402 payment configuration
const paymentOption = {
  scheme: 'exact',
  payTo: PAY_TO,
  price: PRICE_PER_CALL,
  network: NETWORK,
  maxTimeoutSeconds: 60,
};

const routes = {
  'POST /messages': {
    accepts: paymentOption,
    resource: 'MCP tool call',
    description: 'Execute a tool call on The Graph Subgraph MCP ($0.01 USDC)',
  },
  'POST /query': {
    accepts: paymentOption,
    resource: 'MCP tool call',
    description: 'Execute a tool call on The Graph Subgraph MCP ($0.01 USDC)',
  },
};

let httpResourceServer;

async function initX402() {
  const facilitatorConfig = { url: FACILITATOR_URL };
  const authFn = createCdpAuthHeaders();
  if (authFn) {
    facilitatorConfig.createAuthHeaders = authFn;
    console.log('CDP auth configured for facilitator');
  }
  const facilitator = new HTTPFacilitatorClient(facilitatorConfig);
  const resourceServer = new x402ResourceServer(facilitator);

  // Register the exact payment scheme for EVM
  resourceServer.register(NETWORK, createEvmExactSchemeServer(NETWORK));

  httpResourceServer = new x402HTTPResourceServer(resourceServer, routes);
  await httpResourceServer.initialize();
  console.log(`x402 payment gating initialized: $${PRICE_PER_CALL} USDC per tool call on ${NETWORK}`);
  console.log(`Pay-to address: ${PAY_TO}`);
  console.log(`Facilitator: ${FACILITATOR_URL}`);
}

// Express adapter for x402HTTPResourceServer
function createExpressAdapter(req) {
  return {
    getHeader: (name) => req.headers[name.toLowerCase()],
    getMethod: () => req.method,
    getPath: () => req.path,
    getUrl: () => req.originalUrl,
    getAcceptHeader: () => req.headers['accept'] || '',
    getUserAgent: () => req.headers['user-agent'] || '',
    getQueryParams: () => req.query,
    getQueryParam: (name) => req.query[name],
    getBody: () => req.body,
  };
}

// x402 middleware
async function x402Middleware(req, res, next) {
  if (!httpResourceServer) {
    return next();
  }

  const adapter = createExpressAdapter(req);
  const context = { adapter, path: req.path, method: req.method };

  try {
    const result = await httpResourceServer.processHTTPRequest(context);

    if (result.type === 'no-payment-required') {
      return next();
    }

    if (result.type === 'payment-verified') {
      // Payment valid — settle it, then proxy
      const settleResult = await httpResourceServer.processSettlement(
        result.paymentPayload,
        result.paymentRequirements,
        result.declaredExtensions,
      );
      if (settleResult.success) {
        // Set PAYMENT-RESPONSE header
        if (settleResult.headers) {
          for (const [key, value] of Object.entries(settleResult.headers)) {
            res.set(key, value);
          }
        }
        return next();
      }
      // Settlement failed
      console.error('Settlement failed:', settleResult.errorReason, settleResult.errorMessage || '');
      const failResp = settleResult.response || { status: 402, headers: {}, body: { error: settleResult.errorReason || 'Settlement failed' } };
      if (failResp.headers) {
        for (const [key, value] of Object.entries(failResp.headers)) {
          res.set(key, value);
        }
      }
      return res.status(failResp.status || 402).json(failResp.body);
    }

    if (result.type === 'payment-error') {
      const resp = result.response;
      if (resp.headers) {
        for (const [key, value] of Object.entries(resp.headers)) {
          res.set(key, value);
        }
      }
      if (resp.isHtml) {
        return res.status(resp.status).send(resp.body);
      }
      return res.status(resp.status).json(resp.body);
    }

    next();
  } catch (err) {
    console.error('x402 middleware error:', err.message);
    return res.status(500).json({ error: 'Payment processing error', detail: err.message });
  }
}

// Favicon
app.get('/favicon.ico', (req, res) => res.sendFile(path.join(__dirname, 'favicon.png')));
app.get('/favicon.png', (req, res) => res.sendFile(path.join(__dirname, 'favicon.png')));

// x402 discovery endpoint
app.get('/.well-known/x402', (req, res) => {
  res.json({
    version: 1,
    resources: ['POST /messages', 'POST /query'],
  });
});

// OpenAPI spec for x402scan discovery
app.get('/openapi.json', (req, res) => {
  res.json({
    openapi: '3.0.3',
    info: {
      title: 'Subgraph MCP x402 API',
      version: '1.0.0',
      description: 'x402-paid access to The Graph subgraph data via MCP (Model Context Protocol). Query blockchain data from Uniswap, Aave, ENS, and 440+ subgraphs.',
      'x-guidance': 'Connect via GET /sse to get a sessionId, then POST JSON-RPC messages to /messages?sessionId=<id>. Each POST costs $0.01 USDC on Base mainnet. Responses arrive on the SSE stream, not in the POST body.',
    },
    servers: [{ url: 'https://subgraph.duckdns.org' }],
    paths: {
      '/sse': {
        get: {
          summary: 'Open MCP SSE session (free)',
          description: 'Opens a Server-Sent Events stream and returns a sessionId for subsequent message calls.',
          responses: {
            '200': { description: 'SSE stream with endpoint event containing sessionId' },
          },
        },
      },
      '/messages': {
        post: {
          summary: 'Send MCP JSON-RPC message ($0.01 USDC)',
          description: 'Send a JSON-RPC 2.0 message (initialize, tools/list, tools/call) to the MCP server. Requires x402 payment. Response arrives on the SSE stream.',
          'x-payment-info': {
            protocols: ['x402'],
            pricingMode: 'fixed',
            price: '0.01',
            network: 'eip155:8453',
            asset: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
            payTo: PAY_TO,
          },
          parameters: [
            { name: 'sessionId', in: 'query', required: true, schema: { type: 'string' }, description: 'Session ID from SSE endpoint' },
          ],
          requestBody: {
            required: true,
            content: {
              'application/json': {
                schema: {
                  type: 'object',
                  required: ['jsonrpc', 'id', 'method'],
                  properties: {
                    jsonrpc: { type: 'string', enum: ['2.0'] },
                    id: { type: 'integer' },
                    method: { type: 'string', enum: ['initialize', 'tools/list', 'tools/call'] },
                    params: { type: 'object' },
                  },
                },
              },
            },
          },
          responses: {
            '202': { description: 'Message accepted. Response delivered via SSE stream.' },
            '402': { description: 'Payment Required' },
          },
        },
      },
    },
  });
});

// SSE endpoint (free - needed for session establishment)
app.get('/sse', async (req, res) => {
  try {
    const mcpResp = await fetch(`${MCP_BASE}/sse`, {
      headers: { 'Accept': 'text/event-stream' }
    });
    res.set({
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });
    mcpResp.body.pipe(res);
  } catch (e) {
    res.status(500).json({ error: 'MCP proxy error', detail: e.message });
  }
});

// Messages endpoint (paid - $0.01 USDC per call)
app.post('/messages', x402Middleware, async (req, res) => {
  try {
    const url = new URL(`${MCP_BASE}/messages`);
    if (req.query.sessionId) {
      url.searchParams.set('sessionId', req.query.sessionId);
    }
    const mcpResp = await fetch(url.toString(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body)
    });
    const text = await mcpResp.text();
    res.status(mcpResp.status).send(text);
  } catch (e) {
    res.status(500).json({ error: 'MCP proxy error', detail: e.message });
  }
});

// Legacy /query endpoint (paid)
app.post('/query', x402Middleware, async (req, res) => {
  try {
    const url = new URL(`${MCP_BASE}/messages`);
    if (req.query.sessionId) {
      url.searchParams.set('sessionId', req.query.sessionId);
    }
    const mcpResp = await fetch(url.toString(), {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(req.body)
    });
    const text = await mcpResp.text();
    res.status(mcpResp.status).send(text);
  } catch (e) {
    res.status(500).json({ error: 'MCP proxy error', detail: e.message });
  }
});

const PORT = process.env.PORT || 8080;

/** Ensure @ampersend_ai/ampersend-sdk resolves and core factories exist (SDK is ESM-only). */
async function verifyAmpersendSdk() {
  const sdk = await import('@ampersend_ai/ampersend-sdk');
  const required = [
    'createAmpersendHttpClient',
    'createAmpersendTreasurer',
    'createAmpersendProxy',
    'createAmpersendMcpClient',
  ];
  const missing = required.filter((name) => typeof sdk[name] !== 'function');
  if (missing.length) {
    console.warn('@ampersend_ai/ampersend-sdk: unexpected exports (missing):', missing.join(', '));
  } else {
    console.log('@ampersend_ai/ampersend-sdk: OK (x402/MCP factories available)');
  }
}

function startListening(paymentGatingLabel) {
  app.listen(PORT, () => {
    console.log(`x402 proxy listening on http://0.0.0.0:${PORT}${paymentGatingLabel}`);
  });
}

initX402()
  .then(() =>
    verifyAmpersendSdk().catch((e) =>
      console.warn('@ampersend_ai/ampersend-sdk:', e.message),
    ),
  )
  .then(() => startListening(''))
  .catch((err) => {
    console.error('x402 init failed, starting without payment gating:', err.message);
    verifyAmpersendSdk()
      .catch((e) => console.warn('@ampersend_ai/ampersend-sdk:', e.message))
      .finally(() => startListening(' (NO payment gating)'));
  });
