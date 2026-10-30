#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export HAL_ROOT="$ROOT"
APP="$ROOT/Hal.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
MODULE_CACHE="$ROOT/.build/module-cache"

rm -rf "$APP"
rm -rf "$ROOT/AppIcon.iconset"
# Swift/Clang module caches embed absolute paths. On case-insensitive volumes the
# same checkout may be reached as Desktop/hal or desktop/hal; reusing the cache
# then makes the compiler see every SDK module twice and crash. It is cheap and
# deterministic to rebuild this small app's cache.
rm -rf "$MODULE_CACHE"
mkdir -p "$BIN" "$RES" "$MODULE_CACHE"

if python3 - <<'PY'
from PIL import Image, ImageDraw
import math, os

root = os.environ["HAL_ROOT"]
iconset = os.path.join(root, "AppIcon.iconset")
os.makedirs(iconset, exist_ok=True)

# Marka geometrisi Resources/Icons/hal.svg ile birebir ayni.
# SVG'yi qlmanage ile rasterlemek beyaz zemin bastigi icin dogrudan ciziyoruz.
CX = CY = 400.0
R, INNER = 310.0, 190.0
GAP_CENTER, GAP_HALF = 315.0, 40.0
DOT_R, DOT_DIST = 100.0, 250.0
INK = (247, 240, 214, 255)
BG = (14, 14, 16, 255)

