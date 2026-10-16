#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swift-module-cache"
build=(swift build --disable-sandbox --cache-path "$PWD/.build/cache" -c release --arch arm64 --arch x86_64)
"${build[@]}"
binary_dir="$("${build[@]}" --show-bin-path)"
app_path="$PWD/dist/Stowia.app"
rm -rf "$app_path"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/Stowia" "$app_path/Contents/MacOS/Stowia"
cp Resources/Info.plist "$app_path/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/Assets.car Resources/MenuBarIconTemplate.png Resources/MenuBarIconTemplate@2x.png "$app_path/Contents/Resources/"
cp -R Resources/en.lproj Resources/tr.lproj "$app_path/Contents/Resources/"
# An ad hoc signature changes with every build, and macOS then asks for Accessibility access again.
# The self-signed certificate from scripts/make-certificate.sh keeps the identity stable;
# STOWIA_SIGN_IDENTITY picks another one, - forces ad hoc signing.
identity="${STOWIA_SIGN_IDENTITY:-$(security find-identity -p codesigning | awk -F'"' '$2 == "Stowia Self-Signed" { print $2; exit }')}"
codesign --force --sign "${identity:--}" --identifier com.hamzabasaran.stowia --timestamp=none "$app_path"
codesign --verify --strict "$app_path"
printf 'Built: %s (%s, signed: %s)\n' "$app_path" "$(lipo -archs "$app_path/Contents/MacOS/Stowia")" "${identity:-ad hoc}"
