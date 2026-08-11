import SwiftUI
import UIKit

struct ForkUpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result: ForkReleaseCheckResult?
    @State private var errorMessage: String?
    @State private var isChecking = false
    @State private var didCopy = false

    var body: some View {
        List {
            Section("版本") {
                valueRow("当前版本", value: result?.currentVersion.description ?? ForkReleaseService.currentVersionString)
                if let result {
                    valueRow("最新版本", value: result.latestVersion.description)
                    HStack {
                        Text("状态")
                        Spacer()
                        Text(result.updateAvailable ? "发现新版本" : "已是最新版")
                            .foregroundStyle(result.updateAvailable ? .orange : .secondary)
                    }
                }
            }

            if let result {
                Section("IPA 下载地址") {
                    Text(result.ipaURL.absoluteString)
                        .font(.footnote.monospaced())
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = result.ipaURL.absoluteString
                        didCopy = true
                    } label: {
                        Label(didCopy ? "已复制 IPA 下载地址" : "复制 IPA 下载地址", systemImage: "doc.on.doc")
                    }

                    if let digest = result.digest, !digest.isEmpty {
                        Text(digest)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }

            if let errorMessage {
                Section("检查结果") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await check() }
                } label: {
                    if isChecking {
                        HStack { ProgressView(); Text("正在检查…") }
                    } else {
                        Label(result == nil ? "检查更新" : "重新检查", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                .disabled(isChecking)
            } footer: {
                Text("仅手动检查 nnnmdzz/location-spoofer 的正式 GitHub Releases；不会自动检查，也不会使用上游仓库作为发行源。")
            }
        }
        .navigationTitle("检查更新")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("完成") { dismiss() }
            }
        }
        .task { await check() }
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
        defer { isChecking = false }
        do {
            result = try await ForkReleaseService.fetchLatest()
        } catch {
            result = nil
            errorMessage = error.localizedDescription
        }
    }
}