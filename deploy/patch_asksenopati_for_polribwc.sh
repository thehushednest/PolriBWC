#!/usr/bin/env bash

set -euo pipefail

NGINX_SITE="${1:-/etc/nginx/sites-available/asksenopati.com}"
TMP_FILE="$(mktemp)"

cleanup() {
  rm -f "${TMP_FILE}"
}
trap cleanup EXIT

if [[ ! -f "${NGINX_SITE}" ]]; then
  echo "File nginx tidak ditemukan: ${NGINX_SITE}" >&2
  exit 1
fi

awk '
  function print_block() {
    print "    location ^~ /polribwc/api/v1/ptt/ws {"
    print "        proxy_pass http://127.0.0.1:8787/api/v1/ptt/ws;"
    print "        proxy_http_version 1.1;"
    print "        proxy_set_header Host $host;"
    print "        proxy_set_header X-Real-IP $remote_addr;"
    print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
    print "        proxy_set_header X-Forwarded-Proto $scheme;"
    print "        proxy_set_header Upgrade $http_upgrade;"
    print "        proxy_set_header Connection \"upgrade\";"
    print "        proxy_read_timeout 600s;"
    print "        proxy_send_timeout 600s;"
    print "        proxy_buffering off;"
    print "        proxy_cache off;"
    print "    }"
    print ""
    print "    location ^~ /polribwc/api/v1/live/ws {"
    print "        proxy_pass http://127.0.0.1:8787/api/v1/live/ws;"
    print "        proxy_http_version 1.1;"
    print "        proxy_set_header Host $host;"
    print "        proxy_set_header X-Real-IP $remote_addr;"
    print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
    print "        proxy_set_header X-Forwarded-Proto $scheme;"
    print "        proxy_set_header Upgrade $http_upgrade;"
    print "        proxy_set_header Connection \"upgrade\";"
    print "        proxy_read_timeout 600s;"
    print "        proxy_send_timeout 600s;"
    print "        proxy_buffering off;"
    print "        proxy_cache off;"
    print "    }"
    print ""
    print "    location ^~ /polribwc/api/v1/live/signal/ws {"
    print "        proxy_pass http://127.0.0.1:8787/api/v1/live/signal/ws;"
    print "        proxy_http_version 1.1;"
    print "        proxy_set_header Host $host;"
    print "        proxy_set_header X-Real-IP $remote_addr;"
    print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
    print "        proxy_set_header X-Forwarded-Proto $scheme;"
    print "        proxy_set_header Upgrade $http_upgrade;"
    print "        proxy_set_header Connection \"upgrade\";"
    print "        proxy_read_timeout 600s;"
    print "        proxy_send_timeout 600s;"
    print "        proxy_buffering off;"
    print "        proxy_cache off;"
    print "    }"
    print ""
    print "    location ^~ /polribwc/ {"
    print "        proxy_pass http://127.0.0.1:8787/;"
    print "        proxy_http_version 1.1;"
    print "        proxy_set_header Host $host;"
    print "        proxy_set_header X-Real-IP $remote_addr;"
    print "        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;"
    print "        proxy_set_header X-Forwarded-Proto $scheme;"
    print "        proxy_set_header X-Forwarded-Prefix /polribwc;"
    print "        proxy_read_timeout 600s;"
    print "        proxy_send_timeout 600s;"
    print "        proxy_buffering off;"
    print "        proxy_cache off;"
    print "    }"
    print ""
  }
  function is_polribwc_location(line) {
    return line ~ /^    location \^~ \/polribwc\/api\/v1\/ptt\/ws \{/ || \
           line ~ /^    location \^~ \/polribwc\/api\/v1\/live\/ws \{/ || \
           line ~ /^    location \^~ \/polribwc\/ \{/
  }
  function is_any_location(line) {
    return line ~ /^    location /
  }
  {
    if (skip_block) {
      if (is_any_location($0)) {
        skip_block = 0
      } else {
        next
      }
    }
    if (is_polribwc_location($0)) {
      if (!replaced) {
        print_block()
        replaced = 1
      }
      skip_block = 1
      next
    }
    if ($0 ~ /location \/ \{/ && !replaced) {
      print_block()
      replaced = 1
    }
    print
  }
  END {
    if (!replaced) {
      exit 2
    }
  }
' "${NGINX_SITE}" > "${TMP_FILE}" || {
  echo "Gagal menyisipkan blok /polribwc ke ${NGINX_SITE}" >&2
  exit 1
}

cp "${TMP_FILE}" "${NGINX_SITE}"

echo "Berhasil menambah atau memperbarui location /polribwc di ${NGINX_SITE}"
echo "Lanjutkan dengan:"
echo "  sudo nginx -t"
echo "  sudo systemctl reload nginx"
