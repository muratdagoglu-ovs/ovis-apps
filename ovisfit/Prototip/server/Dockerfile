# Ovis Fit analiz sunucusu (Claude Haiku 5.5). TestFlight/fiziksel iPhone için bir HTTPS ters vekilin
# (ör. barındırma platformunun TLS'i) arkasında çalıştır. ANTHROPIC_API_KEY yalnızca ortam değişkeniyle verilir.
FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-fund --no-audit
COPY server.mjs ./
ENV HOST=0.0.0.0 PORT=8787 TRUST_PROXY=1 OVIS_RATE_PER_HOUR=30
EXPOSE 8787
USER node
CMD ["node", "server.mjs"]
