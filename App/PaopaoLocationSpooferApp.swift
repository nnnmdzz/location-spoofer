import SwiftUI

@main
struct PaopaoLocationSpooferApp: App {
    @UIApplicationDelegateAdaptor(LocationSpooferApplicationDelegate.self) private var appDelegate

    init() {
        RuntimeLogger.info("APP", "Lifecycle", "========== App 启动 ==========")
        if #available(iOS 16.0, *) {
            LocationSpooferAppShortcuts.updateAppShortcutParameters()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    Task { @MainActor in
                        _ = SystemShortcutCallbackRouter.shared.handle(url)
                    }
                }
        }
    }
}
