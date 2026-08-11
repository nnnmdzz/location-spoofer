import SwiftUI
import UIKit

struct ForkUpdateCheckView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var result: ForkReleaseCheckResult?
    @State private var errorMessage: String?
    @State private var isChecking = false
    @State private var didCopy = false

    @State private var privateConfiguration: PrivateUpdateConfiguration?
    @State private var privateStatus: PrivateSignedUpdateStatus?
    @State private var privateErrorMessage: String?
    @State private var isCheckingPrivate = false
    @State private var showingPrivateConfiguration = false

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
                Section("公开 unsigned IPA") {
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

            privateUpdateSection

            if let errorMessage {
                Section("公开更新检查结果") {
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
        .sheet(isPresented: $showingPrivateConfiguration) {
            NavigationView {
                PrivateUpdateConfigurationEditorView(initialConfiguration: privateConfiguration) { configuration in
                    privateConfiguration = configuration
                    privateStatus = nil
                    privateErrorMessage = nil
                    if let result {
                        Task { await checkPrivate(requestedVersion: result.latestVersion) }
                    }
                }
            }
        }
        .task {
            loadPrivateConfiguration()
            await check()
        }
    }

    @ViewBuilder
    private var privateUpdateSection: some View {
        Section("私人签名更新") {
            if privateConfiguration == nil {
                Text("未配置私人 OTA。Worker 地址和 Personal Update Token 都只保存在本机 Keychain，不写入源码、Info.plist 或 UserDefaults。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showingPrivateConfiguration = true
                } label: {
                    Label("配置私人签名更新", systemImage: "lock.shield")
                }
            } else {
                HStack {
                    Label("私人通道", systemImage: "lock.fill")
                    Spacer()
                    Text("已配置").foregroundStyle(.secondary)
                }

                if isCheckingPrivate {
                    HStack { ProgressView(); Text("正在检查 signed 版本…") }
                } else if let privateStatus {
                    if privateStatus.available {
                        HStack {
                            Text("signed 状态")
                            Spacer()
                            Text("可安装").foregroundStyle(.green)
                        }
                        valueRow("signed 版本", value: privateStatus.requestedVersion.description)
                        if let expiresAt = privateStatus.expiresAt, !expiresAt.isEmpty {
                            valueRow("临时链接有效期", value: expiresAt)
                        }
                        if let sha = privateStatus.ipaSHA256, !sha.isEmpty {
                            Text(sha)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        Button {
                            installPrivateUpdate()
                        } label: {
                            Label("直接安装已签名版本", systemImage: "square.and.arrow.down")
                        }
                        .disabled(privateStatus.manifestURL == nil)
                    } else {
                        HStack {
                            Text("signed 状态")
                            Spacer()
                            Text("准备中 / 暂不可用").foregroundStyle(.orange)
                        }
                        if let message = privateStatus.message, !message.isEmpty {
                            Text(message)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("尚未检查私人 signed 版本。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let privateErrorMessage {
                    Text(privateErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Button {
                    guard let result else { return }
                    Task { await checkPrivate(requestedVersion: result.latestVersion) }
                } label: {
                    Label("重新检查私人更新", systemImage: "arrow.clockwise")
                }
                .disabled(result == nil || isCheckingPrivate)

                Button {
                    showingPrivateConfiguration = true
                } label: {
                    Label("修改私人配置", systemImage: "key")
                }

                Button(role: .destructive) {
                    clearPrivateConfiguration()
                } label: {
                    Label("清除私人配置", systemImage: "trash")
                }
            }
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
        defer { isChecking = false }
        do {
            let fetched = try await ForkReleaseService.fetchLatest()
            result = fetched
            if privateConfiguration != nil {
                await checkPrivate(requestedVersion: fetched.latestVersion)
            }
        } catch {
            result = nil
            privateStatus = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func checkPrivate(requestedVersion: ForkReleaseVersion) async {
        guard !isCheckingPrivate, let configuration = privateConfiguration else { return }
        isCheckingPrivate = true
        privateStatus = nil
        privateErrorMessage = nil
        defer { isCheckingPrivate = false }
        do {
            privateStatus = try await PrivateSignedUpdateService.fetch(
                configuration: configuration,
                requestedVersion: requestedVersion
            )
        } catch {
            privateErrorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func installPrivateUpdate() {
        guard let manifestURL = privateStatus?.manifestURL,
              let installURL = PrivateSignedUpdateService.installationURL(manifestURL: manifestURL) else {
            privateErrorMessage = PrivateSignedUpdateServiceError.invalidManifestURL.localizedDescription
            return
        }
        UIApplication.shared.open(installURL, options: [:]) { opened in
            guard !opened else { return }
            Task { @MainActor in
                privateErrorMessage = "iOS 没有接受 OTA 安装请求；请确认 signed IPA、manifest 和 provisioning profile 当前有效。"
            }
        }
    }

    private func loadPrivateConfiguration() {
        do {
            privateConfiguration = try PrivateUpdateConfigurationStore.load()
        } catch {
            privateConfiguration = nil
            privateErrorMessage = error.localizedDescription
        }
    }

    private func clearPrivateConfiguration() {
        do {
            try PrivateUpdateConfigurationStore.clear()
            privateConfiguration = nil
            privateStatus = nil
            privateErrorMessage = nil
        } catch {
            privateErrorMessage = error.localizedDescription
        }
    }
}

private struct PrivateUpdateConfigurationEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var workerURLText: String
    @State private var tokenText: String
    @State private var errorMessage: String?
    let onSaved: (PrivateUpdateConfiguration) -> Void

    init(
        initialConfiguration: PrivateUpdateConfiguration?,
        onSaved: @escaping (PrivateUpdateConfiguration) -> Void
    ) {
        _workerURLText = State(initialValue: initialConfiguration?.workerURL.absoluteString ?? "")
        _tokenText = State(initialValue: initialConfiguration?.personalToken ?? "")
        self.onSaved = onSaved
    }

    var body: some View {
        Form {
            Section("私人 OTA 配置") {
                TextField("https://你的-worker.example", text: $workerURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                SecureField("Personal Update Token", text: $tokenText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }

            if let errorMessage {
                Section {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }

            Section {
                Text("两项配置都会作为一个 Keychain 项保存在当前设备，且使用 ThisDeviceOnly 可访问级别；公开源码和发行包中没有默认 Worker 地址或 Token。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("私人签名更新")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") { save() }
            }
        }
    }

    private func save() {
        do {
            try PrivateUpdateConfigurationStore.save(
                workerURL: workerURLText,
                personalToken: tokenText
            )
            guard let configuration = try PrivateUpdateConfigurationStore.load() else {
                throw PrivateUpdateConfigurationError.invalidStoredData
            }
            onSaved(configuration)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
