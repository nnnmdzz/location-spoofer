#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="$ROOT/Shared/AppRemoteConfiguration.swift"
CONTENT="$ROOT/App/ContentView.swift"
MAP="$ROOT/App/MapHomeView.swift"
SETUP="$ROOT/App/FirstSetupView.swift"
SETTINGS="$ROOT/App/SettingsView.swift"
BUG_REPORT="$ROOT/App/BugReportView.swift"
GITHUB_SUBMISSION="$ROOT/Shared/GitHubSubmission.swift"
FORK_RELEASE="$ROOT/Shared/ForkFeatures/ForkReleaseService.swift"
FORK_UPDATE_VIEW="$ROOT/App/ForkFeatures/ForkUpdateCheckView.swift"
DISCUSSION_FORM="$ROOT/.github/DISCUSSION_TEMPLATE/第三方配置分享.yml"
ISSUE_FORM="$ROOT/.github/ISSUE_TEMPLATE/bug-report.yml"
ISSUE_CONFIG="$ROOT/.github/ISSUE_TEMPLATE/config.yml"

fail() { echo "FAIL: $1" >&2; exit 1; }

# Upstream remote configuration remains available only for community prompt policy.
grep -q 'static let fallback = AppRemoteConfiguration' "$CONFIG" || fail "missing remote-configuration fallback"
grep -q 'timeoutIntervalForRequest = 1.5' "$CONFIG" || fail "remote configuration timeout changed"

# Fork update behavior is manual and fork-owned.
! grep -Fq '.task { await checkForUpdates() }' "$CONTENT" || fail "startup must not auto-check updates"
grep -Fq 'ForkUpdateCheckView()' "$SETTINGS" || fail "Settings must expose the fork manual update view"
grep -Fq 'api.github.com/repos/nnnmdzz/location-spoofer/releases?per_page=30' "$FORK_RELEASE" || fail "fork release API missing"
grep -Fq 'browser_download_url' "$FORK_RELEASE" || fail "must use GitHub asset download URL"
grep -Fq 'textSelection(.enabled)' "$FORK_UPDATE_VIEW" || fail "IPA URL must be selectable"
grep -Fq 'UIPasteboard.general.string = result.ipaURL.absoluteString' "$FORK_UPDATE_VIEW" || fail "IPA URL must be copyable"

# All submission actions owned by this fork must stay inside this repository.
grep -Fq 'https://github.com/nnnmdzz/location-spoofer' "$GITHUB_SUBMISSION" || fail "fork GitHub destination missing"
! grep -Fq 'https://github.com/xweiba/location-spoofer' "$GITHUB_SUBMISSION" || fail "submission action still targets upstream"
grep -Fq 'GitHubSubmission.bugReportURL' "$BUG_REPORT" || fail "bug report must use shared destination"
grep -Fq 'SafariView(url: destination.url)' "$BUG_REPORT" || fail "bug report must use in-App Safari"
! grep -q 'UIApplication.shared.open' "$BUG_REPORT" || fail "bug report must not hand off to external GitHub client"

# Community contribution flow remains intact while changing only ownership.
grep -q '社区分享成功配置？' "$MAP" || fail "community prompt missing"
grep -q 'Button("去提交")' "$MAP" || fail "community submit action missing"
grep -q 'Button("复制模板")' "$MAP" || fail "community copy action missing"
grep -q 'GitHubSubmission.communityContributionTemplate' "$MAP" || fail "community template integration missing"
grep -q 'SafariDestination' "$MAP" || fail "community contribution must use in-App Safari"
grep -Fq '匿名收录，不在 README 展示投稿账号' "$GITHUB_SUBMISSION" || fail "anonymous attribution option missing"
test -s "$DISCUSSION_FORM" || fail "discussion form missing"
test -s "$ISSUE_FORM" || fail "bug report issue form missing"
grep -Fq 'blank_issues_enabled: false' "$ISSUE_CONFIG" || fail "blank Issues must remain disabled"

for action in '使用帮助' '功能建议' '分享第三方配置'; do
  grep -Fq "Label(\"$action\"" "$SETTINGS" || fail "Settings support missing: $action"
done

for obsolete in \
  '我已配置，开始检测' \
  '确认完成，重新检测' \
  '下一步：导入配置' \
  '我已导入，检测接口连接'; do
  ! grep -q "$obsolete" "$SETUP" || fail "setup footer retained dynamic label: $obsolete"
done
test "$(grep -c 'actionLabel("完成")' "$SETUP")" -eq 4 || fail "setup footer labels changed"

application_line="$(grep -n 'Section("应用")' "$SETTINGS" | head -n 1 | cut -d: -f1)"
certificate_line="$(grep -n 'Section("证书")' "$SETTINGS" | head -n 1 | cut -d: -f1)"
test "$application_line" -lt "$certificate_line" || fail "certificate reset section ordering changed"

echo "PASS: fork update and contribution contract"
