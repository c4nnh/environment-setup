# Cloudflare Tunnel + Wildcard Subdomain + Caddy (Secure Dynamic Port Proxy)

## Goal

Expose selected local development ports using a predictable hostname pattern while **preventing sensitive ports from being exposed**.

Example:

```
local-3000.canngo.us → localhost:3000
local-3004.canngo.us → localhost:3004
local-5173.canngo.us → localhost:5173
```

Blocked example:

```
local-5432.canngo.us → ❌ blocked
local-6379.canngo.us → ❌ blocked
```

This prevents accidental exposure of databases or internal services.

---

# Recommended Pattern: `local-<port>.canngo.us`

For flexible development and webhooks, use a hostname pattern that includes the port:

```
local-3000.canngo.us → localhost:3000
local-3004.canngo.us → localhost:3004
local-3005.canngo.us → localhost:3005
local-3006.canngo.us → localhost:3006
```

Universal SSL for `canngo.us` already covers:

```
canngo.us
*.canngo.us
```

so all of the above hostnames are automatically covered by a valid certificate (no extra ACM needed).

We will route **all `*.canngo.us` traffic** to Caddy, and let Caddy:

- extract the port from the hostname (`local-<port>.canngo.us`)
- only allow a **whitelist of development ports**
- block all other ports with a 403

---

# Architecture

```
Internet
   ↓
Cloudflare DNS (*.canngo.us)
   ↓
Cloudflare Tunnel
   ↓
localhost:8080 (Caddy reverse proxy)
   ↓
Caddy validates allowed ports
   ↓
proxy → localhost:<port>
```

---

# Alternative: Tunnel Without Caddy

**You do not need Caddy.** Cloudflare Tunnel can map each subdomain to a port by listing multiple ingress rules. One hostname → one service URL.

### Tunnel-only config example

```yaml
# ~/.cloudflared/config.yml
tunnel: local-tunnel
credentials-file: /Users/your-user/.cloudflared/xxxxxxxx-xxxx.json

ingress:
  - hostname: "*.canngo.us"
    service: http://localhost:8080

  - service: http_status:404
```

- Any hostname you **do not** list (e.g. `local-5432.canngo.us`) hits the last rule and returns 404 — so you still only expose what you define.
- No Caddy process; only `cloudflared` runs.
- To add a new port: add one ingress block and restart (or reload) the tunnel.

### Trade-offs

|                         | With Caddy                                        | Tunnel only                                                                         |
| ----------------------- | ------------------------------------------------- | ----------------------------------------------------------------------------------- |
| **Add new port**        | Edit Caddyfile, `caddy reload`                    | Edit config.yml, add ingress rule, restart tunnel                                   |
| **Cache / stale files** | Caddy sends `Cache-Control` + `CDN-Cache-Control` | Rely on Cloudflare Cache Rules (e.g. bypass for `local-*.canngo.us`) or app headers |
| **Invalid host header** | Caddy rewrites `Host` → `localhost:<port>`        | Fix per app (e.g. webpack `allowedHosts`)                                           |
| **Extra process**       | Caddy + cloudflared                               | Only cloudflared                                                                    |
| **Port whitelist**      | Single place in Caddyfile                         | Implicit: only listed hostnames work                                                |

Use **Tunnel only** if you want the simplest stack and are fine editing the tunnel config when adding ports. Use **Caddy** if you want one wildcard rule, central cache/header control, and Host rewriting so all dev servers work without per-app config.

---

# 1. Add Domain to Cloudflare

If `canngo.us` is not yet managed by Cloudflare:

1. Create a Cloudflare account
2. Add domain **canngo.us**
3. Change nameservers at your domain registrar to the Cloudflare nameservers

Wait until the domain status becomes **Active**.

---

# 2. Install Cloudflare Tunnel

### Mac

```bash
brew install cloudflared
```

### Ubuntu / Debian

```bash
sudo apt install cloudflared
```

Verify installation:

```bash
cloudflared --version
```

---

# 3. Authenticate Cloudflare

Run:

```bash
cloudflared tunnel login
```

Your browser will open.

Authorize access to:

```
canngo.us
```

A credential file will be created locally.

---

# 4. Create Tunnel

Create a tunnel:

```bash
cloudflared tunnel create local-tunnel
```

Example output:

```
Tunnel ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
Credentials file:
~/.cloudflared/xxxxxxxx-xxxx.json
```

---

# 5. Create Wildcard DNS Route

Run:

