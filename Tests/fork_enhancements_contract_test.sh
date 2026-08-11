#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

settings="App/SettingsView.swift"
hub="App/ForkFeatures/ForkEnhancementsView.swift"
navigator="App/SystemSettingsNavigator.swift"

[[ -f "$hub" ]] || fail "missing fork enhancements hub"
grep -Fq 'Label("增强功能", systemImage: "sparkles")' "$settings" || fail "Settings must expose exactly one enhancement entry"
test "$(grep -Fc 'ForkEnhancementsView()' "$settings")" -eq 1 || fail "Settings must keep one fork enhancement entry"

grep -Fq 'WlocAccuracySettingsSection()' "$hub" || fail "enhancements must expose WLOC accuracy"
grep -Fq 'LocationEffectStatusPanel()' "$hub" || fail "enhancements must expose effect diagnostics"
grep -Fq 'effectMonitor.retry(reason: "增强功能手动检测")' "$hub" || fail "enhancements must expose one-shot soft refresh diagnostics"
for destination in locationServices wifi appPermissions general; do
  grep -Fq "destination: .$destination" "$hub" || fail "missing system settings shortcut: $destination"
done

grep -A8 'case .locationServices:' "$navigator" | grep -Fq '"prefs:root=Privacy&path=LOCATION"' || fail "location services private shortcut must remain first"
grep -A6 'var shouldFallbackToAppSettings' "$navigator" | grep -A2 'case .locationServices:' | grep -Fq 'return false' || fail "location services must not fallback to app settings"

grep -Fq '不会清除 locationd 缓存、关闭 GPS/GNSS' "$hub" || fail "diagnostics must not overclaim system control"

echo "PASS: fork enhancements hub contract"