def mark_layer(color):
    img = Image.new("RGBA", (800, 800), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.pieslice([CX-R, CY-R, CX+R, CY+R],
               GAP_CENTER + GAP_HALF, GAP_CENTER - GAP_HALF + 360, fill=color)
    d.ellipse([CX-INNER, CY-INNER, CX+INNER, CY+INNER], fill=(0, 0, 0, 0))
    a = math.radians(GAP_CENTER)
    dx, dy = CX + DOT_DIST*math.cos(a), CY + DOT_DIST*math.sin(a)
    d.ellipse([dx-DOT_R, dy-DOT_R, dx+DOT_R, dy+DOT_R], fill=color)
    return img

def app_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    pad = size * 0.08
    d.rounded_rectangle((pad, pad, size-pad, size-pad), radius=size*0.22, fill=BG)
    mark_size = max(int(size * 0.56), 1)
    mark = mark_layer(INK).resize((mark_size, mark_size), Image.Resampling.LANCZOS)
    offset = (size - mark_size) // 2
    img.alpha_composite(mark, (offset, offset))
    return img

for s in [16, 32, 128, 256, 512]:
    app_icon(s).save(os.path.join(iconset, "icon_%dx%d.png" % (s, s)))
    app_icon(s * 2).save(os.path.join(iconset, "icon_%dx%d@2x.png" % (s, s)))

# Yeni macOS sürümlerinde iconutil bazı geçerli RGBA iconset'lerini reddedebiliyor.
# Pillow aynı çok-çözünürlüklü ICNS kapsayıcısını doğrudan ve deterministik üretir.
app_icon(1024).save(os.path.join(root, "Hal.app", "Contents", "Resources", "AppIcon.icns"), format="ICNS")
PY
then
  rm -rf "$ROOT/AppIcon.iconset"
else
  echo "PIL yok, ikon atlandı"
fi

cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/turkey.json" "$RES/turkey.json"

ICON_DIR="$ROOT/Resources/Icons"
mkdir -p "$RES/Icons"
if [[ -d "$ICON_DIR" ]]; then
  cp "$ICON_DIR/"*.svg "$RES/Icons/" 2>/dev/null || true
fi

SPARKLE_VERSION="2.10.0"
SPARKLE_SHA="c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c"
SPARKLE_DIR="$ROOT/.build/sparkle"
SPARKLE_FRAMEWORK="$SPARKLE_DIR/Sparkle.framework"
if [[ ! -d "$SPARKLE_FRAMEWORK" ]]; then
  mkdir -p "$SPARKLE_DIR"
  ARCHIVE="$SPARKLE_DIR/Sparkle-${SPARKLE_VERSION}.tar.xz"
  if [[ ! -f "$ARCHIVE" ]]; then
    curl -fsSL -o "$ARCHIVE" -L \
      "https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
  fi
  GOT="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
  if [[ "$GOT" != "$SPARKLE_SHA" ]]; then
    echo "Sparkle arşivi doğrulanamadı: $GOT" >&2
    exit 1
  fi
  tar -xJf "$ARCHIVE" -C "$SPARKLE_DIR" \
    ./Sparkle.framework ./bin/sign_update ./bin/generate_appcast ./bin/generate_keys
fi

FILES=("${(@f)$(find "$ROOT/Sources" -name '*.swift' | sort)}")

compile_arch() {
  local arch="$1"
  local out="$2"
  local cache="$ROOT/.build/module-cache-$arch"
  rm -rf "$cache"
  mkdir -p "$(dirname "$out")" "$cache"
  swiftc -parse-as-library -O \
    -module-cache-path "$cache" \
    -target "${arch}-apple-macos14.0" \
    -sdk "$SDK" \
    -F "$SPARKLE_DIR" \
    -framework Sparkle \
    -framework SwiftUI \
    -framework AppKit \
    -framework Combine \
    -framework ServiceManagement \
    -framework QuartzCore \
    -framework CoreGraphics \
    -framework IOKit \
    -framework CoreAudio \
    -framework ApplicationServices \
    -framework Security \
    -framework UserNotifications \
    -framework EventKit \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$out" \
    "${FILES[@]}" || return 1
}

mkdir -p "$ROOT/.build/objs"
compile_arch "$ARCH" "$ROOT/.build/objs/Hal-$ARCH"
OTHER="x86_64"
if [[ "$ARCH" == "x86_64" ]]; then
  OTHER="arm64"
fi
if compile_arch "$OTHER" "$ROOT/.build/objs/Hal-$OTHER"; then
  lipo -create -output "$BIN/Hal" \
    "$ROOT/.build/objs/Hal-$ARCH" \
    "$ROOT/.build/objs/Hal-$OTHER"
  echo "İkili: $ARCH + $OTHER"
else
  cp "$ROOT/.build/objs/Hal-$ARCH" "$BIN/Hal"
  echo "İkili: yalnızca $ARCH"
fi
chmod +x "$BIN/Hal"

mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"

# Kalıcı imza: ad-hoc imzada her derleme yeni bir kod kimliği üretir; bu yüzden
# macOS anahtar zinciri ACL'i ve Erişilebilirlik izni her seferinde sıfırlanır.
# Sabit bir sertifikayla imzalayınca izinler bir kez verilip kalıcı olur.
SIGN_ID="${HAL_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application|Mac Developer/ {print $2; exit}')"
fi

# Sparkle kendi içinde imzalı yardımcılar taşır. Dışarı dağıtımda hepsi uygulamanın
# sertifikasıyla, içten dışa, yeniden imzalanır. Uygulama sandbox'lı olmadığı için
# XPC hizmetleri açılmaz; yine de paket imzasının bozulmaması için yerlerinde kalır.
# identity, bundle, hardened (1 ise runtime + timestamp)
sign_bundle() {
  local identity="$1"
  local bundle="$2"
  local hardened="${3:-0}"
  local fw="$bundle/Contents/Frameworks/Sparkle.framework/Versions/B"
  local runtime=()
  if [[ "$hardened" == "1" ]]; then
    runtime=(--options runtime --timestamp)
  fi
  codesign --force --sign "$identity" "${runtime[@]}" "$fw/XPCServices/Installer.xpc"
  codesign --force --sign "$identity" "${runtime[@]}" --preserve-metadata=entitlements \
    "$fw/XPCServices/Downloader.xpc"
  codesign --force --sign "$identity" "${runtime[@]}" "$fw/Autoupdate"
  codesign --force --sign "$identity" "${runtime[@]}" "$fw/Updater.app"
  codesign --force --sign "$identity" "${runtime[@]}" "$fw/../.."
  codesign --force --sign "$identity" "${runtime[@]}" --identifier dev.sungur.Hal "$bundle"
}

if [[ -n "$SIGN_ID" ]]; then
  sign_bundle "$SIGN_ID" "$APP" "${HAL_SIGN_RUNTIME:-0}"
  echo "İmza: $SIGN_ID"
else
  sign_bundle - "$APP" 0
  echo "UYARI: kalıcı imza kimliği yok, ad-hoc imzalandı."
  echo "       Her derlemede anahtar zinciri ve Erişilebilirlik izni tekrar sorulacak."
fi
echo "Built $APP"

# Yayın kopyası. Günlük Hal.app geliştirme sertifikasında kalır; disk imajındaki
# kopya ADBroom ile aynı biçimde ad-hoc imzalanır.
if [[ "${1:-}" == "--dmg" ]]; then
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist")"
  STAGE="$ROOT/dist/dmg"
  DMG="$ROOT/dist/Hal-${VERSION}.dmg"
  rm -rf "$STAGE" "$DMG" "$DMG.sha256"
  mkdir -p "$STAGE"
  ditto "$APP" "$STAGE/Hal.app"
  sign_bundle - "$STAGE/Hal.app" 0
  codesign --verify --strict --deep "$STAGE/Hal.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Hal $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
  rm -rf "$STAGE"
  (cd "$ROOT/dist" && shasum -a 256 "$(basename "$DMG")" | tee "$(basename "$DMG").sha256")
  echo "DMG: $DMG"
fi
