# Cloudflare Tunnel + Wildcard Subdomain + Caddy (Secure Dynamic Port Proxy)

## Goal

Expose selected local development ports using a wildcard subdomain while **preventing sensitive ports from being exposed**.

Example:

```
3000.local.canngo.uk → localhost:3000
3004.local.canngo.uk → localhost:3004
5173.local.canngo.uk → localhost:5173
```

Blocked example:

```
5432.local.canngo.uk → ❌ blocked
6379.local.canngo.uk → ❌ blocked
```

This prevents accidental exposure of databases or internal services.

---

# Architecture

```
Internet
   ↓
Cloudflare DNS (*.local.canngo.uk)
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

If `canngo.uk` is not yet managed by Cloudflare:

1. Create a Cloudflare account
2. Add domain **canngo.uk**
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
canngo.uk
```

A credential file will be created locally.

---

# 4. Create Tunnel

Create a tunnel:

```bash
cloudflared tunnel create dev-tunnel
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
cloudflared tunnel route dns dev-tunnel "*.local.canngo.uk"
```

Cloudflare will automatically create a DNS record:

```
*.local.canngo.uk → tunnel
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

    # Allowed development ports
    @allowed header_regexp port Host ^(?P<port>(3000|3004|5173|6006|6060))\.local\.canngo\.uk$

    reverse_proxy @allowed localhost:{re.port}

    respond "Port not allowed" 403

}
```

### Explanation

Allowed ports:

```
3000
3004
5173
6006
6060
```

Behavior:

| URL                  | Result                    |
| -------------------- | ------------------------- |
| 3000.local.canngo.uk | proxied to localhost:3000 |
| 5173.local.canngo.uk | proxied to localhost:5173 |
| 5432.local.canngo.uk | blocked (403)             |

This prevents accidental exposure of:

* PostgreSQL (5432)
* Redis (6379)
* MongoDB (27017)
* SSH (22)

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
tunnel: dev-tunnel
credentials-file: /Users/your-user/.cloudflared/xxxxxxxx-xxxx.json

ingress:
  - hostname: "*.local.canngo.uk"
    service: http://localhost:8080

  - service: http_status:404
```

---

# 10. Start the Tunnel

Run:

```bash
cloudflared tunnel run dev-tunnel
```

Now all traffic to:

```
*.local.canngo.uk
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
https://3000.local.canngo.uk
```

Expected result:

```
localhost:3000
```

---

# 12. Example Development Services

| Service   | Local Port | URL                          |
| --------- | ---------- | ---------------------------- |
| API       | 3000       | https://3000.local.canngo.uk |
| Admin     | 3004       | https://3004.local.canngo.uk |
| Vite Dev  | 5173       | https://5173.local.canngo.uk |
| Storybook | 6006       | https://6006.local.canngo.uk |
| Worker    | 6060       | https://6060.local.canngo.uk |

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
@allowed host_regexp port ^(?P<port>(3000|3004|5173|6006|6060))\.local\.canngo\.uk$
```

Add the new port:

```
@allowed host_regexp port ^(?P<port>(3000|3004|4000|5173|6006|6060))\.local\.canngo\.uk$
```

Save file and reload Caddy:

```
caddy reload --config ~/Caddyfile
```

Now this will work:

```
https://4000.local.canngo.uk
```

---

# 14. Auto Start Tunnel (Optional)

Install tunnel as a system service:

```
cloudflared service install
```

Or use PM2:

```
pm2 start "cloudflared tunnel run dev-tunnel" --name tunnel
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
3000.local.canngo.uk → localhost:3000
5173.local.canngo.uk → localhost:5173
6006.local.canngo.uk → localhost:6006
```

Ports not explicitly allowed will be blocked automatically.

This setup works well for:

* Express / NestJS APIs
* React / Vite dev servers
* Storybook
* Webhook testing (Stripe, Shopify, GitHub)
* Microservice local development

---
