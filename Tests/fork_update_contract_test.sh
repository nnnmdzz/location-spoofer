#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

adapter="Shared/ForkFeatures/PrivateSigningAdapter.swift"
view="App/ForkFeatures/ForkUpdateCheckView.swift"
content="App/ContentView.swift"
settings="App/SettingsView.swift"
submission="Shared/GitHubSubmission.swift"

[[ -f "$adapter" ]] || fail "missing PrivateSigningAdapter"
[[ -f "$view" ]] || fail "missing ForkUpdateCheckView"

# Release discovery itself lives in the private-signer-ios package. What this repository owns is
# pointing it at the right repository and the right asset name.
grep -Fq 'repository = "nnnmdzz/location-spoofer"' "$adapter" || fail "release discovery must use fork repo"
grep -Fq 'assetNameTemplate = "Location-Spoofer-{tag}-unsigned.ipa"' "$adapter" || fail "must validate versioned IPA asset name"
grep -Fq 'GitHubReleaseSource(' "$adapter" || fail "release discovery must use the package release source"

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
