#!/bin/bash
set -e
cd /opt/jekyll/site
git pull origin main
bundle install --quiet
bundle exec jekyll build --destination /var/www/jekyll/_site
echo "Rebuild completed at $(date)"
