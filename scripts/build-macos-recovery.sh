#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
output_dir="${1:-$repo_dir/../OpenKey-build/recovery}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
app="$output_dir/OpenKey.app"
if [[ -e "$app" ]]; then
    echo "Output already contains OpenKey.app; choose a new output directory." >&2
    exit 1
fi

# Modern Xcode no longer supports the project's original macOS 10.x target.
xcodebuild -quiet -project "$repo_dir/Sources/OpenKey/macOS/OpenKey.xcodeproj" \
    -scheme OpenKey -configuration Release -derivedDataPath "$output_dir/DerivedData" \
    CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
    ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION=2.0.6 CURRENT_PROJECT_VERSION=51 build \
    > "$output_dir/build.log" 2>&1 || {
    cat "$output_dir/build.log"
    exit 1
}
ditto "$output_dir/DerivedData/Build/Products/Release/OpenKey.app" "$app"

# Upstream retains the login helper's sources, but its Xcode target was removed.
# Build that helper from source so Run on startup continues to work.
helper="$app/Contents/Library/LoginItems/OpenKeyHelper.app"
mkdir -p "$helper/Contents/MacOS" "$helper/Contents/Resources/Base.lproj"
xcrun clang -fobjc-arc -Os -mmacosx-version-min=12.0 -arch arm64 -arch x86_64 \
    "$repo_dir/Sources/OpenKey/macOS/OpenKeyHelper/main.m" \
    "$repo_dir/Sources/OpenKey/macOS/OpenKeyHelper/AppDelegate.m" \
    -framework Cocoa -o "$helper/Contents/MacOS/OpenKeyHelper"
xcrun ibtool --compile "$helper/Contents/Resources/Base.lproj/MainMenu.nib" \
    "$repo_dir/Sources/OpenKey/macOS/OpenKeyHelper/Base.lproj/MainMenu.xib"

python3 - "$repo_dir" "$app" "$helper" <<'PY'
import pathlib, plistlib, subprocess, sys
repo, app, helper = map(pathlib.Path, sys.argv[1:])
with (repo / 'Sources/OpenKey/macOS/OpenKeyHelper/Info.plist').open('rb') as f:
    info = plistlib.load(f)
info.update(CFBundleDevelopmentRegion='en', CFBundleExecutable='OpenKeyHelper',
            CFBundleIdentifier='com.tuyenmai.OpenKeyHelper', CFBundleName='OpenKeyHelper',
            LSMinimumSystemVersion='12.0')
with (helper / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
with (app / 'Contents/Info.plist').open('rb') as f:
    info = plistlib.load(f)
info['OpenKeySourceRevision'] = subprocess.check_output(
    ['git', '-C', str(repo), 'rev-parse', 'HEAD'], text=True).strip()
info['OpenKeySourceRepository'] = 'https://github.com/nxnguyen/OpenKey'
with (app / 'Contents/Info.plist').open('wb') as f:
    plistlib.dump(info, f)
PY

codesign --force --sign - "$helper"
codesign --force --sign - "$app"
codesign --verify --deep --strict --verbose=2 "$app"
for architecture in arm64 x86_64; do
    lipo "$app/Contents/MacOS/OpenKey" -verify_arch "$architecture"
    lipo "$helper/Contents/MacOS/OpenKeyHelper" -verify_arch "$architecture"
done
ditto -c -k --sequesterRsrc --keepParent "$app" "$output_dir/OpenKey-2.0.6-build51-macos-universal.zip"
shasum -a 256 "$output_dir/OpenKey-2.0.6-build51-macos-universal.zip" > "$output_dir/SHA256SUMS.txt"
echo "Built: $app"
