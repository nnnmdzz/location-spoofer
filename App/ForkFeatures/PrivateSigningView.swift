import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct PrivateSigningView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var configuration: PrivateUpdateConfiguration?
    @State private var showingConfiguration = false
    @State private var sourceKind = SourceKind.url
    @State private var sourceURLText = ""
    @State private var selectedFileURL: URL?
    @State private var showingFileImporter = false
    @State private var showingAdvanced = false
    @State private var signingMode = PrivateSigningMode.split
    @State private var targetBundleID = ""
    @State private var profileID = ""
    @State private var keychainGroups = ""
    @State private var requireAllBundles = false
    @State private var requireAllEntitlements = false
    @State private var jobs: [PrivateSigningJob] = []
    @State private var linksByJob: [String: PrivateSigningLinks] = [:]
    @State private var isSubmitting = false
    @State private var isRefreshing = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            configurationSection
            sourceSection
            optionsSection
            submitSection
            historySection
        }
        .navigationTitle("私人 IPA 签名")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingConfiguration) {
            NavigationView {
                PrivateUpdateConfigurationEditorView(initialConfiguration: configuration) { saved in
                    configuration = saved
                    Task { await refreshHistory() }
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [UTType(filenameExtension: "ipa") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                selectedFileURL = urls.first
                errorMessage = nil
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .task {
            loadConfiguration()
            await refreshHistory()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if scenePhase == .active && jobs.contains(where: \.isActive) {
                    await pollActiveJobs()
                }
            }
        }
    }

    @ViewBuilder
    private var configurationSection: some View {
        Section("签名服务") {
            if let configuration {
                HStack {
                    Label("Worker", systemImage: "lock.shield.fill")
                    Spacer()
                    Text(configuration.workerURL.host ?? "已配置")
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
                Button("修改 Worker 与 Token") { showingConfiguration = true }
            } else {
                Text("先配置 Cloudflare Worker 地址和 Signing Request Token。配置仅保存在本机 Keychain。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("配置签名服务") { showingConfiguration = true }
            }
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        Section("来源 IPA") {
            Picker("来源", selection: $sourceKind) {
                ForEach(SourceKind.allCases) { kind in Text(kind.title).tag(kind) }
            }
            .pickerStyle(.segmented)

            if sourceKind == .url {
                TextField("https://example.com/App.ipa", text: $sourceURLText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
            } else {
                Button {
                    showingFileImporter = true
                } label: {
                    Label(selectedFileURL?.lastPathComponent ?? "选择 IPA 文件", systemImage: "doc.badge.plus")
                }
                Text("支持分片上传，当前上限 100 MB。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section {
            Picker("签名模式", selection: $signingMode) {
                Text("Split（默认）").tag(PrivateSigningMode.split)
                Text("Standard").tag(PrivateSigningMode.standard)
            }
            Button(showingAdvanced ? "收起高级选项" : "显示高级选项") {
                showingAdvanced.toggle()
            }
            if showingAdvanced {
                TextField("目标 Bundle ID（可留空）", text: $targetBundleID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                TextField("Profile ID（默认 personal-main）", text: $profileID)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Keychain 访问组（每行一个）").font(.caption).foregroundStyle(.secondary)
                    TextEditor(text: $keychainGroups)
                        .frame(minHeight: 72)
                        .font(.footnote.monospaced())
                }
                Toggle("嵌套 App/扩展必须全部保留", isOn: $requireAllBundles)
                Toggle("原权限必须全部保留", isOn: $requireAllEntitlements)
            }
        } header: {
            Text("签名选项")
        } footer: {
            Text("默认会移除 profile 不支持的嵌套包和权限，并在签名报告中列出；不会自动切换签名模式。")
        }
    }

    @ViewBuilder
    private var submitSection: some View {
        Section {
            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    HStack { ProgressView(); Text("正在提交…") }
                } else {
                    Label("提交签名任务", systemImage: "signature")
                }
            }
            .disabled(configuration == nil || isSubmitting || !sourceReady)

            if let errorMessage {
                Text(errorMessage).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var historySection: some View {
        Section {
            if jobs.isEmpty {
                Text("暂无签名任务。")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(jobs) { job in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(job.actualTitle ?? job.source ?? "IPA")
                                .font(.headline)
                                .lineLimit(1)
                            Spacer()
                            statusLabel(job.status)
                        }
                        Text(job.jobID).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        if let bundle = job.actualBundleIdentifier {
                            Text(bundle).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                        if let message = job.message, !message.isEmpty {
                            Text(message).font(.caption).foregroundStyle(job.status.isFailure ? .red : .secondary)
                        }
                        HStack {
                            if job.status == .completed {
                                Button("获取安装/导出链接") { Task { await loadLinks(for: job) } }
                            } else if job.status.isFailure {
                                Button("重试") { Task { await retry(job) } }
                            } else if job.isActive {
                                Button("取消", role: .destructive) { Task { await cancel(job) } }
                            }
                        }
                        if let links = linksByJob[job.jobID] {
                            Button("安装") { UIApplication.shared.open(links.installURL) }
                            Button("导出 IPA") { UIApplication.shared.open(links.exportURL) }
                            Text("链接有效至 \(links.expiresAt)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            HStack {
                Text("最近任务")
                Spacer()
                if isRefreshing { ProgressView() }
                Button("刷新") { Task { await refreshHistory() } }.disabled(isRefreshing)
            }
        } footer: {
            Text("App 在前台且存在进行中的任务时每 5 秒刷新。任务历史保留 30 天，签名 IPA 保留 7 天。")
        }
    }

    private var sourceReady: Bool {
        switch sourceKind {
        case .url: return URL(string: sourceURLText)?.scheme?.lowercased() == "https"
        case .file: return selectedFileURL != nil
        }
    }

    private var options: PrivateSigningOptions {
        PrivateSigningOptions(
            signingMode: signingMode,
            targetBundleIdentifier: nilIfEmpty(targetBundleID),
            profileID: nilIfEmpty(profileID),
            keychainAccessGroups: keychainGroups
                .split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            embeddedBundlePolicy: requireAllBundles ? .requireAll : .stripUnsupported,
            entitlementPolicy: requireAllEntitlements ? .requireAll : .stripUnsupported
        )
    }

    @MainActor
    private func submit() async {
        guard let configuration else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let client = PrivateSigningClient(configuration: configuration)
            let job: PrivateSigningJob
            switch sourceKind {
            case .url:
                guard let url = URL(string: sourceURLText), url.scheme?.lowercased() == "https" else {
                    throw PrivateSigningClientError.invalidURL
                }
                job = try await client.createURLJob(sourceURL: url, options: options)
            case .file:
                guard let fileURL = selectedFileURL else { throw PrivateSigningClientError.invalidURL }
                let accessed = fileURL.startAccessingSecurityScopedResource()
                defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
                job = try await client.uploadAndCreateJob(fileURL: fileURL, options: options)
            }
            jobs.removeAll { $0.jobID == job.jobID }
            jobs.insert(job, at: 0)
            await refreshHistory()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshHistory() async {
        guard !isRefreshing, let configuration else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            jobs = try await PrivateSigningClient(configuration: configuration).history()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func pollActiveJobs() async {
        guard let configuration else { return }
        let client = PrivateSigningClient(configuration: configuration)
        for index in jobs.indices where jobs[index].isActive {
            do {
                jobs[index] = try await client.job(id: jobs[index].jobID)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func retry(_ job: PrivateSigningJob) async {
        guard let configuration else { return }
        do {
            _ = try await PrivateSigningClient(configuration: configuration).retry(jobID: job.jobID)
            await refreshHistory()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func cancel(_ job: PrivateSigningJob) async {
        guard let configuration else { return }
        do {
            _ = try await PrivateSigningClient(configuration: configuration).cancel(jobID: job.jobID)
            await refreshHistory()
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func loadLinks(for job: PrivateSigningJob) async {
        guard let configuration else { return }
        do {
            linksByJob[job.jobID] = try await PrivateSigningClient(configuration: configuration).links(jobID: job.jobID)
        } catch { errorMessage = error.localizedDescription }
    }

    private func loadConfiguration() {
        do { configuration = try PrivateUpdateConfigurationStore.load() }
        catch { errorMessage = error.localizedDescription }
    }

    @ViewBuilder
    private func statusLabel(_ status: PrivateSigningJobStatus) -> some View {
        let display: (String, Color) = switch status {
        case .completed: ("完成", .green)
        case .failed, .dispatchFailed: ("失败", .red)
        case .cancelled: ("已取消", .secondary)
        case .signing: ("签名中", .orange)
        case .following: ("复用中", .orange)
        case .dispatching, .queued: ("排队中", .orange)
        case .unknown(let value): ("未知：\(value)", .secondary)
        }
        Text(display.0).font(.caption).foregroundStyle(display.1)
    }

    private func nilIfEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum SourceKind: String, CaseIterable, Identifiable {
    case url
    case file

    var id: String { rawValue }
    var title: String { self == .url ? "下载链接" : "本地文件" }
}
