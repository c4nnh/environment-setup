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
        local-3005.canngo.us 3005
        local-3006.canngo.us 3006
        local-3007.canngo.us 3007
        default ""
    }

    @allowed expression `{backend_port} != ""`

    handle @allowed {
        reverse_proxy localhost:{backend_port}
    }

    handle {
        respond "Port not allowed" 403
    }
}
```

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

  - service: http_status:404
```

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

# 14. Auto Start Tunnel (Optional)

Install tunnel as a system service:

```
cloudflared service install
```

Or use PM2:

```
pm2 start "cloudflared tunnel run local-tunnel" --name tunnel
pm2 save
pm2 startup
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
