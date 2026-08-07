import SwiftUI

enum TipKind: String, Identifiable {
    case activation = "生效说明"
    case deactivation = "失效说明"
    case removeProxy = "关闭 WiFi 代理"
    case proxySetup = "配置代理"
    case rewriteFailed = "改写失败"
    var id: String { rawValue }
}

struct TipSheetView: View {
    let kind: TipKind
    var runtimeMode: ProxyRuntimeMode = .localWiFi
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch kind {
                    case .activation: ActivationTipContent(runtimeMode: runtimeMode, dismiss: { dismiss() })
                    case .deactivation: DeactivationTipContent(runtimeMode: runtimeMode, dismiss: { dismiss() })
                    case .removeProxy: RemoveProxyTipContent(dismiss: { dismiss() })
                    case .proxySetup: ProxySetupTipContent(dismiss: { dismiss() })
                    case .rewriteFailed: RewriteFailedTipContent(dismiss: { dismiss() })
                    }
                }.padding(16)
            }
            .navigationTitle(kind.rawValue).navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button { dismiss() } label: {
                    Text("知道了").font(.body.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).tint(.blue).padding(.horizontal, 16).padding(.bottom, 8)
            }
        }
    }
}

@MainActor
private func openSettings(_ destination: SystemSettingsDestination) {
    guard let appSettingsURL = URL(string: UIApplication.openSettingsURLString) else { return }
    // Try the preferred (private) URL scheme first; fall back to reliable app-settings:
    if let preferredURL = destination.preferredURL, preferredURL != appSettingsURL {
        UIApplication.shared.open(preferredURL) { opened in
            if !opened {
                UIApplication.shared.open(appSettingsURL)
            }
        }
    } else {
        UIApplication.shared.open(appSettingsURL)
    }
}

// MARK: - 共享组件

private struct TipCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text("知道了").font(.body.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
        }.buttonStyle(.borderedProminent).tint(.blue)
    }
}

// MARK: - 生效说明

struct ActivationTipContent: View {
    var runtimeMode: ProxyRuntimeMode = .localWiFi
    let dismiss: () -> Void
    @ObservedObject private var effectMonitor = LocationEffectMonitor.shared

    var body: some View {
        effectStatusBox

        GroupBox(label: Label("自动刷新仍未生效时", systemImage: "checklist")) {
            VStack(alignment: .leading, spacing: 10) {
                if runtimeMode == .thirdParty {
                    step(0, "确认第三方代理已开启", "保持已导入的 WLOC 模块、HTTPS 解密和第三方代理/VPN 连接开启。")
                }
                step(1, "开启飞行模式", "从控制中心打开飞行模式（点飞机图标），Wi‑Fi 会自动断开。这是为了清除 iOS 的定位缓存。等待 2 秒。")
                step(2, "关闭 Wi‑Fi", "从控制中心再点一下 Wi‑Fi 图标，确认 Wi‑Fi 已关闭。等待 2 秒。")
                systemStep(3, "关闭系统定位服务", "打开系统「设置 → 隐私与安全性 → 定位服务」，关闭顶部的总开关。等待 2 秒。")
                step(4, "打开 Wi‑Fi，启动虚拟定位", runtimeMode == .thirdParty ? "从控制中心打开 Wi‑Fi（飞行模式保持开启），确认第三方代理已连接。坐标已经同步到第三方代理。等待 2 秒。" : "从控制中心打开 Wi‑Fi（飞行模式保持开启），进入 App 点底部「开始虚拟定位」。等待 2 秒。")
                step(5, "关闭飞行模式", "从控制中心关闭飞行模式。等待 2 秒。")
                systemStep(6, "重新开启定位服务", "再次进入「设置 → 隐私与安全性 → 定位服务」，打开总开关。返回 App 后会自动重新检测。")
            }.padding(.vertical, 4)
        }

        GroupBox(label: Label("如果还是不行", systemImage: "exclamationmark.triangle")) {
            Text("操作到第 3 步时关机重启，开机后从第 4 步继续。这样能彻底清除系统缓存的定位数据。")
                .font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
        }

    }

