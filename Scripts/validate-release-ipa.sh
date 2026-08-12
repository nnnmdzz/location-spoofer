#!/usr/bin/env bash
set -euo pipefail

IPA="${1:-}"
EXPECTED_FORK_VERSION="${2:-}"
EXPECTED_MARKETING_VERSION="${3:-}"
EXPECTED_BUILD_NUMBER="${4:-}"

fail() {
  echo "release IPA validation failed: $*" >&2
  exit 1
}

if [ ! -s "$IPA" ]; then
  fail "IPA not found or empty: $IPA"
fi
if [[ ! "$EXPECTED_FORK_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9]{4})?$ ]]; then
  fail "invalid expected fork version: $EXPECTED_FORK_VERSION"
fi
if [[ ! "$EXPECTED_MARKETING_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "invalid expected marketing version: $EXPECTED_MARKETING_VERSION"
fi
if [[ ! "$EXPECTED_BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  fail "invalid expected build number: $EXPECTED_BUILD_NUMBER"
fi
if [ "$EXPECTED_MARKETING_VERSION" != "${EXPECTED_FORK_VERSION%%-*}" ]; then
  fail "marketing version does not match fork version base"
fi

command -v unzip >/dev/null 2>&1 || fail "unzip is required"
PLIST_BUDDY="/usr/libexec/PlistBuddy"
[ -x "$PLIST_BUDDY" ] || fail "PlistBuddy is required"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
unzip -q "$IPA" -d "$TMP_DIR"

APP_DIR="$(find "$TMP_DIR/Payload" -mindepth 1 -maxdepth 1 -type d -name '*.app' -print -quit 2>/dev/null || true)"
[ -n "$APP_DIR" ] || fail "top-level app bundle not found in IPA"
INFO_PLIST="$APP_DIR/Info.plist"
[ -f "$INFO_PLIST" ] || fail "Info.plist not found in app bundle"

read_plist() {
  "$PLIST_BUDDY" -c "Print :$1" "$INFO_PLIST" 2>/dev/null || true
}

ACTUAL_FORK_VERSION="$(read_plist ForkReleaseVersion)"
ACTUAL_MARKETING_VERSION="$(read_plist CFBundleShortVersionString)"
ACTUAL_BUILD_NUMBER="$(read_plist CFBundleVersion)"

[ "$ACTUAL_FORK_VERSION" = "$EXPECTED_FORK_VERSION" ] \
  || fail "ForkReleaseVersion=$ACTUAL_FORK_VERSION, expected $EXPECTED_FORK_VERSION"
[ "$ACTUAL_MARKETING_VERSION" = "$EXPECTED_MARKETING_VERSION" ] \
  || fail "CFBundleShortVersionString=$ACTUAL_MARKETING_VERSION, expected $EXPECTED_MARKETING_VERSION"
[ "$ACTUAL_BUILD_NUMBER" = "$EXPECTED_BUILD_NUMBER" ] \
  || fail "CFBundleVersion=$ACTUAL_BUILD_NUMBER, expected $EXPECTED_BUILD_NUMBER"

echo "Release IPA metadata verified: fork=$ACTUAL_FORK_VERSION marketing=$ACTUAL_MARKETING_VERSION build=$ACTUAL_BUILD_NUMBER"
