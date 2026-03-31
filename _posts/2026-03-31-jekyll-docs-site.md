---
layout: post
title: "Jekyll Docs Site Setup"
date: 2026-03-31
---

Set up a self-hosted Jekyll documentation site on CT 114 for homelab reference docs and build logs.

## What Was Done

- Created Debian LXC container (CT 114) on Proxmox
- Installed Ruby, Jekyll, Bundler, and Nginx
- Configured Just the Docs theme with dark mode and search
- Set up rebuild.sh for git pull + jekyll build deploys
- Configured NPM proxy host at docs.schultzsolutions.tech
- Added SSH key from CT 300 for remote rebuild triggers

## Architecture

Content authored on CT 300, pushed to GitHub, pulled and built on CT 114, served by Nginx.
