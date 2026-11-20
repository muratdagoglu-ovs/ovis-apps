#!/usr/bin/env bash
# Ovis Fit · tek komutla Xcode derlemesi ve dosya teslimi.
#
#   TEAM=ABCDE12345 ./scripts/xcode-build.sh            # test + simülatör derlemesi + imzalı .ipa
#   TEAM=ABCDE12345 ./scripts/xcode-build.sh --upload   # ek olarak TestFlight'a (App Store Connect) yükler
#
# TEAM: developer.apple.com/account › Membership › Team ID. Xcode › Settings › Accounts'ta Apple ID açık olmalı.
# Çıktılar: build/OvisFit.xcarchive, build/ipa/OvisFit.ipa, build/logs/*.log
set -euo pipefail
cd "$(dirname "$0")/.."
UPLOAD=0; [ "${1:-}" = "--upload" ] && UPLOAD=1
TEAM="${TEAM:-$(grep -E '^DEVELOPMENT_TEAM *=' Config/Local.xcconfig 2>/dev/null | sed 's/.*= *//' | tr -d ' ' || true)}"
[ -n "$TEAM" ] && [ "$TEAM" != "ABCDE12345" ] || { echo "HATA: TEAM=<Team ID> ver (developer.apple.com/account › Membership)."; exit 1; }
BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
mkdir -p build/logs

step() { printf '\n▶ %s\n' "$1"; }
run() { local log="build/logs/$1.log"; shift; if ! "$@" >"$log" 2>&1; then
  echo "✗ Başarısız. Son satırlar ($log):"; grep -E "error:|warning: .*error|BUILD FAILED|\*\* .* FAILED" "$log" | head -40 || tail -40 "$log"; exit 1; fi; echo "✓ Tamam ($log)"; }

step "Araçlar"
xcodebuild -version
xcodebuild -list -project OvisFit.xcodeproj | sed -n '1,20p'

step "Mantık testleri (swift test)"
run swift-test swift test

step "Sunucu testleri"
if command -v node >/dev/null; then
  (cd server && [ -d node_modules ] || npm install --no-fund --no-audit >/dev/null)
  run node-test node --test server/server.test.mjs
else echo "Node.js yok, atlandı."; fi

step "Simülatör derlemesi (Debug)"
run sim-build xcodebuild -project OvisFit.xcodeproj -scheme OvisFit -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd build
echo "Uygulama: $PWD/build/dd/Build/Products/Debug-iphonesimulator/OvisFit.app"

step "Cihaz arşivi (Release, imzalı) · yapı $BUILD_NUMBER"
rm -rf build/OvisFit.xcarchive build/ipa
run archive xcodebuild -project OvisFit.xcodeproj -scheme OvisFit -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/OvisFit.xcarchive -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

DEST=export; [ "$UPLOAD" = 1 ] && DEST=upload
cat > build/ExportOptions.plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>method</key><string>app-store-connect</string>
<key>destination</key><string>$DEST</string>
<key>signingStyle</key><string>automatic</string>
<key>teamID</key><string>$TEAM</string>
<key>uploadSymbols</key><true/>
</dict></plist>
PLIST

step "Dışa aktarma ($DEST)"
run export xcodebuild -exportArchive -archivePath build/OvisFit.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/ipa -allowProvisioningUpdates
if [ "$UPLOAD" = 1 ]; then
  echo "✓ App Store Connect'e yüklendi (yapı $BUILD_NUMBER). TestFlight sekmesinde 5–30 dk içinde görünür."
else
  ls -la build/ipa/*.ipa && echo "✓ .ipa hazır: $PWD/build/ipa/ — Transporter uygulamasıyla da yüklenebilir."
fi
open build 2>/dev/null || true
