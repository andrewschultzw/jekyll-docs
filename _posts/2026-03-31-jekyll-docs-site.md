---
layout: post
title: "Setting Up a Jekyll Documentation Site"
date: 2026-03-31
---

A walkthrough of standing up a self-hosted Jekyll docs site on Proxmox, from container creation to first page load.

## Why Jekyll?

The homelab needed a dedicated place for reference docs (service configs, runbooks, troubleshooting notes) and project build logs. The existing Astro site with Lab Notes handles polished public posts — this Jekyll site is a more internal knowledge base, with the option to go public later.

Jekyll was chosen for its markdown-first workflow, rich theme ecosystem, and static output that's trivial to serve with Nginx.

## Architecture

```
CT 300 (authoring) ──git push──▶ GitHub repo (jekyll-docs)
                                        │
CT 114 (serving)   ◀──git pull──────────┘
                   │
                   ▼
           jekyll build → _site/
                   │
                   ▼
           Nginx serves _site/ on port 80
```

Content is authored on CT 300 (the Claude Code container), pushed to GitHub, then pulled and built on CT 114. This keeps the repo accessible from anywhere — not just the home network.

## Step 1: Create the LXC Container

Created CT 114 on Proxmox via the host shell:

```bash
pct create 114 local:vztmpl/debian-12-standard_12.12-1_amd64.tar.zst \
  --hostname jekyll \
  --storage local-lvm --rootfs local-lvm:4 \
  --cores 1 --memory 512 \
  --net0 name=eth0,bridge=vmbr0,ip=dhcp \
  --unprivileged 1 --start 1 --onboot 1
```

Container specs: Debian 12, 4 GB disk, 1 core, 512 MB RAM, DHCP networking. Assigned IP: **192.168.1.243**.

Added the CT 300 SSH key for remote management:

```bash
pct exec 114 -- mkdir -p /root/.ssh
pct exec 114 -- bash -c 'echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI... claude@ct300" >> /root/.ssh/authorized_keys'
pct exec 114 -- chmod 700 /root/.ssh
pct exec 114 -- chmod 600 /root/.ssh/authorized_keys
```

## Step 2: Install Dependencies

All done via SSH from CT 300:

```bash
ssh root@192.168.1.243 'apt update && apt install -y ruby ruby-dev build-essential git nginx'
ssh root@192.168.1.243 'gem install bundler'
```

Final versions: Ruby 3.1.2, Bundler 2.6.9, Nginx 1.22.1, Git 2.39.5.

Created the directory structure:

```bash
ssh root@192.168.1.243 'mkdir -p /opt/jekyll /var/www/jekyll/_site'
```

- `/opt/jekyll/site/` — repo clone
- `/opt/jekyll/rebuild.sh` — build script
- `/var/www/jekyll/_site/` — built output served by Nginx

## Step 3: Create the Jekyll Site

Created the GitHub repo and all site files on CT 300:

```bash
gh repo create andrewschultzw/jekyll-docs --public --clone
```

### Key files

**Gemfile** — Jekyll + Just the Docs theme:

```ruby
source "https://rubygems.org"

gem "jekyll", "~> 4.3"
gem "just-the-docs"
```

**_config.yml** — dark mode, search, docs collection:

```yaml
title: Schultz Solutions Docs
description: Homelab documentation and build logs
theme: just-the-docs
color_scheme: dark
search_enabled: true

collections:
  docs:
    permalink: "/:collection/:path/"
    output: true

just_the_docs:
  collections:
    docs:
      name: Docs
      nav_fold: true
```

### Content structure

- `_docs/services/` — per-service setup docs
- `_docs/networking/` — network topology, switches, DNS
- `_docs/infrastructure/` — Proxmox, storage, hardware
- `_posts/` — build logs like this one

### rebuild.sh

```bash
#!/bin/bash
set -e
cd /opt/jekyll/site
git pull origin main
bundle install --quiet
bundle exec jekyll build --destination /var/www/jekyll/_site
echo "Rebuild completed at $(date)"
```

## Step 4: First Build

Cloned the repo on CT 114 and ran the first build:

```bash
ssh root@192.168.1.243 'git clone https://github.com/andrewschultzw/jekyll-docs.git /opt/jekyll/site'
ssh root@192.168.1.243 'cd /opt/jekyll/site && bundle install'
ssh root@192.168.1.243 'cp /opt/jekyll/site/rebuild.sh /opt/jekyll/rebuild.sh && chmod +x /opt/jekyll/rebuild.sh'
ssh root@192.168.1.243 '/opt/jekyll/rebuild.sh'
```

Jekyll 4.4.1 with Just the Docs 0.12.0 installed. Build completed with some Sass deprecation warnings (non-blocking — these are about `@import` being deprecated in a future Dart Sass version).

## Step 5: Configure Nginx

Wrote a simple vhost config to serve the built static files:

```nginx
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    root /var/www/jekyll/_site;
    index index.html;
    server_name _;

    location / {
        try_files $uri $uri/ $uri.html =404;
    }

    error_page 404 /404.html;
}
```

Enabled it and reloaded:

```bash
ssh root@192.168.1.243 'ln -sf /etc/nginx/sites-available/jekyll /etc/nginx/sites-enabled/jekyll'
ssh root@192.168.1.243 'rm -f /etc/nginx/sites-enabled/default'
ssh root@192.168.1.243 'nginx -t && systemctl reload nginx'
```

## Step 6: NPM Proxy Host

Created a proxy host in Nginx Proxy Manager for `docs.schultzsolutions.tech` forwarding to `192.168.1.243:80`. No Cloudflare tunnel yet — LAN-only access for now, ready to flip public when the time comes.

## Adding New Content

The workflow for adding docs or posts:

```bash
# On CT 300, edit files in /root/jekyll-docs/
vi _docs/services/new-service.md

# Commit and push
git add -A && git commit -m "docs: add new-service runbook" && git push

# Rebuild on CT 114
ssh root@192.168.1.243 /opt/jekyll/rebuild.sh
```

## Summary

| Detail | Value |
|--------|-------|
| Container | CT 114 |
| IP | 192.168.1.243 |
| Port | 80 |
| Subdomain | docs.schultzsolutions.tech |
| Theme | Just the Docs (dark mode) |
| Stack | Jekyll 4.4.1, Ruby 3.1.2, Nginx 1.22.1 |
| Repo | github.com/andrewschultzw/jekyll-docs |
