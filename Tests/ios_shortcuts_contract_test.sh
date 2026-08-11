#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

intents="App/ForkFeatures/LocationSpooferAppIntents.swift"
service="Shared/ForkFeatures/ShortcutLocationService.swift"
app="App/PaopaoLocationSpooferApp.swift"

[[ -f "$intents" ]] || fail "missing App Intents implementation"
[[ -f "$service" ]] || fail "missing shared shortcut service"

grep -Fq 'import AppIntents' "$intents" || fail "AppIntents framework must be imported"
grep -Fq '@available(iOS 16.0, *)' "$intents" || fail "App Intents must preserve iOS 15 deployment compatibility"
grep -Fq 'struct FavoriteLocationEntity: AppEntity' "$intents" || fail "favorites must be exposed as AppEntity"
grep -Fq 'struct FavoriteLocationEntityQuery: EntityQuery' "$intents" || fail "favorites must provide EntityQuery"
grep -Fq '@Property(title: "WGS-84 纬度")' "$intents" || fail "favorite entity must expose WGS-84 latitude"
grep -Fq '@Property(title: "WGS-84 经度")' "$intents" || fail "favorite entity must expose WGS-84 longitude"
for intent in GetFavoriteLocationsIntent SetFavoriteVirtualLocationIntent ClearVirtualLocationIntent VirtualLocationStatusIntent; do
  grep -Fq "struct $intent: AppIntent" "$intents" || fail "missing intent: $intent"
done
grep -Fq 'ReturnsValue<[FavoriteLocationEntity]>' "$intents" || fail "get favorites intent must return an entity array"

test "$(grep -Fc 'AppShortcut(' "$intents")" -eq 4 || fail "exactly four first-party App Shortcuts are expected"
test "$(grep -Fc '\(.applicationName)' "$intents")" -ge 4 || fail "App Shortcut phrases must contain applicationName token"
grep -Fq 'LocationSpooferAppShortcuts.updateAppShortcutParameters()' "$app" || fail "app must refresh shortcut parameters"

grep -Fq 'LocationActionCoordinator()' "$service" || fail "APP mode shortcut must reuse LocationActionCoordinator"
grep -Fq 'ThirdPartyProxyManager.shared.save(favorite)' "$service" || fail "third-party shortcut must reuse ThirdPartyProxyManager"
grep -Fq 'RecentFavoriteStore.record(favorite.id)' "$service" || fail "successful shortcuts must update recent favorites"
grep -Fq 'favorite.coordinatePair' Shared/FavoriteLocationStore.swift || fail "favorite model must retain typed coordinate pair"
grep -Fq 'WlocAccuracyPreference.shared.meters' "$service" || fail "shortcut reporting must use global WLOC accuracy"
grep -Fq 'runtime.isInitialized(runtime.mode)' "$service" || fail "shortcut must reject unconfigured runtime mode"

if grep -Fq 'CoordinateConverter.convert' "$service"; then
  fail "shortcut service must not introduce a second coordinate conversion path"
fi

echo "PASS: iOS shortcuts integration contract"
