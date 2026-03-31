import SwiftUI
#if os(macOS)
import AppKit
#endif

@main
struct FinnApp: App {
    #if os(macOS)
    init() {
        // SPM executables don't get automatic app activation — force it
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
