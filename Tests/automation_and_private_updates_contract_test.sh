#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

quick="App/ForkFeatures/HomeQuickActions.swift"
saved_service="Shared/ForkFeatures/SystemShortcutService.swift"
saved_view="App/ForkFeatures/SavedShortcutsView.swift"
adapter="Shared/ForkFeatures/PrivateSigningAdapter.swift"
public_release="Shared/ForkFeatures/PublicReleaseSource.swift"
enhancements="App/ForkFeatures/ForkEnhancementsView.swift"
update_view="App/ForkFeatures/ForkUpdateCheckView.swift"
plist="Resources/Info.plist"
content="App/ContentView.swift"
home="App/MapHomeView.swift"

for file in "$quick" "$saved_service" "$saved_view" "$adapter" "$public_release"; do
  [[ -f "$file" ]] || fail "missing automation/private update file: $file"
done

# The signing client itself lives in private-signer-ios. This repository only owns the app-specific
# integration boundary and public unsigned-release convenience path.
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

# PrivateSigner must be immutable for a release build. Until v0.3.0 can be tagged through the
# repository tooling, pin the exact merged SDK commit rather than a floating branch/range.
grep -Fq 'url: https://github.com/nnnmdzz/private-signer-ios.git' project.yml || fail "the signing client package must be declared"
grep -Fq 'revision: e54fc2bbfcfb2c38d7e18d154e6aeb1a4ea78bd6' project.yml || fail "the v3 signing client must be pinned to the reviewed SDK commit"
grep -Fq 'product: PrivateSignerKit' project.yml || fail "the app must depend on PrivateSignerKit"
grep -Fq 'product: PrivateSignerSelfUpdate' project.yml || fail "the app must depend on PrivateSignerSelfUpdate"
grep -Fq 'product: PrivateSignerUI' project.yml || fail "the app must depend on PrivateSignerUI"

# Application-specific signing construction stays in one adapter. The only compiled signing
# identity is a stable Worker project ID; profile IDs and release URLs are runtime Worker state.
for symbol in SignerKeychainConfiguration SelfUpdateCoordinator; do
  hits=$(grep -rl "$symbol" --include='*.swift' App Shared | grep -v "^$adapter$" || true)
  [[ -z "$hits" ]] || fail "$symbol is constructed outside the adapter: $hits"
done

grep -Fq 'projectID = "location-spoofer"' "$adapter" || fail "the app must declare its stable Worker project ID"
if grep -rFq 'personal-main' --include='*.swift' App Shared; then
  fail "personal-main must not survive as a client-side profile convention"
fi
if grep -Eq 'static let profile(ID|Id)|defaultProfileID' "$adapter"; then
  fail "the app must not compile a provisioning profile ID"
fi
if grep -rFq 'GitHubReleaseSource' --include='*.swift' App Shared; then
  fail "private signing must not rediscover GitHub releases in the SDK integration"
fi

# Losing the Stable Configuration Group means every installed client loses its Worker URL and
# token on the next self-signature, so both the current and the legacy group must stay declared.
grep -Fq 'configurationAccessGroup = "\(teamID).com.paopaolabs.location-spoofer"' "$adapter" || fail "the Stable Configuration Group must stay declared"
grep -Fq 'app.cauliflower3903.lemon2546' "$adapter" || fail "the legacy access group must stay readable for already-installed clients"
grep -Fq 'keychainService = "com.paopaolabs.location-spoofer.private-update"' "$adapter" || fail "the Keychain service must stay unchanged so shipped clients keep their configuration"

# Public unsigned IPA discovery is allowed only as an app-local fallback. It must remain visibly
# separate from project signing, whose source URL is resolved by the Worker.
grep -Fq 'struct PublicReleaseSource' "$public_release" || fail "public unsigned release discovery must remain app-owned"
grep -Fq 'repository: "nnnmdzz/location-spoofer"' "$adapter" || fail "the public release repository must stay declared"
grep -Fq 'assetNameTemplate: "Location-Spoofer-{tag}-unsigned.ipa"' "$adapter" || fail "the public release asset template must match the release workflow"
grep -Fq 'PublicUpdate.source.latestRelease' "$update_view" || fail "the unsigned fallback must use the app-local public release source"
grep -Fq '公开 IPA 地址不会发给 Worker' "$update_view" || fail "the UI must keep the public/source separation explicit"

# Location Spoofer's client principal is project-scoped. The app exposes project self-update but
# deliberately does not expose the SDK's arbitrary URL/upload signer.
grep -Fq 'SelfUpdateView(' "$update_view" || fail "update UI must expose the private signed update channel"
grep -Fq 'projectID: PrivateSigning.projectID' "$update_view" || fail "private update UI must use the stable Worker project ID"
grep -Fq '复制 IPA 下载地址' "$update_view" || fail "unsigned fallback must remain available"
if grep -rFq 'SigningJobsView(' --include='*.swift' App Shared; then
  fail "Location Spoofer must not expose generic arbitrary-IPA signing with its project-scoped token"
fi

# No credential and no endpoint may be compiled into this public repository.
if grep -rEq 'workers\.dev|r2\.cloudflarestorage\.com' --include='*.swift' App Shared; then
  fail "private Worker/R2 endpoint must not be hard-coded in public source"
fi
if grep -rEqi '(signing[_-]?request[_-]?token|personal[_-]?update[_-]?token)[[:space:]]*=[[:space:]]*"[^"]+"' --include='*.swift' App Shared; then
  fail "a signing token must never be compiled into public source"
fi

# The app's interface is Chinese but hardcoded, so the bundle must declare that language; every
# localized package inside it follows the host application's localization context.
grep -Fq '<string>zh-Hans</string>' "$plist" || fail "the bundle must declare the language its interface is actually in"
grep -Fq 'CFBundleLocalizations' "$plist" || fail "CFBundleLocalizations must list the supported languages"
grep -Fq 'developmentLanguage: zh-Hans' project.yml || fail "XcodeGen must not reset the development language to en"

echo "PASS: automation and v3 private update contract"
