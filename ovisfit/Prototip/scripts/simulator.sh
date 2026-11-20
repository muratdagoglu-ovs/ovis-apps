#!/usr/bin/env bash
# Ovis Fit · simülatörde derle, kur, aç ve (isteğe bağlı) tasarım karşılaştırma görüntüleri al.
# Kullanım:
#   ./scripts/simulator.sh              # derle + kur + aç (gerçek, boş günlük)
#   ./scripts/simulator.sh screenshots  # ayrı geçici veriyle Bugün / Analiz / Su görüntüleri → screenshots/
#   UDID=<simülatör-udid> ./scripts/simulator.sh
set -euo pipefail
cd "$(dirname "$0")/.."

xcodebuild -version
xcodebuild -list -project OvisFit.xcodeproj

if [ -z "${UDID:-}" ]; then
  UDID=$(xcrun simctl list devices available -j | /usr/bin/python3 -c '
import json, sys, re
d = json.load(sys.stdin)["devices"]
best = None
for runtime, devs in d.items():
    m = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not m or int(m.group(1)) < 17: continue
    ver = (int(m.group(1)), int(m.group(2)))
    for dev in devs:
        if dev["name"].startswith("iPhone") and dev.get("isAvailable", True):
            key = (ver, dev["name"] in ("iPhone 16", "iPhone 15", "iPhone 16 Pro", "iPhone 15 Pro"))
            if best is None or key > best[0]: best = (key, dev["udid"], dev["name"], runtime)
if not best: sys.exit("iOS 17+ iPhone simülatörü bulunamadı")
print(best[1]); print(best[2], best[3], file=sys.stderr)
')
fi
echo "Simülatör: $UDID"
xcrun simctl boot "$UDID" 2>/dev/null || true
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
xcrun simctl bootstatus "$UDID" -b

xcodebuild -project OvisFit.xcodeproj -scheme OvisFit -configuration Debug \
  -destination "platform=iOS Simulator,id=$UDID" -derivedDataPath build build

APP="build/Build/Products/Debug-iphonesimulator/OvisFit.app"
BUNDLE=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Info.plist")
xcrun simctl install "$UDID" "$APP"
echo "Uygulama: $PWD/$APP ($BUNDLE)"

if [ "${1:-}" = "screenshots" ]; then
  mkdir -p screenshots
  xcrun simctl status_bar "$UDID" override --time 9:41 --batteryState charged --batteryLevel 100 \
    --cellularBars 4 --wifiBars 3 || true
  for screen in today analysis water; do
    xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
    xcrun simctl launch "$UDID" "$BUNDLE" -OvisScreenshotData -OvisScreen "$screen"
    sleep 4
    xcrun simctl io "$UDID" screenshot "screenshots/$screen.png"
    echo "screenshots/$screen.png"
  done
  xcrun simctl status_bar "$UDID" clear || true
  xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null || true
fi

xcrun simctl launch "$UDID" "$BUNDLE"
