#!/usr/bin/env bash
set -euo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

service="Shared/ForkFeatures/ForkReleaseService.swift"
view="App/ForkFeatures/ForkUpdateCheckView.swift"
content="App/ContentView.swift"
settings="App/SettingsView.swift"
submission="Shared/GitHubSubmission.swift"

[[ -f "$service" ]] || fail "missing ForkReleaseService"
[[ -f "$view" ]] || fail "missing ForkUpdateCheckView"

grep -Fq 'https://api.github.com/repos/nnnmdzz/location-spoofer/releases?per_page=30' "$service" || fail "release API must use fork repo"
grep -Fq 'browser_download_url' "$service" || fail "must decode GitHub browser_download_url"
grep -Fq 'Location-Spoofer-' "$service" || fail "must validate versioned IPA asset name"
grep -Fq 'Release \\(tag) 打包不完整，未找到 IPA' "$service" || fail "missing incomplete-release error"

if grep -Fq '.task { await checkForUpdates() }' "$content"; then
  fail "ContentView must not auto-check updates"
fi
grep -Fq 'ForkUpdateCheckView()' "$settings" || fail "Settings manual update button must open fork update view"
grep -Fq 'textSelection(.enabled)' "$view" || fail "IPA URL must be selectable"
grep -Fq 'UIPasteboard.general.string = result.ipaURL.absoluteString' "$view" || fail "IPA URL must be copyable"

grep -Fq 'FORK_RELEASE_VERSION: "1.0.5-0001"' project.yml || fail "missing fork release build setting"
grep -Fq '<key>ForkReleaseVersion</key>' Resources/Info.plist || fail "missing ForkReleaseVersion plist key"

grep -Fq 'https://github.com/nnnmdzz/location-spoofer' "$submission" || fail "submission URLs must use fork repo"
if grep -Fq 'https://github.com/xweiba/location-spoofer' "$submission"; then
  fail "submission URLs must not write to upstream"
fi

echo "fork update contract OK"
