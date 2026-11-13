#!/usr/bin/env bash
set -euo pipefail
CONF=/etc/nginx/sites-available/production-devops-app
CUR=$(grep -oP 'proxy_pass http://127\.0\.0\.1:\K[0-9]+' "$CONF")
if [ "$CUR" = "13002" ]; then PREV=13001; else PREV=13002; fi
curl -fsS "http://127.0.0.1:$PREV/health" >/dev/null || { echo "previous release not running"; exit 1; }
sed -i -E "s#(proxy_pass http://127\.0\.0\.1:)[0-9]+;#\1$PREV;#" "$CONF"
nginx -t && systemctl reload nginx
echo "rolled back: $CUR -> $PREV"
