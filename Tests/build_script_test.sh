#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_SCRIPT="$ROOT/build.sh"
SIMULATOR_TEST_SCRIPT="$ROOT/Scripts/run-simulator-tests.sh"

test -x "$BUILD_SCRIPT" || fail "build.sh must be executable"
grep -qF "build-unsigned-ipa.sh" "$BUILD_SCRIPT" || fail "build.sh must call build-unsigned-ipa.sh"
grep -qF "run-simulator-tests.sh" "$BUILD_SCRIPT" || fail "build.sh --test must delegate simulator tests"

test -f "$ROOT/Scripts/build-unsigned-ipa.sh" || fail "build-unsigned-ipa.sh must exist"
test -f "$SIMULATOR_TEST_SCRIPT" || fail "run-simulator-tests.sh must exist"
grep -qF "xcrun simctl list devices available" "$SIMULATOR_TEST_SCRIPT" \
  || fail "simulator test runner must select an available iPhone Simulator"
grep -qF 'SIMULATOR_DESTINATION:-' "$SIMULATOR_TEST_SCRIPT" \
  || fail "simulator test runner must keep the simulator destination override"
grep -qF "simctl bootstatus" "$SIMULATOR_TEST_SCRIPT" \
  || fail "simulator test runner must wait for the selected Simulator to boot"
grep -qF "resultBundlePath" "$SIMULATOR_TEST_SCRIPT" \
  || fail "simulator test runner must preserve an xcresult bundle"
grep -qF "Simulator infrastructure failure detected" "$SIMULATOR_TEST_SCRIPT" \
  || fail "simulator test runner must retry infrastructure failures explicitly"
grep -qF "not retrying" "$SIMULATOR_TEST_SCRIPT" \
  || fail "simulator test runner must not retry ordinary XCTest failures"

# Should NOT contain Tunnel references
! grep -qF "Tunnel" "$ROOT/Scripts/build-unsigned-ipa.sh" || fail "build-unsigned-ipa.sh must not reference Tunnel"
! grep -qF "appex" "$ROOT/Scripts/build-unsigned-ipa.sh" || fail "build-unsigned-ipa.sh must not embed extensions"

echo "PASS: root build script contract"
