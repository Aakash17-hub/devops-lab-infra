#!/usr/bin/env bash
set -euo pipefail

APP=production-devops-app
CONF=/etc/nginx/sites-available/$APP
TAG=${1:?usage: deploy.sh <build-number>}
IMAGE=$APP:$TAG

docker image inspect "$IMAGE" >/dev/null

CURRENT=$(grep -oP 'proxy_pass http://127\.0\.0\.1:\K[0-9]+' "$CONF")
if [ "$CURRENT" = "13002" ]; then NEW=13001; else NEW=13002; fi
[ "$NEW" = "13002" ] && ENVNAME=Green || ENVNAME=Blue
NAME=$APP-$NEW
echo "live=$CURRENT new=$NEW image=$IMAGE env=$ENVNAME"

# idle port ko free karo (purana release). Live ko kabhi nahi chhuna.
docker ps -aq --filter "publish=$NEW" | xargs -r docker rm -f
docker rm -f "$NAME" 2>/dev/null || true

docker run -d --name "$NAME" --restart unless-stopped \
  -p 127.0.0.1:$NEW:3000 \
  -e APP_VERSION="$TAG" -e APP_ENV="$ENVNAME" \
  "$IMAGE"

# 1) candidate healthy hai? (live ab bhi purane par hai)
ok=""
for i in $(seq 1 15); do
  if curl -fsS "http://127.0.0.1:$NEW/health" | grep -q "\"version\":\"$TAG\""; then ok=1; break; fi
  sleep 2
done
if [ -z "$ok" ]; then
  echo "candidate unhealthy, live ($CURRENT) untouched"
  docker logs --tail 30 "$NAME" || true
  docker rm -f "$NAME"
  exit 1
fi

# 2) Nginx switch, pehle config test
cp "$CONF" "$CONF.bak"
sed -i -E "s#(proxy_pass http://127\.0\.0\.1:)[0-9]+;#\1$NEW;#" "$CONF"
if ! nginx -t; then cp "$CONF.bak" "$CONF"; echo "nginx -t failed, reverted"; exit 1; fi
systemctl reload nginx

# 3) live endpoint verify, fail ho to turant rollback
sleep 1
if curl -fsS http://127.0.0.1:8080/health | grep -q "\"version\":\"$TAG\""; then
  echo "SWITCHED to $NEW. Rollback container still on $CURRENT"
else
  cp "$CONF.bak" "$CONF"; nginx -t && systemctl reload nginx
  echo "live verify failed, rolled back to $CURRENT"; exit 1
fi

# successful deploy ke baad: sirf 3 newest numeric tags rakho
docker images "$APP" --format '{{.Tag}}' | grep -E '^[0-9]+$' | sort -rn | tail -n +4 | xargs -r -I{} docker rmi "$APP:{}" 2>/dev/null || true
