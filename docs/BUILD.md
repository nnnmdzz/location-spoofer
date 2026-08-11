# Build

## Requirements

- macOS with Xcode and Command Line Tools
- Go 1.23 or newer
- XcodeGen (`brew install xcodegen`)

## One-command build

```bash
./build.sh
```

该脚本会先检查 `xcrun`、`xcodebuild`、`xcodegen` 和 `go`，随后构建 iOS Go 静态库、重新生成 Xcode 工程、构建并输出未签名 IPA。

如需在未签名 IPA 已生成后额外运行 `PaopaoLocationSpoofer` 的 iOS Simulator 单元测试：

```bash
./build.sh --test
```

`--test` 默认自动选择当前环境中第一个可用的 iPhone Simulator。也可以传入指定的 destination：

```bash
SIMULATOR_DESTINATION='platform=iOS Simulator,name=<你的模拟器名称>' ./build.sh --test
```

Output:

```text
dist/PaopaoLocationSpoofer-unsigned.ipa
```

IPA 始终保持未签名。用 [Impactor](https://github.com/claration/Impactor) 签名安装即可。

## 发布验收

1. `./build.sh` 通过并输出未签名 IPA
2. 用 Impactor 签名后安装到设备
3. 真机安装后，先配置 WiFi HTTP 代理 `127.0.0.1:8888`，再按检测结果完成 CA 下载、安装和信任
4. 环境检测通过后，选点开启虚拟定位
5. 打开 Apple 地图验证定位是否变为虚拟位置
6. 若失败，查看诊断页的日志信息

## 发布版本

发布前先生成版本归档并提交：

```bash
./Scripts/generate-release-notes.sh v1.1.0
git add docs/releases/v1.1.0.md
git commit -m "docs: archive v1.1.0 release notes"
git tag v1.1.0
git push origin main v1.1.0
```

归档文件根据“上一个版本标签到当前提交”的 commit subject 生成。GitHub Actions 会校验归档存在，并将文件正文直接作为 GitHub Release 内容；不会发布文档链接或缺失说明的占位 Release。
