import SwiftUI
import UIKit
import PrivateSignerKit
import PrivateSignerSelfUpdate
import PrivateSignerUI

/// The fork's update screen.
///
/// The unsigned public channel is this app's own concern: users copy the IPA URL into whichever
/// third-party signing tool they already use. The private signed channel is not — it is the
/// package's `SelfUpdateView`, reached from here.
struct ForkUpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var candidate: ReleaseCandidate?
    @State private var checkedOnce = false
    @State private var errorMessage: String?
    @State private var isChecking = false
    @State private var didCopy = false
    @State private var hasPrivateConfiguration = false

    var body: some View {
        List {
            Section("版本") {
                valueRow("当前版本", value: PrivateSigning.currentVersionString)
                if let candidate {
                    valueRow("最新版本", value: candidate.version)
                    HStack {
                        Text("状态")
                        Spacer()
                        Text("发现新版本").foregroundStyle(.orange)
                    }
                } else if checkedOnce && !isChecking && errorMessage == nil {
                    HStack {
                        Text("状态")
                        Spacer()
                        Text("已是最新版").foregroundStyle(.secondary)
                    }
                }
            }

            if let candidate {
                Section("公开 unsigned IPA") {
                    Text(candidate.ipaURL.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = candidate.ipaURL.absoluteString
                        didCopy = true
                    } label: {
                        Label(didCopy ? "已复制 IPA 下载地址" : "复制 IPA 下载地址", systemImage: "doc.on.doc")
                    }

                    if let digest = candidate.expectedSHA256, !digest.isEmpty {
                        Text(digest)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            privateUpdateSection

            if let errorMessage {
                Section("公开更新检查结果") {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    if isChecking {
                        HStack { ProgressView(); Text("正在检查…") }
                    } else {
                        Label(checkedOnce ? "重新检查" : "检查更新", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isChecking)
            } footer: {
                Text("公开版本只检查 nnnmdzz/location-spoofer 的正式 GitHub Releases。私人 signed OTA 是独立增强通道；未配置或不可用时不会影响 unsigned IPA。")
            }
        }
        .navigationTitle("检查更新")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .task {
            loadPrivateConfiguration()
            await check()
        }
    }

    @ViewBuilder
    private var privateUpdateSection: some View {
        Section {
            NavigationLink {
                SelfUpdateView(
                    context: PrivateSigning.uiContext,
                    releaseSource: PrivateSigning.releaseSource,
                    currentVersion: PrivateSigning.currentVersionString,
                    installedBundleIdentifier: PrivateSigning.installedBundleIdentifier
                )
            } label: {
                Label(
                    hasPrivateConfiguration ? "私人签名更新" : "配置私人签名更新",
                    systemImage: hasPrivateConfiguration ? "lock.fill" : "lock.shield"
                )
            }

            if hasPrivateConfiguration {
                Button(role: .destructive) {
                    clearPrivateConfiguration()
                } label: {
                    Label("清除私人配置", systemImage: "trash")
                }
            }
        } header: {
            Text("私人签名更新")
        } footer: {
            Text("Worker 地址和 Signing Request Token 只保存在本机 Keychain，不写入源码、Info.plist 或 UserDefaults。签名、多开副本与 OTA 安装都在该页面内完成。")
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).font(.footnote.monospaced()).foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func check() async {
        guard !isChecking else { return }
        isChecking = true
        didCopy = false
        errorMessage = nil
        defer {
            isChecking = false
            checkedOnce = true
        }
        do {
            candidate = try await PrivateSigning.releaseSource.latestRelease(
                currentVersion: PrivateSigning.currentVersionString
            )
        } catch {
            candidate = nil
            errorMessage = error.localizedDescription
        }
    }

    private func loadPrivateConfiguration() {
        hasPrivateConfiguration = (try? PrivateSigning.store.load()) != nil
    }

    private func clearPrivateConfiguration() {
        do {
            try PrivateSigning.store.clear()
            hasPrivateConfiguration = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