```bash
cloudflared tunnel route dns local-tunnel "*.canngo.us"
```

Cloudflare will automatically create a DNS record:

```
*.canngo.us → local-tunnel
```

---

# 6. Install Caddy

### Mac

```bash
brew install caddy
```

### Ubuntu

```bash
sudo apt install caddy
```

Verify installation:

```bash
caddy version
```

---

# 7. Create Caddy Configuration

Create a file:

```
~/Caddyfile
```

Example configuration:

```
:8080 {
    map {http.request.host} {backend_port} {
        local-3004.canngo.us 3004
        local-3008.canngo.us 3008
        local-3002.canngo.us 3002
        local-3001.canngo.us 3001
        local-3009.canngo.us 3009
        default ""
    }

    @allowed expression `{backend_port} != ""`

    handle @allowed {
        reverse_proxy localhost:{backend_port}

        header Cache-Control "no-store, no-cache, must-revalidate, max-age=0"
        header CDN-Cache-Control "no-store"
    }

    handle {
        respond "Port not allowed" 403
    }
}

```

### What `header_up` and cache headers do

- **`header_up Host localhost:{backend_port}`** — Rewrites the `Host` header sent to the backend. Without this, the backend receives `Host: local-3004.canngo.us` which causes "Invalid host header" errors in dev servers like webpack-dev-server.
- **`Cache-Control "no-store, ..."`** — Tells browsers not to cache responses.
- **`CDN-Cache-Control "no-store"`** — Tells Cloudflare CDN specifically not to cache responses. Without this, Cloudflare caches static files (`.js`, `.css`, etc.) and serves stale content after rebuilds.

### Explanation

Allowed ports:

```
3000
3004
3005
3006
5173
6006
6060
```

Behavior:

| URL                  | Result                    |
| -------------------- | ------------------------- |
| local-3000.canngo.us | proxied to localhost:3000 |
| local-5173.canngo.us | proxied to localhost:5173 |
| local-5432.canngo.us | blocked (403)             |

This prevents accidental exposure of:

- PostgreSQL (5432)
- Redis (6379)
- MongoDB (27017)
- SSH (22)

---

# 8. Start Caddy

Run:

```bash
caddy run --config ~/Caddyfile
```

Caddy will listen on:

```
localhost:8080
```

---

# 9. Configure Cloudflare Tunnel

Create file:

```
~/.cloudflared/config.yml
```

Example:

```yaml
tunnel: local-tunnel
credentials-file: /Users/your-user/.cloudflared/xxxxxxxx-xxxx.json

ingress:
  - hostname: "*.canngo.us"
    service: http://localhost:8080
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true

  - service: http_status:404
```

### What `originRequest` options do

- **`noTLSVerify: true`** — Skips TLS certificate verification when connecting to the origin (Caddy). Not strictly required when Caddy listens on plain HTTP (`:8080`), but prevents issues if you later switch to HTTPS.
- **`disableChunkedEncoding: true`** — Disables chunked transfer encoding between the tunnel and origin. This can fix issues with certain dev servers (e.g. webpack-dev-server, HMR streams) that do not handle chunked encoding well through the tunnel.

---

# 10. Start the Tunnel

Run:

```bash
cloudflared tunnel run local-tunnel
```

Now all traffic to:

```
*.local.canngo.us
```

will route to Caddy.

---

# 11. Test

Start a local server.

Example Express server:

```bash
PORT=3000 node app.js
```

Open browser:

```
https://local-3000.canngo.us
```

Expected result:

```
localhost:3000
```

---

# 11.1 Troubleshooting: Certificate and DNS

**"This hostname is not covered by a certificate" (Cloudflare dashboard)**

1. **Check DNS record name**  
   For zone `canngo.us`, the wildcard record must resolve to `*.local.canngo.us`. In Cloudflare the **Name** field is often shown as `*.local` (the full hostname is then `*.local.canngo.us`). If you created a record with a different name, fix it so the FQDN is exactly `*.local.canngo.us`.

2. **Trigger or wait for Edge certificate**

   - In Cloudflare: **SSL/TLS** → **Edge Certificates**.
   - Ensure **Universal SSL** is enabled.
   - Optionally use **Edge Certificates** → **Order Advanced Certificate** and add `*.local.canngo.us` (and `canngo.us` if needed).
   - After changing DNS or adding the hostname, it can take a few minutes for the certificate to be issued.

