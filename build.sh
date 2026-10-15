#!/bin/zsh
# zap 빌드 → dist/zap.app, dist/zap.dmg
set -e
cd "$(dirname "$0")"
APP=dist/zap.app
VERSION=1.0
# CLT의 오래된 module.modulemap 중복 버그 우회 (있을 때만)
OVL=()
if [[ -f /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap && -f /Library/Developer/CommandLineTools/usr/include/swift/bridging.modulemap ]]; then
  mkdir -p tools && : > tools/empty.modulemap
  cat > tools/overlay.yaml <<YAML
{ "version": 0, "case-sensitive": "false", "roots": [ { "type": "file",
  "name": "/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap",
  "external-contents": "$PWD/tools/empty.modulemap" } ] }
YAML
  OVL=(-vfsoverlay tools/overlay.yaml)
fi
rm -rf build dist && mkdir -p build "$APP/Contents/MacOS" "$APP/Contents/Resources"

for arch in arm64 x86_64; do
  swiftc $OVL -O -swift-version 5 -target $arch-apple-macos12 -o build/zap-$arch Sources/main.swift
done
lipo -create build/zap-arm64 build/zap-x86_64 -output "$APP/Contents/MacOS/zap"

swiftc $OVL -o build/make_icon make_icon.swift && build/make_icon build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>zap</string>
  <key>CFBundleDisplayName</key><string>zap</string>
  <key>CFBundleIdentifier</key><string>studio.standing.zap</string>
  <key>CFBundleExecutable</key><string>zap</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST

xattr -cr "$APP"
codesign --force --deep --sign - "$APP"

mkdir -p build/dmg && cp -R "$APP" build/dmg/ && ln -s /Applications build/dmg/Applications
hdiutil create -volname zap -srcfolder build/dmg -ov -format UDZO dist/zap.dmg >/dev/null
echo "완료: dist/zap.app, dist/zap.dmg"
