import SwiftUI

@main
struct PaopaoLocationSpooferApp: App {
    init() {
        RuntimeLogger.info("APP", "Lifecycle", "========== App 启动 ==========")
        if #available(iOS 16.0, *) {
            LocationSpooferAppShortcuts.updateAppShortcutParameters()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
