// mitthuai relay — the tunnel between Claude and a user's Mac.
//
// Responsibilities (and, importantly, NON-responsibilities):
//   • Identity: "Sign in with Google" (scopes: openid email profile only —
//     NO Gmail reading). Binds a device_id to an account and mints an account
//     token the desktop app uses to open its tunnel.
//   • Registry: which Mac (agent WebSocket) belongs to which account.
//   • Forward: a Claude MCP call → the account's Mac → response back.
//
// It NEVER stores the user's memory and NEVER reads their email. Only the
// query and the returned snippets pass through, in transit.
//
// This is a runnable scaffold. In-memory maps are used for clarity; for
// production, back them with a database/Redis and run multiple instances
// behind a sticky-session load balancer (or move the registry to Redis pub/sub).

import http from 'node:http';
import crypto from 'node:crypto';
import { WebSocketServer } from 'ws';

const PORT = process.env.PORT || 8080;
const BASE_URL = process.env.BASE_URL || `http://localhost:${PORT}`;
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '';
const GOOGLE_CLIENT_SECRET = process.env.GOOGLE_CLIENT_SECRET || '';

// --- In-memory state (replace with a DB in production) ---------------------
const accountsByEmail = new Map();   // email -> { id, email }
const tokenToAccount  = new Map();   // accountToken -> accountId
const deviceToAccount = new Map();   // device_id -> accountId
const deviceToken     = new Map();   // device_id -> accountToken (one-time pickup)
const agents          = new Map();   // accountId -> ws (the paired Mac)
const pending         = new Map();   // rid -> { resolve, timer }

const rand = (n = 24) => crypto.randomBytes(n).toString('hex');

function accountForEmail(email) {
  let acct = accountsByEmail.get(email);
  if (!acct) { acct = { id: rand(8), email }; accountsByEmail.set(email, acct); }
  return acct;
}

// --- Tiny HTTP helpers -----------------------------------------------------
function send(res, code, body, headers = {}) {
  const data = typeof body === 'string' ? body : JSON.stringify(body);
  res.writeHead(code, { 'Content-Type': typeof body === 'string' ? 'text/html; charset=utf-8' : 'application/json', ...headers });
  res.end(data);
}
function bearer(req) {
  const h = req.headers['authorization'] || '';
  return h.startsWith('Bearer ') ? h.slice(7) : null;
}
function readBody(req) {
  return new Promise((resolve) => {
    let b = '';
    req.on('data', (c) => { b += c; if (b.length > 4e6) req.destroy(); });
    req.on('end', () => resolve(b));
  });
}

// --- Google Sign-In (identity only) ----------------------------------------
function googleAuthURL(deviceId) {
  const p = new URLSearchParams({
    client_id: GOOGLE_CLIENT_ID,
    redirect_uri: `${BASE_URL}/auth/google/callback`,
    response_type: 'code',
    scope: 'openid email profile',
    access_type: 'online',
    state: deviceId
  });
  return `https://accounts.google.com/o/oauth2/v2/auth?${p}`;
}

async function googleExchange(code) {
  const r = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      code,
      client_id: GOOGLE_CLIENT_ID,
      client_secret: GOOGLE_CLIENT_SECRET,
      redirect_uri: `${BASE_URL}/auth/google/callback`,
      grant_type: 'authorization_code'
    })
  });
  const tok = await r.json();
  if (!tok.access_token) throw new Error('token exchange failed');
  const ui = await fetch('https://openidconnect.googleapis.com/v1/userinfo', {
    headers: { Authorization: `Bearer ${tok.access_token}` }
  });
  return ui.json(); // { sub, email, name, ... }
}

