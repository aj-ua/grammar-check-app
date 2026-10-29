import SwiftUI
import AppKit

@main
struct GrammarCheckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var checker = CheckerModel()

    var body: some Scene {
        Window("Grammar Check", id: "main") {
            ContentView()
                .environmentObject(checker)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1000, height: 640)

        MenuBarExtra("Grammar Check", systemImage: "text.badge.checkmark") {
            MenuContent()
        }

        Settings {
            SettingsView()
        }
    }
}

struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open Grammar Check") {
            openWindow(id: "main")
            NSApp.activate()
        }
        Button("Check Selected Text (⌃⌥G)") {
            SelectionController.shared.trigger()
        }
        Divider()
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Grammar Check") { NSApp.terminate(nil) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Writing to the CLI's stdin after it exited must not kill the app.
        signal(SIGPIPE, SIG_IGN)
        SelectionController.shared.install()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false // keep running in the menu bar for the global shortcut
    }
}
