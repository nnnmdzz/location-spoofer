#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT/build.sh"

test -x "$BUILD_SCRIPT" || fail "build.sh must be executable"
grep -qF "build-unsigned-ipa.sh" "$BUILD_SCRIPT" || fail "build.sh must call build-unsigned-ipa.sh"
grep -qF "xcrun simctl list devices available" "$BUILD_SCRIPT" \
  || fail "build.sh must select an available iPhone Simulator"
grep -qF 'SIMULATOR_DESTINATION:-' "$BUILD_SCRIPT" \
  || fail "build.sh must keep the simulator destination override"

test -f "$ROOT/Scripts/build-unsigned-ipa.sh" || fail "build-unsigned-ipa.sh must exist"

# Should NOT contain Tunnel references
! grep -qF "Tunnel" "$ROOT/Scripts/build-unsigned-ipa.sh" || fail "build-unsigned-ipa.sh must not reference Tunnel"
! grep -qF "appex" "$ROOT/Scripts/build-unsigned-ipa.sh" || fail "build-unsigned-ipa.sh must not embed extensions"

echo "PASS: root build script contract"
