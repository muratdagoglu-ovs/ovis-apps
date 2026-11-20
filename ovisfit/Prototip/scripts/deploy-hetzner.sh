#!/usr/bin/env bash
# Ovis Fit analiz sunucusunu, Ovis CRM'in çalıştığı Hetzner sunucusuna kurar / günceller. Mac'te çalıştırılır
# (CRM'deki script/deploy-canli.sh gibi SSH + rsync ile). CRM'e dokunmaz:
#   - ayrı klasör (/opt/ovisfit), ayrı kullanıcı (ovisfit), ayrı systemd servisi (ovisfit), port 127.0.0.1:8787
#   - Nginx'e AYRI bir site dosyası eklenir; `nginx -t` geçmezse dosya geri alınır, CRM ayarları değişmez
#   - Docker kurulmaz (güvenlik duvarı kurallarını değiştirmemek için)
#
#   ./scripts/deploy-hetzner.sh                         # varsayılan: root@178.105.131.113, fit.178.105.131.113.nip.io
#   ./scripts/deploy-hetzner.sh root@IP alan.adi         # başka sunucu / alan adı
#
# API anahtarı yalnızca ilk kurulumda sorulur, ekranda görünmez; sunucuda /opt/ovisfit/.env (600, sahibi ovisfit) içinde durur.
set -euo pipefail
cd "$(dirname "$0")/.."
SUNUCU="${1:-root@178.105.131.113}"
ALAN="${2:-fit.178.105.131.113.nip.io}"
UZAK=/opt/ovisfit
dur() { echo "✗ $*" >&2; exit 1; }

echo "▸ Sunucu: $SUNUCU · Adres: https://$ALAN"
ssh -o ConnectTimeout=10 "$SUNUCU" true || dur "SSH bağlantısı kurulamadı ($SUNUCU)"

echo "▸ Ön kontrol (node, nginx, certbot)"
ssh "$SUNUCU" 'set -e
  command -v node >/dev/null || { echo "node yok"; exit 3; }
  v=$(node -p "process.versions.node.split(\".\")[0]"); [ "$v" -ge 22 ] || { echo "node $v < 22"; exit 3; }
  command -v nginx >/dev/null || { echo "nginx yok"; exit 3; }
  command -v certbot >/dev/null || { echo "certbot yok"; exit 3; }
  echo "  node $(node -v), $(nginx -v 2>&1), $(certbot --version 2>&1)"' || dur "sunucuda gereksinimler eksik"

echo "▸ Kullanıcı ve klasör"
ssh "$SUNUCU" "set -e
  id ovisfit >/dev/null 2>&1 || useradd --system --home $UZAK --shell /usr/sbin/nologin ovisfit
  mkdir -p $UZAK/server $UZAK/backups"

echo "▸ Kod aktarımı"
TS=$(date +%Y%m%d-%H%M%S)
ssh "$SUNUCU" "cd $UZAK && [ -f server/server.mjs ] && tar czf backups/server-$TS.tgz server && ls -t backups/server-*.tgz | tail -n +6 | xargs -r rm -f || true"
rsync -az --delete --exclude node_modules --exclude '*.test.mjs' --exclude Dockerfile server/ "$SUNUCU:$UZAK/server/"
ssh "$SUNUCU" "set -e; cd $UZAK/server && npm ci --omit=dev --no-fund --no-audit --silent && chown -R ovisfit:ovisfit $UZAK"

if ! ssh "$SUNUCU" "test -s $UZAK/.env"; then
  read -rsp "ANTHROPIC_API_KEY (yazarken görünmez, Enter ile bitir): " KEY; echo
  [ -n "$KEY" ] || dur "anahtar boş"
  printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" | ssh "$SUNUCU" "umask 077; cat > $UZAK/.env && chown ovisfit:ovisfit $UZAK/.env"
  unset KEY
fi

echo "▸ systemd servisi (ovisfit)"
NODE=$(ssh "$SUNUCU" 'readlink -f "$(command -v node)"')
case "$NODE" in /root/*|/home/*) dur "node bir kullanıcı klasöründe ($NODE); ovisfit kullanıcısı erişemez. /usr/local/bin veya /usr/bin altına kurulu node gerekli";; esac
ssh "$SUNUCU" "cat > /etc/systemd/system/ovisfit.service" <<UNIT
[Unit]
Description=Ovis Fit analiz sunucusu (Claude Haiku)
After=network-online.target

[Service]
Type=simple
User=ovisfit
WorkingDirectory=$UZAK/server
EnvironmentFile=$UZAK/.env
Environment=HOST=127.0.0.1 PORT=8787 TRUST_PROXY=1 OVIS_RATE_PER_HOUR=30 NODE_ENV=production
ExecStart=$NODE server.mjs
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadOnlyPaths=$UZAK

[Install]
WantedBy=multi-user.target
UNIT
ssh "$SUNUCU" "set -e; systemctl daemon-reload; systemctl enable --quiet ovisfit; systemctl restart ovisfit
  for i in \$(seq 1 20); do curl -fsS http://127.0.0.1:8787/health && echo && exit 0; sleep 1; done
  journalctl -u ovisfit -n 30 --no-pager; exit 1" || dur "servis ayağa kalkmadı (yukarıdaki günlüğe bak)"

echo "▸ Nginx sitesi ($ALAN)"
ssh "$SUNUCU" "ALAN=$ALAN bash -s" <<'NGX'
set -e
SITE=/etc/nginx/sites-available/ovisfit
[ -d /etc/nginx/sites-available ] || SITE=/etc/nginx/conf.d/ovisfit.conf
YEDEK=$(mktemp); [ -f "$SITE" ] && cp "$SITE" "$YEDEK" || : > "$YEDEK"
if ! grep -q "server_name $ALAN" "$SITE" 2>/dev/null; then
cat > "$SITE" <<CONF
server {
    listen 80;
    server_name $ALAN;
    client_max_body_size 4m;
    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-For \$remote_addr;
        proxy_read_timeout 70s;
    }
}
CONF
fi
[ -d /etc/nginx/sites-enabled ] && ln -sf "$SITE" /etc/nginx/sites-enabled/ovisfit
if ! nginx -t 2>/dev/null; then
  echo "nginx -t başarısız; Ovis Fit site dosyası geri alınıyor (CRM etkilenmedi)"
  if [ -s "$YEDEK" ]; then cp "$YEDEK" "$SITE"; else rm -f "$SITE" /etc/nginx/sites-enabled/ovisfit; fi
  nginx -t; exit 1
fi
systemctl reload nginx
# HTTPS sertifikası (CRM'in kullandığı certbot hesabıyla); yalnızca bu alan adı için
if ! grep -q "listen 443" "$SITE"; then
  certbot --nginx -d "$ALAN" --non-interactive --agree-tos --redirect --register-unsafely-without-email --keep-until-expiring
fi
nginx -t && systemctl reload nginx
NGX

echo "▸ Dış kontrol"
for _ in $(seq 1 15); do curl -fsS "https://$ALAN/health" && echo && echo "✓ Hazır: https://$ALAN" && exit 0; sleep 2; done
dur "https://$ALAN/health yanıt vermedi (DNS/sertifika); 1 dk sonra tekrar dene: curl https://$ALAN/health"