    private var effectStatusBox: some View {
        GroupBox(label: Label("自动刷新与生效检测", systemImage: "location.magnifyingglass")) {
            VStack(alignment: .leading, spacing: 10) {
                switch effectMonitor.status {
                case .idle:
                    Label("等待定位目标", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                    Text("坐标写入成功后，App 会自动绕过近期定位缓存，请求新的百米级 Core Location 样本并验证是否接近目标。")
                        .font(.caption2).foregroundStyle(.secondary)
                case .refreshing(let attempt):
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("正在软刷新定位（\(attempt)/3）")
                            .font(.caption.weight(.semibold))
                    }
                    Text("这里只调整本 App 的定位请求精度，不会关闭系统定位服务，也不会禁用 GPS。")
                        .font(.caption2).foregroundStyle(.secondary)
                case .effective(let distance, let accuracy):
                    Label("定位已生效", systemImage: "checkmark.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.green)
                    measurementText(distance: distance, accuracy: accuracy)
                case .cachePending(let distance, let accuracy):
                    Label("系统仍可能使用旧定位缓存", systemImage: "clock.arrow.circlepath")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    measurementText(distance: distance, accuracy: accuracy)
                    Text("WLOC 目标已经写入，但新样本仍明显偏离目标。可先重新检测；仍无变化时再手动关闭/开启系统定位服务。")
                        .font(.caption2).foregroundStyle(.secondary)
                    diagnosticActions
                case .gpsLikelyDominant(let distance, let accuracy):
                    Label("疑似高精度真实定位占优", systemImage: "location.north.circle.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    measurementText(distance: distance, accuracy: accuracy)
                    Text("检测到远离目标的高精度样本，室外强 GPS/GNSS 或旧高精度定位可能仍在 Core Location 融合中占优。WLOC 只能修改 Wi‑Fi/基站网络定位；此判断为启发式。")
                        .font(.caption2).foregroundStyle(.secondary)
                    diagnosticActions
                case .unavailable:
                    Label("暂时没有拿到新的定位样本", systemImage: "questionmark.circle")
                        .font(.caption.weight(.semibold)).foregroundStyle(.orange)
                    Text("可能是定位授权、系统缓存或已有定位请求占用。可以重新检测，必要时进入定位服务设置刷新。")
                        .font(.caption2).foregroundStyle(.secondary)
                    diagnosticActions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var diagnosticActions: some View {
        HStack(spacing: 8) {
            Button { effectMonitor.retry() } label: {
                Label("重新检测", systemImage: "arrow.clockwise").font(.caption)
            }
            .buttonStyle(.bordered)

            Button { openSettings(.locationServices) } label: {
                Label("刷新定位服务", systemImage: "arrow.up.right.square").font(.caption)
            }
            .buttonStyle(.bordered)
            .tint(.blue)
        }
    }

    private func measurementText(distance: Double, accuracy: Double) -> some View {
        Text(String(format: "距目标约 %.0f m · 样本精度约 %.0f m", distance, accuracy))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption2.bold())
                .frame(width: 20, height: 20)
                .background(Color.blue.opacity(0.15), in: Circle()).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func systemStep(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption2.bold())
                .frame(width: 20, height: 20)
                .background(Color.orange.opacity(0.18), in: Circle()).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { openSettings(.locationServices) } label: {
                    Label("去设置", systemImage: "arrow.up.right.square").font(.caption)
                }.buttonStyle(.bordered).tint(.blue)
            }
        }
    }
}

// MARK: - 失效说明

struct DeactivationTipContent: View {
    var runtimeMode: ProxyRuntimeMode = .localWiFi
    let dismiss: () -> Void

    var body: some View {
        GroupBox(label: Label("取消虚拟定位", systemImage: "arrow.uturn.backward.circle")) {
            VStack(alignment: .leading, spacing: 10) {
                step(1, "开启飞行模式", "从控制中心打开飞行模式，Wi‑Fi 会自动断开。等待 2 秒。")
                step(2, "关闭 Wi‑Fi", "从控制中心确认 Wi‑Fi 已关闭。等待 2 秒。")
                systemStep(3, "关闭系统定位服务", "打开「设置 → 隐私与安全性 → 定位服务」，关闭总开关。等待 2 秒。")
                if runtimeMode == .thirdParty {
                    step(4, "确认坐标已清除", "App 已通知第三方代理清除虚拟坐标。保持网络可用并等待 2 秒，让系统重新获取真实定位。")
                } else {
                    systemStep(4, "打开 Wi‑Fi，移除代理", "从控制中心打开 Wi‑Fi。然后进入「设置 → 无线局域网 → 点 WiFi 右侧 (i) → HTTP 代理」，选择「关闭」后存储。等待 2 秒。")
                }
                step(5, "关闭飞行模式", "从控制中心关闭飞行模式。等待 2 秒。")
                systemStep(6, "重新开启定位服务", "再次进入「设置 → 隐私与安全性 → 定位服务」打开总开关。打开地图验证定位是否恢复。")
            }.padding(.vertical, 4)
        }

        GroupBox(label: Label("如果还是不行", systemImage: "exclamationmark.triangle")) {
            Text("操作到第 3 步时关机重启，开机后从第 4 步继续。").font(.caption).foregroundStyle(.secondary).padding(.vertical, 4)
        }

    }

    private func step(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption2.bold())
                .frame(width: 20, height: 20)
                .background(Color.blue.opacity(0.15), in: Circle()).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func systemStep(_ n: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(n)").font(.caption2.bold())
                .frame(width: 20, height: 20)
                .background(Color.orange.opacity(0.18), in: Circle()).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption.weight(.semibold))
                Text(detail).font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button { openSettings(.locationServices) } label: {
                    Label("去设置", systemImage: "arrow.up.right.square").font(.caption)
                }.buttonStyle(.bordered).tint(.blue)
            }
        }
    }
}

