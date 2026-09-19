#!/usr/bin/env bash
# build_compose.sh — يولّد deploy/docker-compose.yml مع حقن محتوى site/index.html
# كسلسلة base64 بسطر واحد داخل متغير البيئة SITE_B64.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SITE_FILE="$ROOT_DIR/site/index.html"
OUT_FILE="$SCRIPT_DIR/docker-compose.yml"

if [[ ! -f "$SITE_FILE" ]]; then
  echo "ERROR: $SITE_FILE not found. Build the site first (site-builder part)." >&2
  exit 1
fi

# base64 بسطر واحد (macOS: base64 -i ثم إزالة أي أسطر جديدة)
SITE_B64="$(base64 -i "$SITE_FILE" | tr -d '\n')"

if [[ -z "$SITE_B64" ]]; then
  echo "ERROR: base64 encoding produced an empty string." >&2
  exit 1
fi

# الجزء الأول: ثوابت بعلامات مفردة حتى لا يفسد shell علامات $ (مثل $$SITE_B64)
cat > "$OUT_FILE" <<'EOF_PART1'
name: iphonesta

services:
  site:
    image: nginx:1.27-alpine
    container_name: iphonesta-site
    restart: unless-stopped
    environment:
EOF_PART1

# حقن الـ base64 بين علامتي اقتباس مزدوجة (لا يحتوي أحرفًا خطرة)
printf '      SITE_B64: "%s"\n' "$SITE_B64" >> "$OUT_FILE"

# الجزء الثاني: بقية الملف كما هو حرفيًا
cat >> "$OUT_FILE" <<'EOF_PART2'
    command: sh -c "echo $$SITE_B64 | base64 -d > /usr/share/nginx/html/index.html && exec nginx -g 'daemon off;'"
    expose:
      - "80"
    networks:
      public-proxy:
        aliases:
          - iphonesta-site

  route-sync:
    image: curlimages/curl:8.10.1
    container_name: iphonesta-route-sync
    restart: unless-stopped
    network_mode: container:reverse-proxy
    entrypoint: sh
    command:
      - -c
      - |
        echo "route-sync starting";
        curl -s http://localhost:2019/config/ | head -c 2000 || echo "ADMIN_API_UNREACHABLE";
        while true; do
          code=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:2019/config/apps/http/servers/iphonesta);
          if [ "$$code" != "200" ]; then
            echo "installing iphonesta route (status=$$code)";
            curl -s -X POST "http://localhost:2019/config/apps/http/servers/iphonesta" -H "Content-Type: application/json" -d "$$ROUTE_JSON" && echo "route installed";
          fi;
          sleep 20;
        done
    environment:
      ROUTE_JSON: '{"listen":[":443"],"routes":[{"match":[{"host":["iphonesta.com","www.iphonesta.com"]}],"handle":[{"handler":"reverse_proxy","upstreams":[{"dial":"iphonesta-site:80"}]}],"terminal":true}]}'

networks:
  public-proxy:
    external: true
    name: public-proxy
EOF_PART2

echo "Generated: $OUT_FILE"

# ─── التحقق من السلامة ───

# 1) SITE_B64 غير فارغ داخل الملف المولّد
if ! grep -qE 'SITE_B64: "[A-Za-z0-9+/=]+"' "$OUT_FILE"; then
  echo "ERROR: generated file has an empty or malformed SITE_B64." >&2
  exit 1
fi
echo "OK: SITE_B64 present and non-empty ($(printf '%s' "$SITE_B64" | wc -c | tr -d ' ') chars)."

# 2) ROUTE_JSON سليم: استخراج السلسلة بين علامتي الاقتباس المفردة وتحليلها
ROUTE_JSON_EXTRACTED="$(sed -n "s/^      ROUTE_JSON: '\\(.*\\)'\$/\\1/p" "$OUT_FILE")"
if [[ -z "$ROUTE_JSON_EXTRACTED" ]]; then
  echo "ERROR: could not extract ROUTE_JSON from generated file." >&2
  exit 1
fi

if command -v jq >/dev/null 2>&1; then
  if ! printf '%s' "$ROUTE_JSON_EXTRACTED" | jq -e . >/dev/null 2>&1; then
    echo "ERROR: ROUTE_JSON is not valid JSON (jq parse failed)." >&2
    exit 1
  fi
  echo "OK: ROUTE_JSON parses as valid JSON (jq)."
else
  # تحقق يدوي مبسّط عند غياب jq: توازن الأقواس الأساسية ووجود الحقول الجوهرية
  case "$ROUTE_JSON_EXTRACTED" in
    \{*\"listen\"*\"routes\"*\"reverse_proxy\"*\"iphonesta-site:80\"*\})
      echo "OK: ROUTE_JSON manual check passed (jq not available).";;
    *)
      echo "ERROR: ROUTE_JSON manual check failed (jq not available)." >&2
      exit 1;;
  esac
fi

echo "All checks passed."
