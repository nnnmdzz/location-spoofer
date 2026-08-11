#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ZH="$ROOT/README.md"
EN="$ROOT/README.en.md"
fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q 'iOS Location Service Research & Testing Framework' "$ZH" || fail "Chinese README positioning is missing"
grep -q 'iOS Location Service Research & Testing Framework' "$EN" || fail "English README positioning is missing"

grep -q '#### 自签安装说明' "$ZH" || fail "Chinese self-signing instructions are missing"
grep -q '#### Self-Signing Instructions' "$EN" || fail "English self-signing instructions are missing"
grep -q 'Impactor Releases' "$ZH" || fail "Chinese README must link the requested Impactor releases"
grep -q 'Impactor Releases' "$EN" || fail "English README must link the requested Impactor releases"
grep -q '开发者模式' "$ZH" || fail "Chinese README must explain iOS 16 Developer Mode"
grep -q 'Developer Mode' "$EN" || fail "English README must explain iOS 16 Developer Mode"
grep -q '7 天有效期' "$ZH" || fail "Chinese README must disclose free-signing expiry"
grep -q 'seven days' "$EN" || fail "English README must disclose free-signing expiry"

grep -q '^## 功能预览$' "$ZH" || fail "Chinese feature preview is missing"
grep -q '^## Feature Preview$' "$EN" || fail "English feature preview is missing"

images=(
  '主界面.jpg'
  'Apple%20Map.jpg'
  '高德地图.jpg'
  '微信.jpg'
  '钉钉.jpg'
  '高血压.jpg'
)
for image in "${images[@]}"; do
  grep -q "images/$image" "$ZH" || fail "Chinese README is missing image: $image"
  grep -q "images/$image" "$EN" || fail "English README is missing image: $image"
done

image_files=(
  '主界面.jpg'
  'Apple Map.jpg'
  '高德地图.jpg'
  '微信.jpg'
  '钉钉.jpg'
  '高血压.jpg'
)
for image in "${image_files[@]}"; do
  test -f "$ROOT/images/$image" || fail "referenced preview image is missing: $image"
done

test "$(grep -c '^## ' "$ZH")" -eq "$(grep -c '^## ' "$EN")" \
  || fail "Chinese and English README section counts must stay aligned"

! grep -Eq '^## (许可证|License)$' "$ZH" "$EN" || fail "README must not claim a repository license"
grep -q '当前项目不支持在 Windows 上直接构建 iOS 应用' "$ZH" || fail "Chinese README must reject Windows source builds"
grep -q 'Building the iOS app directly on Windows is not supported' "$EN" || fail "English README must reject Windows source builds"
grep -q 'docs/COMMUNITY_TUTORIALS.md' "$ZH" || fail "Chinese README must link the community tutorial submission guide"
grep -q '^#### 配置接口与客户端适配$' "$ZH" \
  || fail "Chinese README must document the third-party integration contract"
grep -q '^#### Configuration API and Client Integration$' "$EN" \
  || fail "English README must document the third-party integration contract"
for contract in 'action=query' 'action=clear' 'lon=<WGS-84'; do
  grep -q "$contract" "$ZH" || fail "Chinese README is missing third-party contract: $contract"
  grep -q "$contract" "$EN" || fail "English README is missing third-party contract: $contract"
done
grep -q '除敏感信息遮挡外，不要自行添加箭头、编号、边框、说明文字或其他标注' \
  "$ROOT/docs/COMMUNITY_TUTORIALS.md" \
  || fail "tutorial submissions must keep source screenshots free of non-privacy annotations"
grep -q '同一张截图可以对应多个步骤' "$ROOT/docs/COMMUNITY_TUTORIALS.md" \
  || fail "tutorial submissions must explain multi-step screenshot handling"
grep -q '不得覆盖上述原图' "$ROOT/docs/COMMUNITY_TUTORIALS.md" \
  || fail "annotated app assets must not replace categorized source screenshots"

if grep -Rnw --include='*.md' --include='*.sh' \
  "$ROOT/build.sh" "$ROOT/README.md" "$ROOT/README.en.md" "$ROOT/docs" "$ROOT/Scripts" \
  -e 'Impact'; then
  fail "documentation and build output must use the correct Impactor name"
fi

echo "PASS: README contract"