// MARK: - 移除 WiFi 代理

struct RemoveProxyTipContent: View {
    let dismiss: () -> Void

    var body: some View {
        GroupBox(label: Label("移除代理配置", systemImage: "wifi.slash")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("停止虚拟定位后，需要手动移除 WiFi 代理配置，否则可能无法上网。\n\n1. 打开「设置 → 无线局域网」\n2. 点击当前 WiFi 右侧 (i) 图标\n3. 找到「HTTP 代理」\n4. 选择「关闭」\n5. 点右上角「存储」")
                    .font(.caption).foregroundStyle(.primary)
                Button { openSettings(.wifi) } label: {
                    Label("去设置", systemImage: "arrow.up.right.square").font(.caption)
                }.buttonStyle(.bordered).tint(.blue)
            }.padding(.vertical, 4)
        }
    }
}

// MARK: - WiFi 代理配置

struct ProxySetupTipContent: View {
    @State private var copied = false
    let dismiss: () -> Void

    var body: some View {
        GroupBox(label: Label("WiFi 代理未配置", systemImage: "wifi")) {
            VStack(alignment: .leading, spacing: 10) {
                Text("系统定位请求没有经过本地代理，请按以下步骤配置：\n\n1. 打开「设置 → 无线局域网」\n2. 确认已连接到正确的 WiFi（不是蜂窝数据）\n3. 点击当前 WiFi 右侧 (i) 图标\n4. 滑到底部「HTTP 代理」→ 选择「手动」\n5. 在「服务器」填写下面的地址，端口填写 8888\n6. 点右上角「存储」")
                    .font(.caption).foregroundStyle(.primary)

                HStack(spacing: 8) {
                    Text("127.0.0.1:8888").font(.caption.monospaced().bold()).foregroundStyle(.blue)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = "127.0.0.1:8888"
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                    } label: {
                        Label(copied ? "已复制" : "复制地址", systemImage: copied ? "checkmark" : "doc.on.doc").font(.caption)
                    }.buttonStyle(.bordered).tint(copied ? .green : .blue)
                }.padding(10).background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))

                Button { openSettings(.wifi) } label: {
                    Text("去设置 WiFi 代理").font(.body.weight(.medium)).frame(maxWidth: .infinity).padding(.vertical, 12)
                }.buttonStyle(.borderedProminent).tint(.blue)
            }.padding(.vertical, 4)
        }
    }
}

// MARK: - 改写失败

struct RewriteFailedTipContent: View {
    let dismiss: () -> Void

    var body: some View {
        GroupBox(label: Label("坐标改写失败", systemImage: "exclamationmark.triangle")) {
            VStack(alignment: .leading, spacing: 8) {
                Text("虚拟定位已连接，但坐标替换没有成功。可能原因：\n\n• 代理刚启动不久，数据还没开始改写（等待几秒后重试）\n• CA 证书与当前 App 版本不匹配\n• iOS 系统安全策略限制\n\n建议操作：\n1. 完全停止虚拟定位，再重新开启\n2. 删除旧证书，重新生成并安装\n3. 在诊断页查看详细日志")
                    .font(.caption).foregroundStyle(.primary)
            }.padding(.vertical, 4)
        }
    }
}
