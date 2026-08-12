#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

"$ROOT/Scripts/build-core.sh"
command -v xcodegen >/dev/null 2>&1 || { echo "xcodegen is required: brew install xcodegen" >&2; exit 1; }
xcodegen generate

XCODEBUILD_SETTINGS=()
if [ -n "${RELEASE_MARKETING_VERSION:-}" ]; then
  XCODEBUILD_SETTINGS+=("MARKETING_VERSION=${RELEASE_MARKETING_VERSION}")
fi
if [ -n "${RELEASE_BUILD_NUMBER:-}" ]; then
  XCODEBUILD_SETTINGS+=("CURRENT_PROJECT_VERSION=${RELEASE_BUILD_NUMBER}")
fi
if [ -n "${RELEASE_FORK_VERSION:-}" ]; then
  XCODEBUILD_SETTINGS+=("FORK_RELEASE_VERSION=${RELEASE_FORK_VERSION}")
fi

if [ "${#XCODEBUILD_SETTINGS[@]}" -gt 0 ]; then
  echo "Applying release build settings:"
  printf '  %s\n' "${XCODEBUILD_SETTINGS[@]}"
fi

rm -rf build/UnsignedIPA build/DerivedData
xcodebuild \
  -project PaopaoLocationSpoofer.xcodeproj \
  -scheme PaopaoLocationSpoofer \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  "${XCODEBUILD_SETTINGS[@]}" \
  build

APP="build/DerivedData/Build/Products/Release-iphoneos/PaopaoLocationSpoofer.app"
if [ ! -d "$APP" ]; then
  echo "App bundle not found" >&2
  exit 1
fi

mkdir -p build/UnsignedIPA/Payload dist
ditto "$APP" "build/UnsignedIPA/Payload/PaopaoLocationSpoofer.app"
cd build/UnsignedIPA
zip -qry "$ROOT/dist/PaopaoLocationSpoofer-unsigned.ipa" Payload
echo "Output: dist/PaopaoLocationSpoofer-unsigned.ipa"
