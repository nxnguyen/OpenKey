#!/bin/bash
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/../.." && pwd)"
derived_dir="${OPENKEY_TEST_BUILD_DIR:-$(mktemp -d -t openkey-tests)}"
architecture="$(uname -m)"
mkdir -p "$derived_dir"

xcodebuild -quiet -project "$repo_dir/Sources/OpenKey/macOS/OpenKey.xcodeproj" \
    -scheme OpenKey -configuration Release -derivedDataPath "$derived_dir" \
    CODE_SIGNING_ALLOWED=NO MACOSX_DEPLOYMENT_TARGET=12.0 \
    ARCHS="$architecture" ONLY_ACTIVE_ARCH=YES build > "$derived_dir/build.log" 2>&1 || {
    cat "$derived_dir/build.log"
    exit 1
}

object_dir="$derived_dir/Build/Intermediates.noindex/OpenKey.build/Release/OpenKey.build/Objects-normal/$architecture"
objects=()
for object in "$object_dir"/*.o; do
    case "$(basename "$object")" in main.o|OpenKey_lto.o) continue ;; esac
    objects+=("$object")
done

xcrun clang++ -std=c++14 -fobjc-arc -mmacosx-version-min=12.0 \
    -I "$repo_dir/Sources/OpenKey/macOS/ModernKey" \
    -I "$repo_dir/Sources/OpenKey/engine" \
    "$repo_dir/tests/macOS/EventTapRecoveryTests.mm" "${objects[@]}" \
    -framework Cocoa -framework Carbon -framework CoreGraphics -framework EventKit \
    -framework ServiceManagement -o "$derived_dir/event-tap-tests"
"$derived_dir/event-tap-tests"
