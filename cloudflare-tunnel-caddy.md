# Cloudflare Tunnel + Wildcard Subdomain + Caddy Dynamic Port Proxy

## Goal

Expose **unlimited local ports** using a wildcard subdomain and automatically map the **subdomain port → localhost port**.

Example:

```
3000.local.canngo.uk → localhost:3000
3004.local.canngo.uk → localhost:3004
6060.local.canngo.uk → localhost:6060
5173.local.canngo.uk → localhost:5173
```

You can run **any new port** without changing configuration.

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
Caddy extracts port from subdomain
   ↓
proxy → localhost:<port>
```

---

# 1. Add Domain to Cloudflare

If `canngo.uk` is not already managed by Cloudflare:

1. Create a Cloudflare account
2. Add domain **canngo.uk**
3. Change nameservers at your domain registrar to the Cloudflare nameservers

Wait until the domain status becomes **Active**.

---

# 2. Install Cloudflare Tunnel (cloudflared)

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

Authorize access to the domain:

```
canngo.uk
```

A credential file will be created locally.

---

# 4. Create a Tunnel

Create a named tunnel:

```bash
cloudflared tunnel create dev-tunnel
```

Example output:

```
Tunnel ID: 12345678-abcd-1234-abcd-1234567890ab
Credentials file:
/Users/can/.cloudflared/12345678-abcd-1234-abcd-1234567890ab.json
```

---

# 5. Route Wildcard DNS to Tunnel

Create a wildcard DNS route:

```bash
cloudflared tunnel route dns dev-tunnel "*.local.canngo.uk"
```

This automatically creates a DNS record in Cloudflare:

```
*.local.canngo.uk → tunnel
```

Now any subdomain under `local.canngo.uk` will go to the tunnel.

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

Verify:

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
*.local.canngo.uk:8080 {

    @port host_regexp port ^(?P<port>\d+)\.local\.canngo\.uk$

    reverse_proxy @port localhost:{re.port}

}
```

Explanation:

```
3000.local.canngo.uk
   ↓
extract port = 3000
   ↓
proxy to localhost:3000
```

---

# 8. Start Caddy

Run:

```bash
caddy run --config ~/Caddyfile
```

Caddy will start listening on:

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
credentials-file: /Users/can/.cloudflared/12345678-abcd-1234-abcd-1234567890ab.json

ingress:
  - hostname: "*.local.canngo.uk"
    service: http://localhost:8080

  - service: http_status:404
```

This means:

```
*.local.canngo.uk → localhost:8080 (Caddy)
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

is forwarded to **Caddy**.

---

# 11. Test

Start any local server.

Example Express server:

```bash
PORT=3000 node app.js
```

Open browser:

```
https://3000.local.canngo.uk
```

It will route to:

```
localhost:3000
```

---

# 12. Example Development Ports

| Service   | Local Port | URL                          |
| --------- | ---------- | ---------------------------- |
| API       | 3000       | https://3000.local.canngo.uk |
| Admin     | 3004       | https://3004.local.canngo.uk |
| Vite      | 5173       | https://5173.local.canngo.uk |
| Storybook | 6006       | https://6006.local.canngo.uk |
| Worker    | 6060       | https://6060.local.canngo.uk |

No configuration changes required when adding new ports.

---

# 13. Auto Start Tunnel (Optional)

### Option 1 — Install as system service

```
cloudflared service install
```

### Option 2 — Use PM2

```
pm2 start "cloudflared tunnel run dev-tunnel" --name tunnel
pm2 save
pm2 startup
```

---

# Result

You now have a **dynamic local development gateway**:

```
any-port.local.canngo.uk → localhost:any-port
```

Examples:

```
3000.local.canngo.uk → localhost:3000
5173.local.canngo.uk → localhost:5173
6006.local.canngo.uk → localhost:6006
```

This setup works perfectly for:

* Express / NestJS
* Vite / Next.js
* Storybook
* Webhook testing (Stripe, Shopify, GitHub)
* Microservice local development
