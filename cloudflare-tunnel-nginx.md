# Cloudflare Tunnel + Wildcard Subdomain + Dynamic Port Proxy

## Goal

Expose unlimited local ports using wildcard subdomain.

Example:

```
3000.local.canngo.uk → localhost:3000
3004.local.canngo.uk → localhost:3004
6060.local.canngo.uk → localhost:6060
```

---

# 1. Add domain to Cloudflare

If `canngo.uk` is not on Cloudflare yet:

1. Create Cloudflare account
2. Add domain `canngo.uk`
3. Change nameservers at your registrar to Cloudflare

Wait until domain becomes **Active**.

---

# 2. Create wildcard DNS record

Go to:

```
Cloudflare Dashboard
→ DNS
```

Add record:

```
Type: CNAME
Name: *.local
Target: tunnel-id.cfargotunnel.com
Proxy: ON
```

(Cloudflare may auto-create this later using CLI)

---

# 3. Install cloudflared

Mac:

```
brew install cloudflared
```

Linux:

```
sudo apt install cloudflared
```

Check:

```
cloudflared --version
```

---

# 4. Login Cloudflare

```
cloudflared tunnel login
```

Browser will open.

Authorize the domain:

```
canngo.uk
```

---

# 5. Create tunnel

```
cloudflared tunnel create dev-tunnel
```

Example output:

```
Tunnel ID: 12345678-abcd
Credentials file:
/Users/can/.cloudflared/12345678-abcd.json
```

---

# 6. Create tunnel config

Create file:

```
~/.cloudflared/config.yml
```

Example:

```yaml
tunnel: dev-tunnel
credentials-file: /Users/can/.cloudflared/12345678-abcd.json

ingress:
  - hostname: "*.local.canngo.uk"
    service: http://localhost:8080

  - service: http_status:404
```

This means:

```
*.local.canngo.uk → localhost:8080
```

---

# 7. Route DNS to tunnel

Run:

```
cloudflared tunnel route dns dev-tunnel "*.local.canngo.uk"
```

Cloudflare will automatically create the DNS record.

---

# 8. Install Nginx

Mac:

```
brew install nginx
```

Ubuntu:

```
sudo apt install nginx
```

---

# 9. Configure dynamic port proxy

Edit nginx config:

```
/usr/local/etc/nginx/nginx.conf
```

Add server:

```
server {
    listen 8080;

    server_name ~^(?<port>\d+)\.local\.canngo\.uk$;

    location / {
        proxy_pass http://127.0.0.1:$port;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

Explanation:

```
3000.local.canngo.uk → port=3000 → proxy localhost:3000
```

---

# 10. Restart Nginx

Mac:

```
brew services restart nginx
```

Linux:

```
sudo systemctl restart nginx
```

---

# 11. Run Cloudflare Tunnel

```
cloudflared tunnel run dev-tunnel
```

---

# 12. Test

Start any server.

Example:

```
node server.js
PORT=3000
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

# 13. Optional: Auto start tunnel

Install as service:

```
cloudflared service install
```

Or run with PM2:

```
pm2 start "cloudflared tunnel run dev-tunnel" --name tunnel
pm2 save
pm2 startup
```

---

# Result

You now have unlimited local ports exposed.

Examples:

```
3000.local.canngo.uk → localhost:3000
3004.local.canngo.uk → localhost:3004
6060.local.canngo.uk → localhost:6060
5173.local.canngo.uk → localhost:5173
```

No extra configuration required when new port is created.
