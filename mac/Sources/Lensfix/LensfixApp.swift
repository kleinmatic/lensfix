import SwiftUI
import AppKit

// Minimal scaffold to prove the SwiftPM + CLT toolchain can build & run a
// SwiftUI App without full Xcode. Real UI comes next.

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // An SPM executable launches as an "accessory" by default; promote it
        // to a regular app so it gets a Dock icon, menu bar, and focus.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct LensfixApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("Lensfix") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
