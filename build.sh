#!/bin/bash
# 构建 ArkWatch.app（仅依赖 macOS 命令行工具，不需要 Xcode 工程）
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/ArkWatch.app"
BIN="$APP/Contents/MacOS/ArkWatch"

echo "==> 清理"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "==> 编译（Universal：arm64 + x86_64）"
TMPDIR_BUILD="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BUILD"' EXIT
ARCH_BINS=()
for ARCH in arm64 x86_64; do
  echo "    - $ARCH"
  swiftc -swift-version 5 -O -target "${ARCH}-apple-macos13.0" \
    -framework AppKit -framework SwiftUI -framework CryptoKit -framework Security \
    "$ROOT/Sources/"*.swift \
    -o "$TMPDIR_BUILD/ArkWatch-$ARCH" 2>&1 | grep -E "error:" && exit 1 || true
  ARCH_BINS+=("$TMPDIR_BUILD/ArkWatch-$ARCH")
done
lipo -create "${ARCH_BINS[@]}" -output "$BIN"
echo "    架构：$(lipo -archs "$BIN")"

echo "==> 生成图标"
if [ -f "$ROOT/tools/make-icon.swift" ]; then
  swiftc -O "$ROOT/tools/make-icon.swift" -o /tmp/arkwatch_makeicon >/dev/null 2>&1 || true
  if [ -x /tmp/arkwatch_makeicon ]; then
    /tmp/arkwatch_makeicon /tmp/arkwatch_icon.png >/dev/null
    rm -rf /tmp/arkwatch.iconset && mkdir -p /tmp/arkwatch.iconset
    for s in 16 32 64 128 256 512; do
      sips -z $s $s /tmp/arkwatch_icon.png --out /tmp/arkwatch.iconset/icon_${s}x${s}.png >/dev/null
      d=$((s*2))
      sips -z $d $d /tmp/arkwatch_icon.png --out /tmp/arkwatch.iconset/icon_${s}x${s}@2x.png >/dev/null
    done
    iconutil -c icns /tmp/arkwatch.iconset -o "$APP/Contents/Resources/AppIcon.icns" >/dev/null 2>&1 || true
  fi
fi

echo "==> 写入 Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>ArkWatch</string>
    <key>CFBundleDisplayName</key><string>ArkWatch</string>
    <key>CFBundleIdentifier</key><string>com.joco.arkwatch</string>
    <key>CFBundleExecutable</key><string>ArkWatch</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.1.0</string>
    <key>CFBundleVersion</key><string>3</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "==> 临时签名"
codesign --force --sign - --timestamp=none "$APP" 2>/dev/null || true

echo "==> 完成：$APP"
"$BIN" --selftest
