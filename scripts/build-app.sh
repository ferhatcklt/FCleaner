#!/usr/bin/env bash
# FCleaner.app paketini oluşturur: ./scripts/build-app.sh  →  build/FCleaner.app
set -euo pipefail

cd "$(dirname "$0")/.."
VERSION="${VERSION:-0.1.0}"
APP="build/FCleaner.app"

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/FCleaner"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/FCleaner"

# İkon yoksa üret (scripts/make-icon.swift).
[[ -f Resources/AppIcon.icns ]] || swift scripts/make-icon.swift .
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>FCleaner</string>
    <key>CFBundleDisplayName</key><string>FCleaner</string>
    <key>CFBundleIdentifier</key><string>tr.com.fcapps.fcleaner</string>
    <key>CFBundleExecutable</key><string>FCleaner</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundleVersion</key><string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 FCApps · MIT License</string>
</dict>
</plist>
PLIST

# İmza: SIGN_IDENTITY verilmişse onu, yoksa anahtar zincirindeki ilk "Apple Development" sertifikasını kullanır.
# Sabit bir imza, Tam Disk Erişimi izninin her yeniden derlemede kaybolmasını önler.
# Sertifika yoksa ad-hoc imzaya düşer (izni her derlemeden sonra yeniden vermek gerekebilir).
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')}"
if [[ -n "$IDENTITY" ]]; then
    codesign --force --deep --sign "$IDENTITY" "$APP"
    echo "🔏 İmzalandı: $(security find-identity -v -p codesigning | grep "$IDENTITY" | head -1 | cut -d'"' -f2)"
else
    codesign --force --deep --sign - "$APP"
    echo "⚠️  Ad-hoc imza kullanıldı"
fi

echo "✅ $APP hazır"
