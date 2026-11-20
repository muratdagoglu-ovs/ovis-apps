#!/usr/bin/env bash
# Ovis Fit analiz sunucusu (Claude Haiku 5.5). Aynı Wi‑Fi'deki iPhone'a açılır.
# Kullanım:  ANTHROPIC_API_KEY=... ./scripts/dev-server.sh
#   veya anahtarı bir kez ~/.ovisfit-key dosyasına kaydet (yalnızca sen okuyabilirsin):
#   printf '%s' 'ANAHTAR' > ~/.ovisfit-key && chmod 600 ~/.ovisfit-key
set -euo pipefail
cd "$(dirname "$0")/../server"
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -f "$HOME/.ovisfit-key" ]; then
  ANTHROPIC_API_KEY="$(cat "$HOME/.ovisfit-key")"; export ANTHROPIC_API_KEY
fi
if [ -z "${ANTHROPIC_API_KEY:-}" ]; then
  echo "HATA: ANTHROPIC_API_KEY yok. Anahtar al: https://console.anthropic.com/settings/keys"
  echo "Sonra: ANTHROPIC_API_KEY=... ./scripts/dev-server.sh"
  exit 1
fi
command -v node >/dev/null || { echo "HATA: Node.js 22+ gerekli: https://nodejs.org"; exit 1; }
[ -d node_modules ] || npm install --no-fund --no-audit
NAME=$(scutil --get LocalHostName 2>/dev/null || hostname)
echo "iPhone bu adrese bağlanır: http://$NAME.local:8787"
HOST=0.0.0.0 PORT=8787 exec node server.mjs