3. **SSL/TLS mode**  
   Set encryption mode to **Full** or **Full (strict)**. For tunnels to Caddy on `localhost:8080`, **Full** is enough (no origin certificate required).

4. **Verify from CLI**
   ```bash
   curl -vI https://local-3004.canngo.us
   ```
   Confirm the response is not a certificate error and that the request reaches your app.

---

# 12. Example Development Services

| Service   | Local Port | URL                          |
| --------- | ---------- | ---------------------------- |
| API       | 3000       | https://local-3000.canngo.us |
| Admin     | 3004       | https://local-3004.canngo.us |
| Job       | 3005       | https://local-3005.canngo.us |
| Worker    | 3006       | https://local-3006.canngo.us |
| Vite Dev  | 5173       | https://local-5173.canngo.us |
| Storybook | 6006       | https://local-6006.canngo.us |

---

# 13. Add a New Allowed Port

If you want to expose a **new development port**, edit the Caddyfile.

Example: allow **port 4000**

Open config:

```
nano ~/Caddyfile
```

Find this line:

```
@allowed header_regexp port Host ^local-(?P<port>(3000|3004|3005|3006|5173|6006))\.canngo\.us$
```

Add the new port:

```
@allowed header_regexp port Host ^local-(?P<port>(3000|3004|3005|3006|4000|5173|6006))\.canngo\.us$
```

Save file and reload Caddy:

```
caddy reload --config ~/Caddyfile
```

Now this will work:

```
https://local-4000.canngo.us
```

---

# 14. Auto Start Tunnel and Caddy (Optional)

You can keep both **Caddy** and **Cloudflare Tunnel** running automatically so that your dev hostnames work without manual steps.

## 14.1 Caddy as a background service (macOS, Homebrew)

If you installed Caddy via Homebrew:

```bash
brew services start caddy     # start at login and run in background
brew services list            # confirm caddy is running
```

To stop:

```bash
brew services stop caddy
```

If `brew services list` shows `caddy error 1`, it usually means the Homebrew service is using a different (or invalid) Caddyfile. Copy your working `~/Caddyfile` to the Homebrew etc directory and restart:

```bash
cp ~/Caddyfile "$(brew --prefix)/etc/Caddyfile"
brew services restart caddy
brew services list
```

If it still fails, check the service log:

```bash
tail -n 50 ~/Library/Logs/homebrew.mxcl.caddy.log
```

## 14.2 Cloudflared as a background service

### Option A – Official service

Install the tunnel as a system service:

```bash
cloudflared service install
```

Cloudflared will automatically run `cloudflared tunnel run local-tunnel` in the background.

If you previously tried to manage `cloudflared` with Homebrew and see:

```bash
brew services list
# ...
cloudflared error 1
```

then stop the Homebrew service and let the official service own it:

```bash
brew services stop cloudflared
```

After that, `cloudflared` will not appear as `started` in `brew services list`, but it will still run in the background via `cloudflared service install`.

### Option B – PM2 (Node-based process manager)

If you already use Node tooling, you can manage the tunnel via PM2:

```bash
pm2 start "cloudflared tunnel run local-tunnel" --name local-tunnel
pm2 save
pm2 startup
```

This will restart the tunnel automatically after reboot.

## 14.3 Dev script: start tunnel + Caddy + app together

If you prefer to start everything only when you run your app, create a small script, for example:

```bash
#!/usr/bin/env bash

# Start Caddy if it is not running
if ! pgrep -x "caddy" > /dev/null; then
  caddy run --config "$HOME/Caddyfile" &
fi

# Start Cloudflare tunnel if it is not running
if ! pgrep -x "cloudflared" > 0; then
  cloudflared tunnel run local-tunnel &
fi

# Finally start your app (example: Express on port 3004)
PORT=3004 node app.js
```

Make it executable and run:

```bash
chmod +x dev.sh
./dev.sh
```

---

# 15. Optional Security (Recommended)

You may optionally enable **Cloudflare Zero Trust Access** to require login before accessing dev services.

Example:

```
Google login required
GitHub login required
```

This prevents unauthorized users from accessing your development environment.

---

# Result

You now have a **secure dynamic development gateway**.

Example:

```
3000.local.canngo.us → localhost:3000
local-5173.canngo.us → localhost:5173
local-6006.canngo.us → localhost:6006
```

Ports not explicitly allowed will be blocked automatically.

This setup works well for:

- Express / NestJS APIs
- React / Vite dev servers
- Storybook
- Webhook testing (Stripe, Shopify, GitHub)
- Microservice local development

---
