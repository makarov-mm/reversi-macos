#!/bin/sh
# Builds "3D Reversi.app" with the Swift Package Manager.
#
#   ./build.sh          build the application into build/
#   ./build.sh run      build it and start it
#   ./build.sh clean    remove everything the builds made
set -eu

cd "$(dirname "$0")"

NAME="3D Reversi"
EXECUTABLE="Reversi3D"
IDENTIFIER="com.makarovmm.reversi3d"
VERSION="1.0.0"
APP="build/$NAME.app"
ICON="Sources/Reversi3D/Resources/reversi3d.png"

case "${1:-build}" in
    clean)
        rm -rf .build build
        exit 0
        ;;
    build | run) ;;
    *)
        echo "Usage: $0 [run | clean]" >&2
        exit 2
        ;;
esac

swift build -c release --product "$EXECUTABLE"
BIN="$(swift build -c release --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/$EXECUTABLE" "$APP/Contents/MacOS/$EXECUTABLE"
# The shaders and the icon, where the game looks for them.
cp -R "$BIN/${EXECUTABLE}_${EXECUTABLE}.bundle" "$APP/Contents/Resources/"

# The icon of the application, in the sizes macOS asks for.
ICONSET="build/$EXECUTABLE.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$ICON" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$EXECUTABLE.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key>
    <string>$EXECUTABLE</string>
    <key>CFBundleIdentifier</key>
    <string>$IDENTIFIER</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ru</string>
    </array>
    <key>CFBundleName</key>
    <string>$NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.board-games</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Mykhailo Makarov. MIT License.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

# An ad-hoc signature, which Apple silicon requires of every program it runs.
codesign --force --sign - "$APP"

echo "Built $APP"
if [ "${1:-build}" = run ]; then
    open "$APP"
fi
