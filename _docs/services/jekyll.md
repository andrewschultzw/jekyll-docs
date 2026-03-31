---
layout: default
title: Jekyll Docs Site
parent: Docs
nav_order: 1
---

# Jekyll Documentation Site

**Container:** CT 114
**Port:** 80
**Subdomain:** docs.schultzsolutions.tech

## Overview

Self-hosted Jekyll site for homelab documentation and build logs. Serves static HTML built from markdown files in the `jekyll-docs` GitHub repo.

## Stack

- Jekyll 4.x with Just the Docs theme
- Ruby + Bundler
- Nginx serving static files

## Paths

| Path | Purpose |
|------|---------|
| `/opt/jekyll/site/` | Git repo clone |
| `/opt/jekyll/rebuild.sh` | Build script |
| `/var/www/jekyll/_site/` | Built output |

## Rebuilding

From CT 300:
```bash
ssh root@<CT114_IP> /opt/jekyll/rebuild.sh
```

Or directly on CT 114:
```bash
/opt/jekyll/rebuild.sh
```

## Adding Content

1. Edit markdown files in `/root/jekyll-docs/` on CT 300
2. Commit and push to GitHub
3. Trigger rebuild on CT 114
