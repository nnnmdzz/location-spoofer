import SwiftUI
import PrivateSignerUI

struct ForkEnhancementsView: View {
    @ObservedObject private var effectMonitor = LocationEffectMonitor.shared
    @State private var manualSettingsHint = ""

    var body: some View {
        Form {
            Section("定位生效诊断") {
                LocationEffectStatusPanel()
                    .listRowInsets(EdgeInsets())

                Button {
                    effectMonitor.retry(reason: "增强功能手动检测")
                } label: {
                    Label("立即重新检测", systemImage: "arrow.clockwise")
                }
                .disabled(effectMonitor.target == nil || isRefreshing)

                Text("重新检测会请求一份新的 Core Location 样本并与当前虚拟目标比较。它不会清除 locationd 缓存、关闭 GPS/GNSS，也不会修改系统定位服务开关。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            WlocAccuracySettingsSection()

            Section("自动化与更新") {
                NavigationLink {
                    SavedShortcutsView()
                } label: {
                    Label("我的快捷指令", systemImage: "command")
                }

                NavigationLink {
                    ForkUpdateCheckView()
                } label: {
                    Label("App 更新", systemImage: "arrow.triangle.2.circlepath")
                }

                NavigationLink {
                    SigningJobsView(context: PrivateSigning.uiContext)
                } label: {
                    Label("私人 IPA 签名", systemImage: "signature")
                }
            }

            Section("系统设置快捷入口") {
                settingsButton("定位服务", systemImage: "location.circle", destination: .locationServices)
                settingsButton("Wi-Fi", systemImage: "wifi", destination: .wifi)
                settingsButton("本 App 定位权限", systemImage: "app.badge.checkmark", destination: .appPermissions)
                settingsButton("通用", systemImage: "gearshape", destination: .general)

                Text("“定位服务”优先使用私有 prefs/App-Prefs 路径，并按既定规则不会 fallback 到本 App 设置页；系统拒绝跳转时会显示手动路径。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("关于增强功能") {
                Text("这里集中放置 fork 专属能力。WLOC 精度同时用于 APP 模式和第三方代理模式；定位生效判断为诊断性启发式结果，不代表 iOS 暴露了 GPS 来源控制。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("增强功能")
        .navigationBarTitleDisplayMode(.inline)
        .alert("无法直接跳转", isPresented: Binding(
            get: { !manualSettingsHint.isEmpty },
            set: { if !$0 { manualSettingsHint = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(manualSettingsHint)
        }
    }

    private var isRefreshing: Bool {
        if case .refreshing = effectMonitor.status { return true }
        return false
    }

    private func settingsButton(
        _ title: String,
        systemImage: String,
        destination: SystemSettingsDestination
    ) -> some View {
        Button {
            SystemSettingsNavigator.open(destination) { hint in
                if let hint { manualSettingsHint = hint }
            }
        } label: {
            Label(title, systemImage: systemImage)
        }
    }
}
