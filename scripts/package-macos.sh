#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Ad-hoc signing needs no paid Apple account. Sparkle signatures use the local Keychain.
version="${1:?Usage: scripts/package-macos.sh VERSION BUILD_NUMBER}"
build_number="${2:?Specify an increasing numeric build number}"
[[ "$version" =~ ^[0-9]+(\.[0-9]+)*$ && "$build_number" =~ ^[0-9]+$ ]] || {
    echo "Version and build number must be numeric." >&2; exit 1;
}
output="$PWD/build/releases/v$version"
[[ ! -e "$output" ]] || { echo "Output already exists: $output" >&2; exit 1; }

xcodebuild -project MiniBujo.xcodeproj -scheme MiniBujo -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/ReleaseDerivedData \
    -clonedSourcePackagesDirPath build/SourcePackages \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- \
    "MARKETING_VERSION=$version" "CURRENT_PROJECT_VERSION=$build_number" build

app="$PWD/build/ReleaseDerivedData/Build/Products/Release/MiniBujo.app"
codesign --verify --deep --strict "$app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist")" == "$build_number" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")" == "$version" ]]
tools="$PWD/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
public_key="$($tools/generate_keys --account com.xmshrine.minibujo -p)"
[[ "$public_key" == "$(/usr/libexec/PlistBuddy -c 'Print SUPublicEDKey' "$app/Contents/Info.plist")" ]] || {
    echo "Keychain signing key does not match the app's public key." >&2; exit 1;
}

mkdir -p "$output"
archive="MiniBujo-$version-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/$archive"
"$tools/generate_appcast" --account com.xmshrine.minibujo --maximum-deltas 0 \
    --download-url-prefix "https://github.com/XmShrine/MiniBujo/releases/download/v$version/" \
    "$output"
(cd "$output" && shasum -a 256 "$archive" > SHA256SUMS.txt)
echo "Ready: $output"
echo "Create a draft release with:"
echo "gh release create v$version '$output/$archive' '$output/appcast.xml' '$output/SHA256SUMS.txt' --draft --title 'Mini Bujo $version' --notes-file RELEASE_NOTES.md"
