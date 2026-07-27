# mitthuai relay

The tunnel between Claude and a user's Mac. It does **identity + routing only** —
it never stores anyone's memory and never reads anyone's email.

```
Sign in with Google (openid/email/profile)         Claude.ai web / Code
        │ identity only                                   │  POST /mcp (Bearer account token)
        ▼                                                 ▼
   /pair → /auth/google → mints account token   ──►   this relay   ──WSS /agent──►  user's Mac
                                                        routes by account            (runs MCP locally,
                                                                                       returns snippets)
```

## Run locally

```bash
cd relay
npm install
GOOGLE_CLIENT_ID=... GOOGLE_CLIENT_SECRET=... BASE_URL=http://localhost:8080 npm start
```

## Environment

| Var | Meaning |
|---|---|
| `PORT` | Listen port (default 8080) |
| `BASE_URL` | Public base URL, e.g. `https://relay.mitthuai.com` |
| `GOOGLE_CLIENT_ID` | Google OAuth client (Web application) |
| `GOOGLE_CLIENT_SECRET` | Google OAuth client secret |

Google Cloud → APIs & Services → Credentials → OAuth client (Web application).
Authorized redirect URI: `${BASE_URL}/auth/google/callback`.
Scopes: `openid email profile` only — **no Gmail scopes**, so no security
assessment and no restricted-scope verification.

## Endpoints

- `GET /pair?device_id=&name=` — pairing page (app opens this in the browser).
- `GET /auth/google` / `GET /auth/google/callback` — Google Sign-In.
- `GET /api/device-token?device_id=` — one-time token pickup for the app.
- `POST /mcp` (`Authorization: Bearer <account token>`) — forwards a JSON-RPC
  message to the account's paired Mac and returns the response.
- `WS /agent` (`Authorization: Bearer <account token>`) — the desktop app's
  outbound tunnel.

## Wiring Claude

- **Claude Code / Desktop** can use the relay today with header auth:
  ```bash
  claude mcp add --transport http mitthuai https://relay.mitthuai.com/mcp \
    --header "Authorization: Bearer <account token>"
  ```
- **Claude.ai web** custom connectors authenticate via **OAuth 2.1** (with
  dynamic client registration + PKCE). That flow is the documented next step:
  add `/authorize`, `/token`, `/register`, and
  `/.well-known/oauth-authorization-server` endpoints here, federating login to
  the existing Google Sign-In, and issuing the same account tokens. The routing
  and tunnel below it are already in place.

## Production notes

- Replace the in-memory `Map`s with a database/Redis; move the agent registry to
  Redis pub/sub if you run more than one instance (or use sticky sessions).
- Terminate TLS at your platform (Cloud Run, Fly, a reverse proxy).
- Add rate limiting and per-account connection caps.
- Log connection metadata only — never message contents.
