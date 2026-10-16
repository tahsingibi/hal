#!/bin/zsh
# Yeni bir Hâl sürümünü güncelleme paketine hazırlar.
# Developer ID Application sertifikası yoksa durur. Noter ve yükleme elle biter.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IDENTITY="${HAL_SIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Developer ID Application/ {print $2; exit}')"
fi
if [[ "$IDENTITY" != *"Developer ID Application"* ]]; then
  echo "Developer ID Application sertifikası yok. Güncelleme paketi üretilmedi." >&2
  echo "Apple Development imzası yalnızca bu Mac'te çalışır; indiren kişide Gatekeeper açmaz." >&2
  exit 1
fi

HAL_SIGN_IDENTITY="$IDENTITY" HAL_SIGN_RUNTIME=1 "$ROOT/build.sh"

VERSION="$(plutil -extract CFBundleShortVersionString raw Info.plist)"
BUILD="$(plutil -extract CFBundleVersion raw Info.plist)"
mkdir -p "$ROOT/dist"
ZIP="$ROOT/dist/Hal-${VERSION}.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$ROOT/Hal.app" "$ZIP"

SIGN_UPDATE="$ROOT/.build/sparkle/bin/sign_update"
if [[ ! -x "$SIGN_UPDATE" ]]; then
  echo "sign_update yok. Önce ./build.sh Sparkle'ı indirmiş olmalı." >&2
  exit 1
fi
echo "Sürüm ${VERSION} (${BUILD})"
"$SIGN_UPDATE" --account Hal "$ZIP"

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$ZIP"
  echo "Noter tamam."
else
  echo "Noter atlandı. NOTARY_KEYCHAIN_PROFILE verildiğinde notarytool çalışır."
fi

echo "Zip: $ZIP"
echo "İmzayı appcast.xml içindeki enclosure'a yaz. Zip adresini GitHub Release'e bağla:"
echo "  https://github.com/tahsingibi/hal/releases/download/v${VERSION}/Hal-${VERSION}.zip"
echo "appcast.xml dosyasını main'e commit edip gönder. Uygulama şu adresten okur:"
echo "  https://raw.githubusercontent.com/tahsingibi/hal/main/appcast.xml"
echo "CFBundleVersion her yayında artar. Gizli imza anahtarı login anahtarlığında, hesap adı Hal."
