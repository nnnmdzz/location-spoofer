#!/usr/bin/env bash
set -euo pipefail

VERSION="${1:-}"
OUTPUT="${2:-}"
TARGET_REF="${3:-HEAD}"

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9]{4})?$ ]]; then
  echo "Usage: $0 v<major>.<minor>.<patch>[-NNNN] [output-file] [target-ref]" >&2
  exit 2
fi

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="docs/releases/${VERSION}.md"
fi

TARGET_COMMIT="$(git rev-parse --verify "${TARGET_REF}^{commit}" 2>/dev/null || true)"
if [[ -z "$TARGET_COMMIT" ]]; then
  echo "Unable to resolve release target: $TARGET_REF" >&2
  exit 1
fi

# On a tag-triggered workflow the release tag already points at TARGET_COMMIT.
# Describe from its parent in that case so the generated range starts at the
# previous release instead of collapsing to VERSION..VERSION.
DESCRIBE_REF="$TARGET_COMMIT"
VERSION_TAG_COMMIT="$(git rev-parse -q --verify "refs/tags/${VERSION}^{commit}" 2>/dev/null || true)"
if [[ -n "$VERSION_TAG_COMMIT" && "$VERSION_TAG_COMMIT" == "$TARGET_COMMIT" ]]; then
  if git rev-parse -q --verify "${TARGET_COMMIT}^" >/dev/null; then
    DESCRIBE_REF="${TARGET_COMMIT}^"
  else
    DESCRIBE_REF=""
  fi
fi

PREVIOUS_TAG=""
if [[ -n "$DESCRIBE_REF" ]]; then
  PREVIOUS_TAG="$(git describe --tags --abbrev=0 --match 'v*' "$DESCRIBE_REF" 2>/dev/null || true)"
fi

if [[ -n "$PREVIOUS_TAG" ]]; then
  RANGE="$PREVIOUS_TAG..$TARGET_COMMIT"
  RANGE_LABEL="$PREVIOUS_TAG..$VERSION"
else
  RANGE="$TARGET_COMMIT"
  RANGE_LABEL="initial..$VERSION"
fi

COMMITS="$(git log "$RANGE" --no-merges --format='- `%h` %s')"
if [[ -z "$COMMITS" ]]; then
  COMMITS="- 本次发行没有额外的非合并提交；说明由当前发行提交状态自动生成。"
fi

RELEASE_DATE="${RELEASE_DATE:-$(date +%F)}"
mkdir -p "$(dirname "$OUTPUT")"
cat > "$OUTPUT" <<EOF
# ${VERSION}

发布日期：${RELEASE_DATE}

## 提交变更总结

${COMMITS}

## 自签安装

- Release 附件为未签名 IPA，安装前需要自行签名。
- 可使用免费 Apple ID 和 Impactor 完成签名安装，无需付费开发者账号。
- 签名时请保留 Bundle ID \`com.paopaolabs.location-spoofer\`、App Group \`group.com.paopaolabs.location-spoofer\` 及原有 entitlements。
- 免费 Apple ID 签名通常只有 7 天有效期，到期后需要重新签名安装。

<!-- commit-range: ${RANGE_LABEL} -->
EOF

echo "Generated $OUTPUT from $RANGE"
