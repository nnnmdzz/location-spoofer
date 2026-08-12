#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

quick="App/ForkFeatures/HomeQuickActions.swift"
saved_service="Shared/ForkFeatures/SystemShortcutService.swift"
saved_view="App/ForkFeatures/SavedShortcutsView.swift"
adapter="Shared/ForkFeatures/PrivateSigningAdapter.swift"
enhancements="App/ForkFeatures/ForkEnhancementsView.swift"
update_view="App/ForkFeatures/ForkUpdateCheckView.swift"
plist="Resources/Info.plist"
content="App/ContentView.swift"
home="App/MapHomeView.swift"

for file in "$quick" "$saved_service" "$saved_view" "$adapter"; do
  [[ -f "$file" ]] || fail "missing automation/private update file: $file"
done

# The signing client itself now lives in the private-signer-ios package, which owns the tests for
# the transport, the Keychain rules, and the job lifecycle. What this repository still has to
# guarantee is that the integration is wired correctly and leaks nothing.
for file in Shared/ForkFeatures/PrivateSigningService.swift \
            Shared/ForkFeatures/PrivateUpdateService.swift \
            Shared/ForkFeatures/ForkReleaseService.swift \
            App/ForkFeatures/PrivateSigningView.swift; do
  [[ -f "$file" ]] && fail "$file was migrated into the private-signer-ios package and must not come back"
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

# The package is the only signing client, pinned to an exact version.
grep -Fq 'url: https://github.com/nnnmdzz/private-signer-ios.git' project.yml || fail "the signing client package must be declared"
grep -Fq 'exactVersion:' project.yml || fail "the signing client package must be pinned to an exact version"
grep -Fq 'product: PrivateSignerKit' project.yml || fail "the app must depend on PrivateSignerKit"

# Application-specific signing values live in the adapter and nowhere else.
for symbol in SignerKeychainConfiguration GitHubReleaseSource SelfUpdateCoordinator; do
  hits=$(grep -rl "$symbol" --include='*.swift' App Shared | grep -v "^$adapter$" || true)
  [[ -z "$hits" ]] || fail "$symbol is constructed outside the adapter: $hits"
done

# Losing the Stable Configuration Group means every installed client loses its Worker URL and
# token on the next self-signature, so both the current and the legacy group must stay declared.
grep -Fq 'configurationAccessGroup = "\(teamID).com.paopaolabs.location-spoofer"' "$adapter" || fail "the Stable Configuration Group must stay declared"
grep -Fq 'app.cauliflower3903.lemon2546' "$adapter" || fail "the legacy access group must stay readable for already-installed clients"
grep -Fq 'keychainService = "com.paopaolabs.location-spoofer.private-update"' "$adapter" || fail "the Keychain service must stay unchanged so shipped clients keep their configuration"

# Release discovery must keep matching the asset the release workflow actually publishes.
grep -Fq 'assetNameTemplate = "Location-Spoofer-{tag}-unsigned.ipa"' "$adapter" || fail "the release asset template must match the published asset name"
grep -Fq 'repository = "nnnmdzz/location-spoofer"' "$adapter" || fail "the release repository must stay declared"

# Both entry points stay reachable from the UI.
grep -Fq 'SigningJobsView(context: PrivateSigning.uiContext)' "$enhancements" || fail "enhancements UI must expose arbitrary private IPA signing"
grep -Fq 'SelfUpdateView(' "$update_view" || fail "update UI must expose the private signed update channel"
grep -Fq '复制 IPA 下载地址' "$update_view" || fail "unsigned fallback must remain available"

# No credential and no endpoint may be compiled into this public repository.
if grep -rEq 'workers\.dev|r2\.cloudflarestorage\.com' --include='*.swift' App Shared; then
  fail "private Worker/R2 endpoint must not be hard-coded in public source"
fi
if grep -rEqi '(signing[_-]?request[_-]?token|personal[_-]?update[_-]?token)[[:space:]]*=[[:space:]]*"[^"]+"' --include='*.swift' App Shared; then
  fail "a signing token must never be compiled into public source"
fi

echo "PASS: automation and private update contract"
