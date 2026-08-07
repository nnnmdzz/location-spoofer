import SwiftUI

struct SettingsView: View {
    @ObservedObject var setup: SetupCoordinator
    @ObservedObject var actions: LocationActionCoordinator
    @ObservedObject private var proxy = ProxyManager.shared
    @ObservedObject private var runtimeMode = ProxyRuntimeModeStore.shared
    @ObservedObject private var thirdPartyProxy = ThirdPartyProxyManager.shared
    @ObservedObject private var thirdPartyClient = ThirdPartyProxyClientStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var activeTip: TipKind?
    @State private var proxyOperationError = ""
    @State private var proxyOperationAlertTitle = "代理操作失败"
    @State private var modeOperationRunning = false
    @State private var copiedClient: ThirdPartyProxyClient?

    var body: some View {
        Form {
            Section("运行模式") {
                Picker("模式", selection: runtimeModeBinding) {
                    ForEach(ProxyRuntimeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.inline)
                .disabled(modeOperationRunning || actions.state.isBusy || thirdPartyProxy.isRequesting)

                if runtimeMode.mode == .thirdParty {
                    Label("测试模式：仅 Shadowrocket 当前可测试", systemImage: "testtube.2")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section("状态") {
                if runtimeMode.mode == .localWiFi {
                    HStack {
                        Label("本机代理", systemImage: proxy.isRunning ? "play.circle.fill" : "stop.circle")
                        Spacer()
                        Toggle("", isOn: proxyBinding).labelsHidden()
                            .tint(.blue)
                            .disabled(actions.state.isBusy)
                    }
                } else {
                    HStack {
                        Label("第三方模块", systemImage: thirdPartyStatusIcon)
                        Spacer()
                        Text(thirdPartyStatusText).foregroundStyle(.secondary)
                    }
                    Button {
                        detectThirdPartyConnection()
                    } label: {
                        if thirdPartyProxy.isRequesting {
                            HStack { ProgressView(); Text("正在检测…") }
                        } else {
                            Label("检测连接", systemImage: "network")
                        }
                    }
                    .disabled(thirdPartyProxy.isRequesting)
                }
                HStack {
                    Label("虚拟定位", systemImage: virtualLocationIsActive ? "location.fill" : "location.slash")
                    Spacer()
                    Text(virtualLocationStatusText).foregroundStyle(.secondary)
                }
            }

            WlocAccuracySettingsSection()

            if runtimeMode.mode == .thirdParty {
                thirdPartyConfigurationSection
            } else {
                Section("说明") {
                Button {
                    activeTip = .activation
                } label: {
                    Label("生效说明", systemImage: "checklist")
                }
                Button {
                    activeTip = .deactivation
                } label: {
                    Label("失效说明", systemImage: "arrow.uturn.backward.circle")
                }
                Button {
                    activeTip = .removeProxy
                } label: {
                    Label("关闭 WiFi 代理", systemImage: "wifi.slash")
                }
                }
            }

            Section("工作原理") {
                Text(workflowDescription)
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("应用") {
                if runtimeMode.mode == .localWiFi {
                    Button {
                        setup.requestSetup()
                    } label: {
                        Label("进入引导页", systemImage: "arrow.clockwise.circle")
                    }
                }
                valueRow("版本", value: versionText)
            }

            Section("支持") {
                NavigationLink {
                    BugReportView(setup: setup)
                } label: {
                    Label("报告 Issue", systemImage: "ladybug")
                }
            }

            Section("关于") {
                Button {
                    if let url = URL(string: "https://github.com/xweiba/location-spoofer") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("xweiba/location-spoofer", systemImage: "link")
                }
                Text("如果觉得好用，欢迎去 GitHub 给项目点个 Star")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Section("致谢") {
                Button {
                    if let url = URL(string: "https://github.com/Yu9191/wloc") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("核心定位改写逻辑移植自 Yu9191/wloc", systemImage: "heart.fill")
                        .foregroundStyle(.pink)
                }
            }
        }
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("完成") { dismiss() } }
        }
        .sheet(item: $activeTip) { kind in
            TipSheetView(kind: kind)
        }
        .alert(proxyOperationAlertTitle, isPresented: Binding(
            get: { !proxyOperationError.isEmpty },
            set: { if !$0 { proxyOperationError = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(proxyOperationError)
        }
    }

    private func valueRow(_ title: String, value: String) -> some View {
        HStack { Text(title); Spacer(); Text(value).font(.footnote.monospaced()).foregroundStyle(.secondary) }
    }

    private var versionText: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    private var proxyBinding: Binding<Bool> {
        Binding(get: { proxy.isRunning }, set: { on in
            Task {
                if on {
                    do {
                        try await proxy.start()
                    } catch {
                        proxy.error = error.localizedDescription
                        proxyOperationAlertTitle = "代理操作失败"
                        proxyOperationError = error.localizedDescription
                    }
                } else {
                    if actions.virtualLocationEnabled {
                        actions.clear()
                        RuntimeLogger.info("APP", "Settings", "关闭代理前已同步关闭虚拟定位")
                    }
                    proxy.stop()
                }
            }
        })
    }

    private var runtimeModeBinding: Binding<ProxyRuntimeMode> {
        Binding(
            get: { runtimeMode.mode },
            set: { newMode in switchRuntimeMode(to: newMode) }
        )
    }

    @ViewBuilder
    private var thirdPartyConfigurationSection: some View {
        Section("第三方代理配置") {
            Picker("客户端", selection: Binding(
                get: { thirdPartyClient.selectedClient },
                set: { thirdPartyClient.select($0) }
            )) {
                ForEach(ThirdPartyProxyClient.allCases) { client in
                    Text(client.name).tag(client)
                }
            }

            HStack {
                Text("验证状态")
                Spacer()
                Text(thirdPartyClient.selectedClient.verificationText)
                    .font(.footnote)
                    .foregroundStyle(thirdPartyClient.selectedClient == .shadowrocket ? .green : .orange)
            }

            Button {
                UIPasteboard.general.string = thirdPartyClient.selectedClient.subscriptionURL.absoluteString
                copiedClient = thirdPartyClient.selectedClient
            } label: {
                Label(copiedClient == thirdPartyClient.selectedClient ? "已复制订阅链接" : "复制订阅链接", systemImage: "doc.on.doc")
            }

            Button {
                openThirdPartyClient(thirdPartyClient.selectedClient)
            } label: {
                Label("打开 \(thirdPartyClient.selectedClient.name)", systemImage: "arrow.up.forward.app")
            }

            Button {
                setup.requestThirdPartySetup()
                dismiss()
            } label: {
                Label("重新打开配置引导", systemImage: "arrow.clockwise.circle")
            }

            if thirdPartyClient.selectedClient == .egern {
                Text("Egern 直接使用 Surge 的 .sgmodule 模块。")
                    .font(.footnote).foregroundStyle(.secondary)
            } else if thirdPartyClient.selectedClient == .stash {
                Text("Stash 直接订阅 .stoverride，不要通过 Script Hub 转换。")
                    .font(.footnote).foregroundStyle(.secondary)
            }

            Text("复制链接后，在对应代理客户端中添加模块/重写订阅，并启用 MITM。第三方客户端保存坐标后，即使关闭本 App，坐标仍由代理客户端持久化并继续生效。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private var thirdPartyStatusIcon: String {
        switch thirdPartyProxy.connectionState {
        case .unknown: return "questionmark.circle"
        case .connected: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    private var thirdPartyStatusText: String {
        switch thirdPartyProxy.connectionState {
        case .unknown: return "未检测"
        case .connected(let active): return active ? "已连接，有坐标" : "已连接，无坐标"
        case .failed: return "连接失败"
        }
    }

    private var virtualLocationStatusText: String {
        if runtimeMode.mode == .localWiFi {
            return actions.virtualLocationEnabled ? "已开启" : "已关闭"
        }
        if case .connected(let active) = thirdPartyProxy.connectionState {
            return active ? "第三方已保存" : "未保存"
        }
        return "未知"
    }

    private var workflowDescription: String {
        if runtimeMode.mode == .thirdParty {
            return "App 只负责地图选点、收藏和发送 WGS-84 坐标。第三方代理客户端通过模块拦截 Apple WLOC 请求并持久化当前坐标；本模式不启动本机代理，不使用 App 的 CA，也不需要配置 127.0.0.1:8888。"
        }
        return """
        App 在设备本地运行一个代理服务器（127.0.0.1:8888）。

        通过 WiFi 手动代理配置，让系统的定位请求（gs-loc.apple.com/clls/wloc）经过这个本地代理。代理使用已安装的 CA 证书对 HTTPS 流量做中间人解密，把 Apple 返回的定位坐标改写为你设置的虚拟坐标，再加密返回给系统，从而实现虚拟定位。
        """
    }

    private func switchRuntimeMode(to newMode: ProxyRuntimeMode) {
        guard newMode != runtimeMode.mode, !modeOperationRunning else { return }
        modeOperationRunning = true
        Task { @MainActor in
            defer { modeOperationRunning = false }
            switch newMode {
            case .thirdParty:
                if actions.virtualLocationEnabled { actions.clear() }
                proxy.stop()
                setup.completeSetup()
                runtimeMode.setMode(.thirdParty)
                setup.requestThirdPartySetup()
                proxyOperationAlertTitle = "模式已切换"
                proxyOperationError = "已切换到第三方代理模式。请关闭 Wi-Fi 中的 127.0.0.1:8888 手动代理，并按引导导入第三方配置。"
            case .localWiFi:
                do {
                    try await thirdPartyProxy.clear()
                } catch {
                    RuntimeLogger.warning("APP", "Mode", "切换 APP 模式前无法清除第三方坐标", details: [
                        "错误": error.localizedDescription
                    ])
                }
                runtimeMode.setMode(.localWiFi)
                await setup.prepareLocalServices()
                setup.requestSetup()
                proxyOperationAlertTitle = "模式已切换"
                proxyOperationError = "已切换到 APP 模式。请停用第三方 WLOC 模块或代理连接，避免双重拦截。"
            }
        }
    }

    private func detectThirdPartyConnection() {
        Task { @MainActor in
            do {
                let response = try await thirdPartyProxy.query()
                if !response.success, response.error?.contains("无已保存") != true {
                    proxyOperationAlertTitle = "检测失败"
                    proxyOperationError = response.error ?? "第三方代理模块返回失败"
                }
            } catch {
                proxyOperationAlertTitle = "检测失败"
                proxyOperationError = error.localizedDescription
            }
        }
    }

    private func openThirdPartyClient(_ client: ThirdPartyProxyClient) {
        guard let url = client.launchURL else { return }
        UIApplication.shared.open(url, options: [:]) { opened in
            guard !opened else { return }
            Task { @MainActor in
                proxyOperationAlertTitle = "无法打开客户端"
                proxyOperationError = "无法打开 \(client.name)，请确认客户端已安装后手动打开。"
            }
        }
    }

    private var virtualLocationIsActive: Bool {
        if runtimeMode.mode == .localWiFi {
            return actions.virtualLocationEnabled
        }
        if case .connected(let active) = thirdPartyProxy.connectionState {
            return active
        }
        return false
    }
}
