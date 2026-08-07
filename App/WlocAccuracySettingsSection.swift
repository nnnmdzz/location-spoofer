import SwiftUI

struct WlocAccuracySettingsSection: View {
    private static let customOption = -1

    @ObservedObject private var preference = WlocAccuracyPreference.shared
    @State private var selectedOption = WlocAccuracyPreset.standard.rawValue
    @State private var customAccuracyText = String(WlocAccuracyPreset.standard.rawValue)
    @State private var validationMessage = ""

    var body: some View {
        Section("WLOC 定位精度") {
            Picker("精度", selection: $selectedOption) {
                ForEach(WlocAccuracyPreset.allCases) { preset in
                    Text(preset.displayName).tag(preset.rawValue)
                }
                Text("自定义").tag(Self.customOption)
            }
            .onChange(of: selectedOption) { newValue in
                guard let preset = WlocAccuracyPreset(rawValue: newValue) else {
                    if preference.matchingPreset != nil {
                        customAccuracyText = String(preference.meters)
                    }
                    return
                }
                preference.select(preset)
                customAccuracyText = String(preset.rawValue)
            }

            if selectedOption == Self.customOption {
                HStack(spacing: 12) {
                    TextField("1–1000", text: $customAccuracyText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("m")
                        .foregroundStyle(.secondary)
                    Button("应用") {
                        applyCustomAccuracy()
                    }
                }
            }

            HStack {
                Text("当前配置")
                Spacer()
                Text("\(preference.meters) m")
                    .font(.footnote.monospaced())
                    .foregroundStyle(.secondary)
            }

            if let preset = preference.matchingPreset {
                Text(preset.detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("当前使用自定义精度。WLOC 上游接口按整数米处理 accuracy。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Text("可输入 1–1000m。配置会持久化，并在下一次开启或切换虚拟定位时同时用于 APP 模式和第三方代理模式。更小的值不保证一定能压过 GNSS/GPS，建议结合生效检测结果对比。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear {
            syncEditorFromPreference()
        }
        .alert("精度设置无效", isPresented: Binding(
            get: { !validationMessage.isEmpty },
            set: { if !$0 { validationMessage = "" } }
        )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(validationMessage)
        }
    }

    private func syncEditorFromPreference() {
        customAccuracyText = String(preference.meters)
        selectedOption = preference.matchingPreset?.rawValue ?? Self.customOption
    }

    private func applyCustomAccuracy() {
        let trimmed = customAccuracyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Int(trimmed),
              WlocAccuracyPreference.allowedRange.contains(value),
              preference.setCustomMeters(value) else {
            validationMessage = "请输入 1–1000 之间的整数米数。"
            return
        }
        customAccuracyText = String(value)
        selectedOption = preference.matchingPreset?.rawValue ?? Self.customOption
    }
}
