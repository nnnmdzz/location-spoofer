#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT_DIR/.github/workflows/release.yml"
GENERATOR="$ROOT_DIR/Scripts/generate-release-notes.sh"

fail() {
  echo "release notes contract failed: $*" >&2
  exit 1
}

grep -Fq 'fetch-depth: 0' "$WORKFLOW" || fail "release checkout must fetch tags"
grep -Fq 'Prepare release notes' "$WORKFLOW" || fail "release workflow must prepare notes before publishing"
grep -Fq 'bash Scripts/generate-release-notes.sh "$VERSION" "$RELEASE_NOTES" "$GITHUB_SHA"' "$WORKFLOW" \
  || fail "missing automatic release-note fallback"
grep -Fq 'Using archived release notes' "$WORKFLOW" || fail "hand-written archived notes must stay preferred"
grep -Fq '未找到 ${NOTES_FILE}；根据 Git 历史自动生成本次 Release 说明。' "$WORKFLOW" \
  || fail "release-note notice must delimit NOTES_FILE before non-ASCII punctuation"
if grep -Fq '未找到 $NOTES_FILE；' "$WORKFLOW"; then
  fail "bare NOTES_FILE before non-ASCII punctuation is unsafe under bash nounset"
fi
if grep -Fq '缺少版本归档' "$WORKFLOW"; then
  fail "missing archived notes must not block a release"
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
TEST_REPO="$TMP_DIR/repo"
mkdir -p "$TEST_REPO/Scripts"
cp "$GENERATOR" "$TEST_REPO/Scripts/generate-release-notes.sh"

cd "$TEST_REPO"
git init -q
git config user.name "Release Notes Test"
git config user.email "release-notes-test@example.invalid"

echo "base" > app.txt
git add app.txt Scripts/generate-release-notes.sh
git commit -q -m "feat: initial release"
git tag v1.0.0-0001

echo "next" >> app.txt
git add app.txt
git commit -q -m "fix: second release change"

RELEASE_DATE=2026-08-12 bash Scripts/generate-release-notes.sh \
  v1.0.0-0002 "$TMP_DIR/untagged.md" HEAD >/dev/null

grep -Fq '# v1.0.0-0002' "$TMP_DIR/untagged.md" || fail "generated title is wrong"
grep -Fq 'fix: second release change' "$TMP_DIR/untagged.md" || fail "generated notes omit release commits"
grep -Fq '<!-- commit-range: v1.0.0-0001..v1.0.0-0002 -->' "$TMP_DIR/untagged.md" \
  || fail "untagged release range is wrong"

git tag v1.0.0-0002
RELEASE_DATE=2026-08-12 bash Scripts/generate-release-notes.sh \
  v1.0.0-0002 "$TMP_DIR/tagged.md" HEAD >/dev/null

grep -Fq 'fix: second release change' "$TMP_DIR/tagged.md" || fail "tag-triggered generation collapsed to an empty range"
grep -Fq '<!-- commit-range: v1.0.0-0001..v1.0.0-0002 -->' "$TMP_DIR/tagged.md" \
  || fail "tag-triggered release range is wrong"

if bash Scripts/generate-release-notes.sh v1.0.0-beta "$TMP_DIR/invalid.md" HEAD >/dev/null 2>&1; then
  fail "generator accepted a version rejected by release.yml"
fi

echo "release notes contract passed"
