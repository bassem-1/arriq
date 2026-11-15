#!/usr/bin/env bash
# builds arriq, assembles dist/arriq.app, ad-hoc signs it and zips it for a github release.
# usage: scripts/bundle.sh [--debug]
set -euo pipefail

usage() {
    echo "usage: scripts/bundle.sh [--debug]" >&2
    exit 2
}

config=release
for arg in "$@"; do
    case "$arg" in
        --debug) config=debug ;;
        *) usage ;;
    esac
done

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

app_name="arriq"
version="$(tr -d '[:space:]' < "$root/VERSION")"
if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
    echo "error: VERSION must be dotted numbers, got '$version'" >&2
    exit 1
fi

dist="$root/dist"
app="$dist/$app_name.app"
zip_path="$dist/$app_name-$version.zip"
# ARRIQ_BUILD_DIR moves build products elsewhere (useful when the repo lives in an iCloud-synced folder).
build_root="${ARRIQ_BUILD_DIR:-$root/.build}"
work="$build_root/bundle"
build_args=(-c "$config" --scratch-path "$build_root")

echo "building $app_name $version (${build_args[*]})"
swift build "${build_args[@]}"

bin_dir="$(swift build "${build_args[@]}" --show-bin-path)"
binary="$bin_dir/$app_name"
if [[ ! -x "$binary" ]]; then
    echo "error: built binary not found at $binary" >&2
    exit 1
fi

echo "rendering icon"
rm -rf "$work"
mkdir -p "$work/AppIcon.iconset"
master="$work/icon-1024.png"
swift "$root/scripts/make-icon.swift" "$master"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$master" --out "$work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
    sips -z "$((size * 2))" "$((size * 2))" "$master" --out "$work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$work/AppIcon.iconset" -o "$work/AppIcon.icns"

echo "assembling $app"
rm -rf "$dist"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$binary" "$app/Contents/MacOS/$app_name"
chmod 755 "$app/Contents/MacOS/$app_name"
sed -e "s/__VERSION__/$version/g" "$root/Resources/Info.plist" > "$app/Contents/Info.plist"
plutil -lint "$app/Contents/Info.plist" >/dev/null
cp "$work/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"

# the after-quit gadget: the same binary in a nested bundle with its own id, run by a LaunchAgent with --gadget.
# its own id keeps launch services from mistaking it for arriq (see Sources/ArriqKit/AfterQuit.swift).
helper="$app/Contents/Helpers/$app_name gadget.app"
echo "assembling $helper"
mkdir -p "$helper/Contents/MacOS" "$helper/Contents/Resources"
cp "$binary" "$helper/Contents/MacOS/$app_name"
chmod 755 "$helper/Contents/MacOS/$app_name"
cp "$app/Contents/Info.plist" "$helper/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "io.github.arriq.gadget" "$helper/Contents/Info.plist"
plutil -replace CFBundleName -string "$app_name gadget" "$helper/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "$app_name gadget" "$helper/Contents/Info.plist"
plutil -lint "$helper/Contents/Info.plist" >/dev/null
cp "$work/AppIcon.icns" "$helper/Contents/Resources/AppIcon.icns"

echo "signing (ad-hoc)"
# nested bundle first: signing the outer app seals the helper's signature into it
codesign --force --sign - --timestamp=none "$helper"
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app"

echo "zipping $zip_path"
ditto -c -k --keepParent "$app" "$zip_path"
shasum -a 256 "$zip_path"
