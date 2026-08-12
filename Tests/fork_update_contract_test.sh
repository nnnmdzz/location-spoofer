#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

adapter="Shared/ForkFeatures/PrivateSigningAdapter.swift"
public_release="Shared/ForkFeatures/PublicReleaseSource.swift"
view="App/ForkFeatures/ForkUpdateCheckView.swift"
content="App/ContentView.swift"
settings="App/SettingsView.swift"
submission="Shared/GitHubSubmission.swift"

[[ -f "$adapter" ]] || fail "missing PrivateSigningAdapter"
[[ -f "$public_release" ]] || fail "missing PublicReleaseSource"
[[ -f "$view" ]] || fail "missing ForkUpdateCheckView"

# Public unsigned release lookup is an app-local convenience path. Private signed update is a
# separate Worker v2 project flow and must not receive the public IPA URL.
grep -Fq 'repository: "nnnmdzz/location-spoofer"' "$adapter" || fail "public release discovery must use fork repo"
grep -Fq 'assetNameTemplate: "Location-Spoofer-{tag}-unsigned.ipa"' "$adapter" || fail "public release discovery must validate the versioned IPA asset name"
grep -Fq 'struct PublicReleaseSource' "$public_release" || fail "public unsigned release lookup must remain an app-local source"
grep -Fq 'PublicUpdate.source.latestRelease' "$view" || fail "public update check must use the app-local source"
grep -Fq 'projectID: PrivateSigning.projectID' "$view" || fail "private update must use the Worker project registry"
if grep -rFq 'GitHubReleaseSource' --include='*.swift' App Shared; then
  fail "private signing must not use client-side GitHub release discovery"
fi

if grep -Fq '.task { await checkForUpdates() }' "$content"; then
  fail "ContentView must not auto-check updates"
fi
grep -Fq 'ForkUpdateCheckView()' "$settings" || fail "Settings manual update button must open fork update view"
grep -Fq 'textSelection(.enabled)' "$view" || fail "IPA URL must be selectable"
grep -Fq 'UIPasteboard.general.string = candidate.ipaURL.absoluteString' "$view" || fail "IPA URL must be copyable"

release_version="$(sed -nE 's/^[[:space:]]*FORK_RELEASE_VERSION: "([^"]+)".*/\1/p' project.yml | head -n 1)"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]{4}$ ]] || fail "missing or invalid fork release build setting"
grep -Fq '<key>ForkReleaseVersion</key>' Resources/Info.plist || fail "missing ForkReleaseVersion plist key"
grep -Fq '<string>$(FORK_RELEASE_VERSION)</string>' Resources/Info.plist || fail "ForkReleaseVersion must come from project.yml"

grep -Fq 'https://github.com/nnnmdzz/location-spoofer' "$submission" || fail "submission URLs must use fork repo"
if grep -Fq 'https://github.com/xweiba/location-spoofer' "$submission"; then
  fail "submission URLs must not write to upstream"
fi

echo "fork update contract OK"
