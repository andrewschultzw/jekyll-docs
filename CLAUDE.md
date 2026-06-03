# jekyll-docs

Internal homelab documentation + build-log site ("Schultz Solutions Docs"), served at docs.schultzsolutions.tech.

## Stack
- Jekyll `~> 4.3` (Ruby + Bundler), `just-the-docs` theme, dark color scheme, search enabled.
- Static output served by Nginx. No CI; no test suite (content site).

## Commands
```bash
bundle install                 # install gems
bundle exec jekyll serve       # local preview at http://localhost:4000 (live reload)
bundle exec jekyll build       # build to ./_site
```

## Deploy
Production builds run on the host (CT 114) via `rebuild.sh`, NOT GitHub Pages:
`git pull origin main` → `bundle install` → `bundle exec jekyll build --destination /var/www/jekyll/_site`.
Workflow: edit + push to `main` from CT 300 → trigger rebuild on CT 114:
`ssh root@<CT114_IP> /opt/jekyll/rebuild.sh` (or run `/opt/jekyll/rebuild.sh` on CT 114 directly).
Do not edit `rebuild.sh` paths casually — they're absolute to the CT 114 host (`/opt/jekyll/site`, `/var/www/jekyll/_site`). `rebuild.sh` is excluded from the build in `_config.yml`.

## Structure
- `_config.yml` — site, theme, search, and collection config.
- `_docs/` — `docs` collection (outputs `/docs/...`), grouped into `services/`, `networking/`, `infrastructure/`.
- `_posts/` — Build Log entries, named `YYYY-MM-DD-slug.md`.
- `index.md`, `docs.md`, `blog.md` — top-level nav landing pages.

## Conventions
- Doc pages use just-the-docs nav front matter: `layout: default`, `title`, `parent`, `grand_parent`, `nav_order`.
- New doc category = new folder under `_docs/<category>/` with an `index.md` carrying nav front matter.
- `_docs` is a non-default collection — content there won't appear unless front matter wires it into the nav tree.

## Gotchas
- No `Gemfile.lock` is committed; gem versions can drift between machines. Consider committing one if builds diverge.
- Internal-facing site — keep homelab IPs/hostnames/secrets out of published pages.
