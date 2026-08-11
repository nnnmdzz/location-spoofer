#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

quick="App/ForkFeatures/HomeQuickActions.swift"
saved_service="Shared/ForkFeatures/SystemShortcutService.swift"
saved_view="App/ForkFeatures/SavedShortcutsView.swift"
private_service="Shared/ForkFeatures/PrivateUpdateService.swift"
update_view="App/ForkFeatures/ForkUpdateCheckView.swift"
plist="Resources/Info.plist"
content="App/ContentView.swift"
home="App/MapHomeView.swift"

for file in "$quick" "$saved_service" "$saved_view" "$private_service"; do
  [[ -f "$file" ]] || fail "missing automation/private update file: $file"
done

grep -Fq 'UIApplication.shared.shortcutItems = items' "$quick" || fail "dynamic Home Screen quick actions must be registered"
grep -Fq 'case favorite(UUID)' "$quick" || fail "quick actions must support recent favorites"
grep -Fq 'case clearVirtualLocation' "$quick" || fail "quick actions must support clearing virtual location"
grep -Fq 'case enhancements' "$quick" || fail "quick actions must support enhancements entry"
grep -Fq 'UIWindowSceneDelegate' "$quick" || fail "scene lifecycle must handle quick actions"
grep -Fq 'performActionFor shortcutItem: UIApplicationShortcutItem' "$quick" || fail "scene delegate must receive resumed quick actions"
grep -Fq 'configuration.delegateClass = LocationSpooferSceneDelegate.self' "$quick" || fail "SwiftUI app delegate must install scene delegate"
grep -Fq 'RecentFavoriteStore.record' "$home" || fail "successful in-app favorite apply must record recency"
grep -Fq 'ShortcutLocationService.applyFavorite' "$content" || fail "Home Screen favorite action must reuse shortcut service"

grep -Fq 'case fixedText' "$saved_service" || fail "saved shortcuts must support fixed text input"
grep -Fq 'case clipboard' "$saved_service" || fail "saved shortcuts must support clipboard input"
grep -Fq 'components.scheme = "shortcuts"' "$saved_service" || fail "saved shortcuts must invoke Shortcuts URL scheme"
grep -Fq 'x-success' "$saved_service" || fail "saved shortcuts must configure success callback"
grep -Fq 'x-cancel' "$saved_service" || fail "saved shortcuts must configure cancel callback"
grep -Fq 'x-error' "$saved_service" || fail "saved shortcuts must configure error callback"
grep -Fq 'fork_shortcut_callback_nonce' "$saved_service" || fail "shortcut callbacks must be correlated with a nonce"
grep -Fq '<string>paopaolocation-spoofer</string>' "$plist" || fail "callback URL scheme must be registered"
grep -Fq '.onOpenURL' App/PaopaoLocationSpooferApp.swift || fail "app must route callback URLs"

grep -Fq 'kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly' "$private_service" || fail "private update configuration must use ThisDeviceOnly Keychain accessibility"
grep -Fq 'forHTTPHeaderField: "Authorization"' "$private_service" || fail "Personal Update Token must travel in authorization header"
grep -Fq 'configuration.personalToken' "$private_service" || fail "Personal Update Token must be read from Keychain configuration"
grep -Fq 'appendingPathComponent("location-spoofer"' "$private_service" || fail "private worker API must use location-spoofer route"
grep -Fq 'manifestURL.scheme?.lowercased() == "https"' "$private_service" || fail "private manifest must require HTTPS"
grep -Fq 'components.scheme = "itms-services"' "$private_service" || fail "private update must hand off to iOS OTA installer"
grep -Fq 'PrivateUpdateConfigurationStore' "$update_view" || fail "update UI must expose private configuration"
grep -Fq '直接安装已签名版本' "$update_view" || fail "update UI must expose direct signed install action"
grep -Fq '复制 IPA 下载地址' "$update_view" || fail "unsigned fallback must remain available"

if grep -Eq 'workers\.dev|r2\.cloudflarestorage\.com' App/ForkFeatures/ForkUpdateCheckView.swift Shared/ForkFeatures/PrivateUpdateService.swift; then
  fail "private Worker/R2 endpoint must not be hard-coded in public source"
fi

echo "PASS: automation and private update contract"
