const express = require('express');
const fetch = require('node-fetch');
const app = express();
app.use(express.json());

const MCP_BASE = process.env.MCP_HOST || 'http://mcp:8000';

async function ensurePaid(req) {
  // TODO: integrate Ampersend SDK to verify payment
  return true;
}

// Proxy SSE endpoint (streaming)
app.get('/sse', async (req, res) => {
  const paid = await ensurePaid(req);
  if (!paid) {
    return res.status(402).json({ error: 'Payment required' });
  }
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

// Proxy messages endpoint
app.post('/messages', async (req, res) => {
  const paid = await ensurePaid(req);
  if (!paid) {
    return res.status(402).json({ error: 'Payment required' });
  }
  try {
    const url = new URL(`${MCP_BASE}/messages`);
    // Forward sessionId query param
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

// Keep legacy /query endpoint as pass-through to /messages
app.post('/query', async (req, res) => {
  const paid = await ensurePaid(req);
  if (!paid) {
    return res.status(402).json({ error: 'Payment required' });
  }
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
app.listen(PORT, () => console.log(`Ampersend front proxy listening on http://0.0.0.0:${PORT}`));
