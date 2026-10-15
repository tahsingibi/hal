#!/bin/zsh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
export HILAL_ROOT="$ROOT"
APP="$ROOT/Hal.app"
BIN="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
SDK="$(xcrun --show-sdk-path)"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macos14.0"
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

root = os.environ["HILAL_ROOT"]
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

FILES=("${(@f)$(find "$ROOT/Sources" -name '*.swift' | sort)}")

swiftc -parse-as-library -O \
  -module-cache-path "$MODULE_CACHE" \
  -target "$TARGET" \
  -sdk "$SDK" \
  -framework SwiftUI \
  -framework AppKit \
  -framework Combine \
  -framework ServiceManagement \
  -framework QuartzCore \
  -framework CoreGraphics \
  -framework IOKit \
  -framework ApplicationServices \
  -framework Security \
  -framework UserNotifications \
  -framework EventKit \
  -o "$BIN/Hal" \
  "${FILES[@]}"

chmod +x "$BIN/Hal"

# Kalıcı imza: ad-hoc imzada her derleme yeni bir kod kimliği üretir; bu yüzden
# macOS anahtar zinciri ACL'i ve Erişilebilirlik izni her seferinde sıfırlanır.
# Sabit bir sertifikayla imzalayınca izinler bir kez verilip kalıcı olur.
SIGN_ID="${HILAL_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_ID" ]]; then
  SIGN_ID="$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development|Developer ID Application|Mac Developer/ {print $2; exit}')"
fi

if [[ -n "$SIGN_ID" ]]; then
  codesign --force --sign "$SIGN_ID" --identifier dev.sungur.Hilal "$APP" >/dev/null
  echo "İmza: $SIGN_ID"
else
  codesign --force --sign - --identifier dev.sungur.Hilal "$APP" >/dev/null
  echo "UYARI: kalıcı imza kimliği yok, ad-hoc imzalandı."
  echo "       Her derlemede anahtar zinciri ve Erişilebilirlik izni tekrar sorulacak."
fi
echo "Built $APP"
