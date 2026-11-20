#!/usr/bin/env bash
# Ovis Fit analiz sunucusunu Hetzner sunucuna kurar / günceller. Mac'te çalıştırılır.
#
#   ./scripts/deploy-hetzner.sh root@SUNUCU_IP fit-api.alanadin.com
#
# Önce: alan adı sağlayıcında fit-api.alanadin.com için sunucu IP'sine A kaydı ekle,
# Hetzner Firewall'da 80 ve 443 portları açık olsun. SSH ile sunucuya girebiliyor olmalısın.
# API anahtarı yalnızca ilk kurulumda sorulur, ekranda görünmez ve sunucuda /opt/ovisfit/.env (600) içinde durur.
set -euo pipefail
cd "$(dirname "$0")/.."
TARGET="${1:?Kullanım: $0 root@SUNUCU_IP alan.adi}"
DOMAIN="${2:?Kullanım: $0 root@SUNUCU_IP alan.adi}"
REMOTE=/opt/ovisfit

echo "▶ DNS: $DOMAIN → $(dig +short "$DOMAIN" 2>/dev/null | tail -1)"
echo "▶ Dosyalar sunucuya kopyalanıyor ($TARGET:$REMOTE)"
ssh "$TARGET" "mkdir -p $REMOTE/server"
rsync -az --delete --exclude node_modules --exclude '*.test.mjs' server/ "$TARGET:$REMOTE/server/"
rsync -az deploy/hetzner/docker-compose.yml deploy/hetzner/Caddyfile "$TARGET:$REMOTE/"

if ! ssh "$TARGET" "test -f $REMOTE/.env"; then
  read -rsp "ANTHROPIC_API_KEY (yazarken görünmez, Enter ile bitir): " KEY; echo
  [ -n "$KEY" ] || { echo "Anahtar boş."; exit 1; }
  printf 'ANTHROPIC_API_KEY=%s\nOVIS_DOMAIN=%s\n' "$KEY" "$DOMAIN" | ssh "$TARGET" "umask 077; cat > $REMOTE/.env"
  unset KEY
else
  ssh "$TARGET" "grep -q '^OVIS_DOMAIN=' $REMOTE/.env && sed -i 's#^OVIS_DOMAIN=.*#OVIS_DOMAIN=$DOMAIN#' $REMOTE/.env || echo 'OVIS_DOMAIN=$DOMAIN' >> $REMOTE/.env"
fi

echo "▶ Sunucuda başlatılıyor"
ssh "$TARGET" "REMOTE=$REMOTE DOMAIN=$DOMAIN bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail
cd "$REMOTE"
if ! command -v docker >/dev/null; then
  echo "Docker kuruluyor…"; curl -fsSL https://get.docker.com | sh
fi
busy=$(ss -ltnp 2>/dev/null | grep -E ':(80|443) ' | grep -v caddy || true)
if [ -n "$busy" ] && ! docker compose ps --status running caddy 2>/dev/null | grep -q caddy; then
  echo "80/443 başka bir servis tarafından kullanılıyor; yalnızca uygulama 127.0.0.1:8787'de başlatılıyor."
  docker compose up -d --build ovisfit
  MODE=proxy
else
  docker compose --profile tls up -d --build
  MODE=tls
fi
for i in $(seq 1 20); do curl -fsS http://127.0.0.1:8787/health && echo && break; sleep 2; done
if [ "$MODE" = proxy ]; then
  cat <<NGINX

Mevcut nginx'ine şu sunucu bloğunu ekle (certbot ile HTTPS al), sonra: nginx -t && systemctl reload nginx
  server {
    server_name $DOMAIN;
    client_max_body_size 4m;
    location / { proxy_pass http://127.0.0.1:8787; proxy_set_header X-Forwarded-For \$remote_addr; proxy_read_timeout 70s; }
  }
NGINX
fi
REMOTE_SCRIPT

echo "▶ Dış kontrol (sertifika ilk seferde ~30 sn sürebilir):"
sleep 5
curl -fsS "https://$DOMAIN/health" && echo && echo "✓ Hazır: https://$DOMAIN" || echo "Henüz yanıt yok; DNS/firewall'ı kontrol edip 1 dk sonra: curl https://$DOMAIN/health"
