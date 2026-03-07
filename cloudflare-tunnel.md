# Cloudflare Tunnel + Wildcard Subdomain (Secure Dynamic Port Proxy)

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

Cloudflare Tunnel maps each hostname to a local port via ingress rules. Only hostnames you list are exposed; any other hostname (e.g. `local-5432.canngo.us`) hits the catch-all rule and returns 404.

---

# Architecture

```
Internet
   ↓
Cloudflare DNS (*.canngo.us)
   ↓
Cloudflare Tunnel (cloudflared)
   ↓
Ingress rules: hostname → localhost:<port>
   ↓
Local service (e.g. localhost:3000)
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

# 6. Configure Cloudflare Tunnel

Create file:

```
~/.cloudflared/config.yml
```

Example (one hostname per port you want to expose):

```yaml
tunnel: local-tunnel
credentials-file: /Users/your-user/.cloudflared/xxxxxxxx-xxxx.json

ingress:
  - hostname: local-3000.canngo.us
    service: http://localhost:3000
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true
  - hostname: local-3001.canngo.us
    service: http://localhost:3001
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true
  - hostname: local-3002.canngo.us
    service: http://localhost:3002
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true
  - hostname: local-3004.canngo.us
    service: http://localhost:3004
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true
  - hostname: local-3008.canngo.us
    service: http://localhost:3008
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true
  - hostname: local-3009.canngo.us
    service: http://localhost:3009
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true
  # Add one block per port you want to expose

  - service: http_status:404
```

- Any hostname you **do not** list (e.g. `local-5432.canngo.us`) hits the last rule and returns 404 — so you only expose what you define.
- To add a new port: add one ingress block and restart (or reload) the tunnel.

### What `originRequest` options do

- **`noTLSVerify: true`** — Skips TLS certificate verification when connecting to the local service. Prevents issues if you later switch to HTTPS locally.
- **`disableChunkedEncoding: true`** — Disables chunked transfer encoding between the tunnel and origin. This can fix issues with certain dev servers (e.g. webpack-dev-server, HMR streams) that do not handle chunked encoding well through the tunnel.

---

# 7. Start the Tunnel

Run:

```bash
cloudflared tunnel run local-tunnel
```

Traffic to the hostnames you defined will route to the corresponding local ports.

---

# 8. Test

Start a local server.

Example Express server:

```bash
PORT=3000 node app.js
```

Open browser:

```
https://local-3000.canngo.us
```

Expected result: your app responds (same as localhost:3000).

---

# 8.1 Troubleshooting: Certificate and DNS

**"This hostname is not covered by a certificate" (Cloudflare dashboard)**

1. **Check DNS record name**  
   For zone `canngo.us`, the wildcard record must resolve to `*.canngo.us`. In Cloudflare the **Name** field is often shown as `*` (the full hostname is then `*.canngo.us`). If you created a record with a different name, fix it so the FQDN is exactly `*.canngo.us`.

2. **Trigger or wait for Edge certificate**

   - In Cloudflare: **SSL/TLS** → **Edge Certificates**.
   - Ensure **Universal SSL** is enabled.
   - Optionally use **Edge Certificates** → **Order Advanced Certificate** and add `*.canngo.us` (and `canngo.us` if needed).
   - After changing DNS or adding the hostname, it can take a few minutes for the certificate to be issued.

3. **SSL/TLS mode**  
   Set encryption mode to **Full** or **Full (strict)**. For tunnels to local HTTP services, **Full** is enough (no origin certificate required).

4. **Verify from CLI**
   ```bash
   curl -vI https://local-3004.canngo.us
   ```
   Confirm the response is not a certificate error and that the request reaches your app.

---

# 9. Example Development Services

| Service   | Local Port | URL                          |
| --------- | ---------- | ---------------------------- |
| API       | 3000       | https://local-3000.canngo.us |
| Admin     | 3004       | https://local-3004.canngo.us |
| Job       | 3005       | https://local-3005.canngo.us |
| Worker    | 3006       | https://local-3006.canngo.us |
| Vite Dev  | 5173       | https://local-5173.canngo.us |
| Storybook | 6006       | https://local-6006.canngo.us |

---

# 10. Add a New Allowed Port

To expose a **new development port**, edit the tunnel config and add an ingress block.

Example: allow **port 4000**

Open config:

```bash
nano ~/.cloudflared/config.yml
```

Add a new block before the catch-all `http_status:404` rule:

```yaml
  - hostname: local-4000.canngo.us
    service: http://localhost:4000
    originRequest:
      noTLSVerify: true
      disableChunkedEncoding: true
```

Restart the tunnel:

```bash
cloudflared tunnel run local-tunnel
```

(If running as a service, restart the service instead.)

Now:

```
https://local-4000.canngo.us
```

will proxy to localhost:4000.

## 10.1 Add port via script (cf-tunnel-add.sh)

To add a hostname and port without editing the config file by hand, use the helper script:

```bash
./cf-tunnel-add.sh <hostname> <service_url>
```

Example:

```bash
./cf-tunnel-add.sh local-3003.canngo.us http://localhost:3003
```

The script will:

1. Append the new ingress block to `~/.cloudflared/config.yml` (before the catch-all `http_status:404` rule).
2. Skip if the hostname is already present.
3. Restart the Cloudflare tunnel (stops the running `cloudflared` process and starts it again in the background).

Make the script executable once:

```bash
chmod +x cf-tunnel-add.sh
```

If you run the tunnel as a system service (e.g. `cloudflared service install`), the script’s restart may not affect the service. In that case, restart the service yourself after running the script (e.g. restart the service from your OS or PM2).

---

# 11. Auto Start Tunnel (Optional)

You can keep **Cloudflare Tunnel** running automatically so that your dev hostnames work without manual steps.

## 11.1 Official service

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

## 11.2 PM2 (Node-based process manager)

If you already use Node tooling, you can manage the tunnel via PM2:

```bash
pm2 start "cloudflared tunnel run local-tunnel" --name local-tunnel
pm2 save
pm2 startup
```

This will restart the tunnel automatically after reboot.

## 11.3 Dev script: start tunnel + app together

If you prefer to start the tunnel only when you run your app, create a small script, for example:

```bash
#!/usr/bin/env bash

# Start Cloudflare tunnel if it is not running
if ! pgrep -x "cloudflared" > /dev/null; then
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

# 12. Optional Security (Recommended)

You may optionally enable **Cloudflare Zero Trust Access** to require login before accessing dev services.

Example:

```
Google login required
GitHub login required
```

This prevents unauthorized users from accessing your development environment.

---

# Result

You now have a **secure development gateway** using only Cloudflare Tunnel.

Example:

```
local-3000.canngo.us → localhost:3000
local-5173.canngo.us → localhost:5173
local-6006.canngo.us → localhost:6006
```

Hostnames not listed in your ingress rules return 404. Ports not explicitly allowed are not exposed.

This setup works well for:

- Express / NestJS APIs
- React / Vite dev servers
- Storybook
- Webhook testing (Stripe, Shopify, GitHub)
- Microservice local development

---
