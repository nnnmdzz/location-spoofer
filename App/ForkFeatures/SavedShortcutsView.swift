import SwiftUI
import UIKit

struct SavedShortcutsView: View {
    @StateObject private var store = SavedSystemShortcutStore()
    @ObservedObject private var callbackRouter = SystemShortcutCallbackRouter.shared
    @State private var editingShortcut: SavedSystemShortcut?
    @State private var showingEditor = false
    @State private var didCopyResult = false

    var body: some View {
        Form {
            Section("我的快捷指令") {
                if store.items.isEmpty {
                    Text("添加一个系统快捷指令名称后，就可以从本 App 直接运行。iOS 不提供读取用户全部快捷指令列表的公开接口，因此名称需要手动登记一次。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.items) { item in
                        Button {
                            didCopyResult = false
                            SystemShortcutRunner.run(item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "command")
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(item.name)
                                        .foregroundStyle(.primary)
                                    Text(item.inputMode.displayName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "play.circle.fill")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                store.delete(item)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            Button {
                                editingShortcut = item
                                showingEditor = true
                            } label: {
                                Label("编辑", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                    }
                }

                Button {
                    editingShortcut = SavedSystemShortcut()
                    showingEditor = true
                } label: {
                    Label("添加快捷指令", systemImage: "plus.circle")
                }

                Button {
                    SystemShortcutRunner.openShortcutsApp()
                } label: {
                    Label("打开快捷指令 App", systemImage: "arrow.up.forward.app")
                }
            }

            if let message = callbackRouter.lastMessage {
                Section("本次执行结果") {
                    Text(message)
                        .foregroundStyle(callbackRouter.lastWasError ? .red : .primary)
                        .textSelection(.enabled)

                    Button {
                        UIPasteboard.general.string = message
                        didCopyResult = true
                    } label: {
                        Label(didCopyResult ? "已复制结果" : "复制结果", systemImage: "doc.on.doc")
                    }

                    Button("清除结果") {
                        callbackRouter.clearResult()
                        didCopyResult = false
                    }
                }
            }

            Section {
                Text("运行时会通过 Shortcuts 的 x-callback URL 交给系统快捷指令 App；成功、取消或错误后再回到 Location Spoofer。执行结果只保留在本次 App 进程中，不建立历史记录。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("我的快捷指令")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEditor) {
            NavigationView {
                SavedShortcutEditorView(shortcut: editingShortcut ?? SavedSystemShortcut()) { saved in
                    store.upsert(saved)
                    showingEditor = false
                }
            }
        }
    }
}

private struct SavedShortcutEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: SavedSystemShortcut
    let onSave: (SavedSystemShortcut) -> Void

    init(shortcut: SavedSystemShortcut, onSave: @escaping (SavedSystemShortcut) -> Void) {
        _draft = State(initialValue: shortcut)
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("快捷指令") {
                TextField("快捷指令名称", text: $draft.name)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Picker("输入方式", selection: $draft.inputMode) {
                    ForEach(SavedShortcutInputMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }

                if draft.inputMode == .fixedText {
                    TextField("固定文本", text: $draft.fixedText)
                }
            }

            Section {
                Text("名称必须与系统快捷指令 App 中的名称一致。剪贴板模式由 Shortcuts 在执行时读取当前剪贴板。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("快捷指令配置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("保存") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if draft.inputMode != .fixedText { draft.fixedText = "" }
                    onSave(draft)
                }
                .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}
