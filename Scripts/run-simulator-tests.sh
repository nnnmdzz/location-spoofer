#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/PaopaoLocationSpoofer.xcodeproj"
SCHEME="PaopaoLocationSpoofer"
RESULT_DIR="$ROOT/build/TestResults"
DERIVED_DATA="$ROOT/build/TestDerivedData"

mkdir -p "$RESULT_DIR"

select_simulator_id() {
  local simulator_id

  simulator_id="$(
    xcrun simctl list devices available \
      | awk -F '[()]' '/^[[:space:]]*iPhone/ && /Booted/ { print $2; exit }'
  )"
  if [ -z "$simulator_id" ]; then
    simulator_id="$(
      xcrun simctl list devices available \
        | awk -F '[()]' '/^[[:space:]]*iPhone/ { print $2; exit }'
    )"
  fi

  if [ -z "$simulator_id" ]; then
    echo "No available iPhone Simulator was found." >&2
    echo "Set SIMULATOR_DESTINATION to an installed simulator destination." >&2
    xcrun simctl list devices >&2 || true
    return 1
  fi

  printf '%s\n' "$simulator_id"
}

boot_simulator() {
  local simulator_id="$1"

  # simctl boot returns an error when the device is already booted. That state is
  # acceptable; bootstatus below is the authoritative readiness check.
  xcrun simctl boot "$simulator_id" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$simulator_id" -b
}

is_simulator_infrastructure_failure() {
  local log_file="$1"
  grep -Eiq \
    'CoreSimulatorService|com\.apple\.CoreSimulator\.SimError|Unable to boot|Failed to boot|device failed to boot|Lost connection to.*Simulator|Failed to start test manager|Timed out waiting for.*Simulator|device is not currently booted' \
    "$log_file"
}

run_test_attempt() {
  local attempt="$1"
  local log_file="$RESULT_DIR/xcodebuild-attempt-${attempt}.log"
  local result_bundle="$RESULT_DIR/PaopaoLocationSpooferTests-attempt-${attempt}.xcresult"

  rm -rf "$result_bundle"

  set +e
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -destination "$resolved_destination" \
    -destination-timeout 120 \
    -derivedDataPath "$DERIVED_DATA" \
    -resultBundlePath "$result_bundle" \
    test 2>&1 | tee "$log_file"
  local status="${PIPESTATUS[0]}"
  set -e

  return "$status"
}

cd "$ROOT"

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "Missing required command: xcodegen" >&2
  echo "Install XcodeGen: brew install xcodegen" >&2
  exit 1
fi

xcodegen generate

simulator_id=""
resolved_destination="${SIMULATOR_DESTINATION:-}"

if [ -n "$resolved_destination" ]; then
  if [[ "$resolved_destination" =~ (^|,)id=([^,]+) ]]; then
    simulator_id="${BASH_REMATCH[2]}"
    boot_simulator "$simulator_id"
  fi
else
  simulator_id="$(select_simulator_id)"
  resolved_destination="platform=iOS Simulator,id=${simulator_id}"
  boot_simulator "$simulator_id"
fi

echo "Running iOS Simulator tests on: $resolved_destination"

if run_test_attempt 1; then
  exit 0
else
  first_status="$?"
fi

first_log="$RESULT_DIR/xcodebuild-attempt-1.log"
if ! is_simulator_infrastructure_failure "$first_log"; then
  echo "Tests failed without a Simulator infrastructure signature; not retrying." >&2
  exit "$first_status"
fi

echo "Simulator infrastructure failure detected; retrying once with a clean test environment." >&2
rm -rf "$DERIVED_DATA"

if [ -n "$simulator_id" ]; then
  xcrun simctl shutdown "$simulator_id" >/dev/null 2>&1 || true
  boot_simulator "$simulator_id"
fi

if run_test_attempt 2; then
  exit 0
else
  second_status="$?"
fi

xcrun simctl list devices >&2 || true
exit "$second_status"
