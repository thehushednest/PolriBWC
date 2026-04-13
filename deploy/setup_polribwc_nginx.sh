#!/usr/bin/env bash

set -euo pipefail

DOMAIN="polribwc.cakrawalasasmita.com"
NGINX_CONF_SOURCE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/nginx-polribwc.conf"
NGINX_CONF_TARGET="/etc/nginx/sites-available/${DOMAIN}"
NGINX_ENABLED_TARGET="/etc/nginx/sites-enabled/${DOMAIN}"

echo "Menyalin config nginx untuk ${DOMAIN}"
sudo cp "${NGINX_CONF_SOURCE}" "${NGINX_CONF_TARGET}"
sudo ln -sfn "${NGINX_CONF_TARGET}" "${NGINX_ENABLED_TARGET}"

echo "Menguji konfigurasi nginx"
sudo nginx -t

echo "Reload nginx"
sudo systemctl reload nginx

cat <<EOF
Selesai.

Langkah berikutnya:
1. Pastikan DNS A record ${DOMAIN} mengarah ke IP publik mesin ini.
2. Pastikan port 80/443 terbuka ke mesin ini.
3. Jika ingin HTTPS, jalankan certbot, misalnya:
   sudo certbot --nginx -d ${DOMAIN}
EOF
