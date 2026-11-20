#!/usr/bin/env bash
# Ovis Fit · Release arşivi oluştur ve TestFlight'a (App Store Connect) yükle.
#
# Önce:
#   1. App Store Connect'te uygulamayı oluştur (Bundle ID ile).
#   2. cp Config/Local.xcconfig.example Config/Local.xcconfig ve DEVELOPMENT_TEAM,
#      PRODUCT_BUNDLE_IDENTIFIER, OVIS_API_BASE_URL (https) değerlerini doldur.
#   3. Kimlik: Xcode › Settings › Accounts'ta Apple ID oturumu açık olsun
#      VEYA App Store Connect API anahtarı ver:
#        export ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-... ASC_KEY_PATH=$PWD/scripts/AuthKey_XXXXXXXXXX.p8
#
# Kullanım:  BUILD_NUMBER=2 ./scripts/testflight.sh      (her yüklemede artan sayı)
set -euo pipefail
cd "$(dirname "$0")/.."

LOCAL=Config/Local.xcconfig
[ -f "$LOCAL" ] || { echo "HATA: $LOCAL yok. Config/Local.xcconfig.example'dan oluştur."; exit 1; }
grep -Eq '^DEVELOPMENT_TEAM *= *[A-Z0-9]{10} *$' "$LOCAL" && ! grep -q 'ABCDE12345' "$LOCAL" \
  || { echo "HATA: $LOCAL içinde gerçek DEVELOPMENT_TEAM gerekli."; exit 1; }
grep -Eq '^OVIS_API_BASE_URL\[config=Release\] *= *https:' "$LOCAL" && ! grep -q 'sirketin.com' "$LOCAL" \
  || echo "UYARI: HTTPS analiz sunucusu tanımlı değil. Testçiler adresi Profil › Analiz sunucusu bölümünden girmeli."

BUILD_NUMBER="${BUILD_NUMBER:-$(date +%Y%m%d%H%M)}"
AUTH=()
if [ -n "${ASC_KEY_ID:-}" ]; then
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

rm -rf build/OvisFit.xcarchive build/export
xcodebuild -project OvisFit.xcodeproj -scheme OvisFit -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/OvisFit.xcarchive \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" archive

# ExportOptions'taki destination=upload, dışa aktarırken doğrudan App Store Connect'e yükler.
xcodebuild -exportArchive -archivePath build/OvisFit.xcarchive \
  -exportOptionsPlist scripts/ExportOptions-TestFlight.plist -exportPath build/export \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

echo "Yüklendi: yapı $BUILD_NUMBER. App Store Connect › TestFlight'ta işlenmesini bekle (genelde 5–30 dk)."
