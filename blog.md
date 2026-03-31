---
layout: default
title: Build Log
nav_order: 3
---

# Build Log

Project write-ups and build notes, newest first.

{% for post in site.posts %}
- **{{ post.date | date: "%Y-%m-%d" }}** — [{{ post.title }}]({{ post.url }})
{% endfor %}
