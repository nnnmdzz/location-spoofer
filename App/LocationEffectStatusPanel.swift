import SwiftUI
import UIKit

struct LocationEffectStatusPanel: View {
    @ObservedObject private var effectMonitor = LocationEffectMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("定位运行状态", systemImage: "location.circle")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                statusBadge
            }

            switch effectMonitor.status {
            case .idle:
                Text("等待虚拟定位目标。坐标写入后会自动检测最多 3 次，后两次各间隔 10 秒。")
                    .font(.caption).foregroundStyle(.secondary)
            case .refreshing(let attempt, let total):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(total == 1 ? "正在手动检测" : "正在自动检测（\(attempt)/\(total)）")
                        .font(.caption.weight(.semibold))
                }
                Text("仅调整本 App 本轮 Core Location 请求精度，不会关闭系统定位服务或禁用 GPS。")
                    .font(.caption2).foregroundStyle(.secondary)
            case .effective(let distance, let accuracy):
                measurementText(distance: distance, accuracy: accuracy)
            case .cachePending(let distance, let accuracy):
                measurementText(distance: distance, accuracy: accuracy)
                Text("新样本仍明显偏离目标，系统可能仍在使用旧定位缓存。")
                    .font(.caption2).foregroundStyle(.secondary)
                retryButton
            case .gpsLikelyDominant(let distance, let accuracy):
                measurementText(distance: distance, accuracy: accuracy)
                Text("检测到远离目标的高精度样本，疑似 GPS/GNSS 或旧高精度来源仍占优；此判断为启发式。")
                    .font(.caption2).foregroundStyle(.secondary)
                retryButton
            case .unavailable:
                Text("本轮没有取得可用于判定的新定位样本。")
                    .font(.caption).foregroundStyle(.secondary)
                retryButton
            }

            Text("自动检测仅在写入或恢复目标时执行：首次立即检测，之后每隔 10 秒，最多 3 次；不会因 App 回到前台重复启动。手动“重新检测”只执行 1 次。")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch effectMonitor.status {
        case .idle:
            badge("待检测", color: .secondary)
        case .refreshing:
            badge("检测中", color: .blue)
        case .effective:
            badge("已生效", color: .green)
        case .cachePending:
            badge("缓存待刷新", color: .orange)
        case .gpsLikelyDominant:
            badge("疑似 GPS 占优", color: .orange)
        case .unavailable:
            badge("无新样本", color: .orange)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var retryButton: some View {
        Button { effectMonitor.retry() } label: {
            Label("重新检测", systemImage: "arrow.clockwise")
                .font(.caption)
        }
        .buttonStyle(.bordered)
    }

    private func measurementText(distance: Double, accuracy: Double) -> some View {
        Text(String(format: "距目标约 %.0f m · 样本精度约 %.0f m", distance, accuracy))
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
    }
}
