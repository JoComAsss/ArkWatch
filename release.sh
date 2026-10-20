#!/bin/bash
# 打发布包：Universal .app + zip + SHA256
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-1.0.0}"

"$ROOT/build.sh"

OUT="$ROOT/dist/ArkWatch-$VERSION-macos-universal.zip"
rm -f "$OUT" "$OUT.sha256"
ditto -c -k --sequesterRsrc --keepParent "$ROOT/dist/ArkWatch.app" "$OUT"
shasum -a 256 "$OUT" | tee "$OUT.sha256"

echo
echo "== 产物 =="
ls -lh "$OUT"
echo "提示：未签名分发，用户首次打开需右键 →「打开」，或执行"
echo "  xattr -dr com.apple.quarantine /Applications/ArkWatch.app"
