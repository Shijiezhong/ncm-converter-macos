#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
bash ./build-java.sh
app="dist/NCM转换器.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" build/swift-cache
cp Info.plist "$app/Contents/Info.plist"
cp dist/ncm-converter.jar "$app/Contents/Resources/NCM转换工具.jar"
xcrun swift -module-cache-path build/swift-cache Icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
arch="${ARCH:-$(uname -m)}"
compile() {
  xcrun swiftc -swift-version 5 -O -target "$1-apple-macosx14.0" \
    -module-cache-path build/swift-cache NcmApp.swift \
    -o "build/ncm-converter-$1" -framework AppKit
}
case "$arch" in
  universal)
    compile arm64
    compile x86_64
    lipo -create build/ncm-converter-arm64 build/ncm-converter-x86_64 -output "$app/Contents/MacOS/ncm-converter"
    ;;
  arm64|x86_64)
    compile "$arch"
    cp "build/ncm-converter-$arch" "$app/Contents/MacOS/ncm-converter"
    ;;
  *) echo "Unsupported architecture: $arch" >&2; exit 1 ;;
esac
chmod +x "$app/Contents/MacOS/ncm-converter"
xattr -cr "$app"
codesign --force --sign - "$app"
codesign --verify --strict "$app"
archive="dist/NCM-Converter-macOS-${arch}-v2.1.0.zip"
ditto -c -k --norsrc --noextattr --keepParent "$app" "$archive"
shasum -a 256 "$archive" dist/ncm-converter.jar > dist/SHA256SUMS.txt
echo "Built: $archive"
