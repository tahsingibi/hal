#!/bin/zsh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
python3 scripts/localize.py --check
TEST_APP="$ROOT/.build/SettingsVerification.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources"
cp Info.plist "$TEST_APP/Contents/Info.plist"
for locale in Resources/*.lproj; do
  ditto "$locale" "$TEST_APP/Contents/Resources/$(basename "$locale")"
done
# Only the disposable test catalog gets this marker; real translations stay intact.
python3 - "$TEST_APP" <<'PY'
import pathlib, sys
p = pathlib.Path(sys.argv[1]) / 'Contents/Resources/tr.lproj/Localizable.strings'
s = p.read_text().replace('"Features" = "Özellikler";', '"Features" = "Katalog testi";')
p.write_text(s)
PY
FILES=("${(@f)$(find Sources -name '*.swift' ! -name 'HalApp.swift' | sort)}")
swiftc -parse-as-library -module-cache-path "$ROOT/.build/check-cache" \
  -target "$(uname -m)-apple-macos14.0" -F "$ROOT/.build/sparkle" \
  -framework Sparkle -framework SwiftUI -framework AppKit -framework Combine \
  -framework ServiceManagement -framework QuartzCore -framework CoreGraphics \
  -framework IOKit -framework CoreAudio -framework ApplicationServices \
  -framework Security -framework UserNotifications -framework Carbon -framework ScreenCaptureKit -framework EventKit \
  -Xlinker -rpath -Xlinker "$ROOT/.build/sparkle" \
  "${FILES[@]}" Tests/SettingsLocalizationTests.swift \
  -o "$TEST_APP/Contents/MacOS/Hal"
"$TEST_APP/Contents/MacOS/Hal"
