#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
BUILD_SCRIPT="$ROOT_DIR/Scripts/build-unsigned-ipa.sh"
VALIDATOR="$ROOT_DIR/Scripts/validate-release-ipa.sh"

fail() {
  echo "release build metadata contract failed: $*" >&2
  exit 1
}

grep -Fq 'APP_VERSION="${VERSION#v}"' "$WORKFLOW" \
  || fail "release workflow must derive app version from release tag"
grep -Fq 'MARKETING_VERSION="${APP_VERSION%%-*}"' "$WORKFLOW" \
  || fail "release workflow must derive marketing version from release tag"
grep -Fq 'BUILD_NUMBER="$GITHUB_RUN_NUMBER"' "$WORKFLOW" \
  || fail "release workflow must use its monotonic run number as build number"
grep -Fq 'RELEASE_FORK_VERSION: "${{ steps.release.outputs.app_version }}"' "$WORKFLOW" \
  || fail "release build must receive tag-derived fork version"
grep -Fq 'RELEASE_MARKETING_VERSION: "${{ steps.release.outputs.marketing_version }}"' "$WORKFLOW" \
  || fail "release build must receive tag-derived marketing version"
grep -Fq 'RELEASE_BUILD_NUMBER: "${{ steps.release.outputs.build_number }}"' "$WORKFLOW" \
  || fail "release build must receive workflow-derived build number"
grep -Fq 'Validate IPA release metadata' "$WORKFLOW" \
  || fail "release workflow must validate packaged IPA metadata"
grep -Fq 'bash Scripts/validate-release-ipa.sh' "$WORKFLOW" \
  || fail "release workflow must run the IPA metadata validator"

grep -Fq 'MARKETING_VERSION=${RELEASE_MARKETING_VERSION}' "$BUILD_SCRIPT" \
  || fail "device build must forward release marketing version to xcodebuild"
grep -Fq 'CURRENT_PROJECT_VERSION=${RELEASE_BUILD_NUMBER}' "$BUILD_SCRIPT" \
  || fail "device build must forward release build number to xcodebuild"
grep -Fq 'FORK_RELEASE_VERSION=${RELEASE_FORK_VERSION}' "$BUILD_SCRIPT" \
  || fail "device build must forward release fork version to xcodebuild"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
APP_DIR="$TMP_DIR/package/Payload/Test.app"
mkdir -p "$APP_DIR"
cat > "$APP_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleShortVersionString</key>
  <string>1.2.3</string>
  <key>CFBundleVersion</key>
  <string>77</string>
  <key>ForkReleaseVersion</key>
  <string>1.2.3-0042</string>
</dict>
</plist>
PLIST

(
  cd "$TMP_DIR/package"
  zip -qry "$TMP_DIR/test.ipa" Payload
)

bash "$VALIDATOR" "$TMP_DIR/test.ipa" 1.2.3-0042 1.2.3 77 >/dev/null

if bash "$VALIDATOR" "$TMP_DIR/test.ipa" 1.2.3-0043 1.2.3 77 >/dev/null 2>&1; then
  fail "validator accepted a mismatched ForkReleaseVersion"
fi
if bash "$VALIDATOR" "$TMP_DIR/test.ipa" 1.2.3-0042 1.2.3 78 >/dev/null 2>&1; then
  fail "validator accepted a mismatched CFBundleVersion"
fi

echo "release build metadata contract passed"