// --- HTTP server -----------------------------------------------------------
const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, BASE_URL);

  // Health check.
  if (url.pathname === '/' ) return send(res, 200, 'mitthuai relay: ok');

  // 1) Device pairing page → send the user to Google.
  if (url.pathname === '/pair') {
    const deviceId = url.searchParams.get('device_id') || '';
    if (!deviceId) return send(res, 400, 'missing device_id');
    if (!GOOGLE_CLIENT_ID) return send(res, 500, 'relay not configured (GOOGLE_CLIENT_ID)');
    return send(res, 200,
      `<html><body style="font-family:sans-serif;background:#0e0f13;color:#eee;padding:3em;text-align:center">
       <h2>Connect this Mac to MitthuAI</h2>
       <p>Sign in to link this device. We only use Google for login — we never read your email.</p>
       <p style="margin-top:2em"><a href="/auth/google?device_id=${encodeURIComponent(deviceId)}"
          style="background:#7c6cff;color:#fff;padding:12px 22px;border-radius:10px;text-decoration:none">Sign in with Google</a></p>
       </body></html>`);
  }

  // 2) Kick off Google OAuth.
  if (url.pathname === '/auth/google') {
    const deviceId = url.searchParams.get('device_id') || '';
    if (!deviceId) return send(res, 400, 'missing device_id');
    res.writeHead(302, { Location: googleAuthURL(deviceId) });
    return res.end();
  }

  // 3) Google callback → bind device, mint account token.
  if (url.pathname === '/auth/google/callback') {
    const code = url.searchParams.get('code');
    const deviceId = url.searchParams.get('state') || '';
    if (!code || !deviceId) return send(res, 400, 'missing code/state');
    try {
      const profile = await googleExchange(code);
      const acct = accountForEmail(profile.email);
      const token = rand(24);
      tokenToAccount.set(token, acct.id);
      deviceToAccount.set(deviceId, acct.id);
      deviceToken.set(deviceId, token); // picked up once by the app, then cleared
      return send(res, 200,
        `<html><body style="font-family:sans-serif;background:#0e0f13;color:#eee;padding:3em;text-align:center">
         <h2>✅ Connected as ${profile.email}</h2>
         <p>You can return to the MitthuAI app — this Mac will connect within a minute.</p>
         </body></html>`);
    } catch (e) {
      return send(res, 500, 'sign-in failed');
    }
  }

  // 4) App polls for its account token after the user signs in.
  if (url.pathname === '/api/device-token') {
    const deviceId = url.searchParams.get('device_id') || '';
    const token = deviceToken.get(deviceId);
    if (!token) return send(res, 200, { token: null });
    deviceToken.delete(deviceId); // one-time pickup
    return send(res, 200, { token });
  }

  // 5) Claude MCP front door. Forwards a JSON-RPC message to the account's Mac.
  //    Auth: Bearer <account token>. (Claude Code/Desktop can pass this as a
  //    header today; wiring Claude.ai-web's OAuth flow is the documented next
  //    step — see README "Claude.ai web OAuth".)
  if (url.pathname === '/mcp' && req.method === 'POST') {
    const token = bearer(req);
    const accountId = token && tokenToAccount.get(token);
    if (!accountId) return send(res, 401, { error: 'unauthorized' });
    const ws = agents.get(accountId);
    if (!ws || ws.readyState !== ws.OPEN) return send(res, 503, { error: 'device offline' });

    const body = await readBody(req);
    let msg;
    try { msg = JSON.parse(body); } catch { return send(res, 400, { error: 'bad json' }); }

    // Notifications (no id) need no reply.
    const isNotification = msg && msg.id === undefined;
    const rid = rand(8);
    ws.send(JSON.stringify({ rid, mcp: msg }));
    if (isNotification) return send(res, 202, {});

    const response = await new Promise((resolve) => {
      const timer = setTimeout(() => { pending.delete(rid); resolve(null); }, 30000);
      pending.set(rid, { resolve, timer });
    });
    if (!response) return send(res, 504, { error: 'device timeout' });
    return send(res, 200, response);
  }

  send(res, 404, { error: 'not found' });
});

// --- WebSocket: the desktop apps (agents) ----------------------------------
const wss = new WebSocketServer({ server, path: '/agent' });
wss.on('connection', (ws, req) => {
  const token = (req.headers['authorization'] || '').replace(/^Bearer /, '');
  const accountId = tokenToAccount.get(token);
  if (!accountId) { ws.close(4001, 'unauthorized'); return; }

  agents.set(accountId, ws);
  const ping = setInterval(() => { try { ws.send(JSON.stringify({ type: 'ping' })); } catch {} }, 30000);

  ws.on('message', (raw) => {
    let obj; try { obj = JSON.parse(raw.toString()); } catch { return; }
    if (obj.type === 'pong' || obj.type === 'register') return;
    // Response to a forwarded MCP call.
    if (obj.rid && pending.has(obj.rid)) {
      const { resolve, timer } = pending.get(obj.rid);
      clearTimeout(timer); pending.delete(obj.rid);
      resolve(obj.mcp || null);
    }
  });

  ws.on('close', () => {
    clearInterval(ping);
    if (agents.get(accountId) === ws) agents.delete(accountId);
  });
});

server.listen(PORT, () => {
  console.log(`mitthuai relay listening on ${PORT} (base ${BASE_URL})`);
  if (!GOOGLE_CLIENT_ID) console.warn('WARNING: GOOGLE_CLIENT_ID not set — pairing disabled.');
});
