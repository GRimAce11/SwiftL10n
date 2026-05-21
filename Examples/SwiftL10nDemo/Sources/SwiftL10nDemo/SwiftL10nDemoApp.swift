import SwiftUI

@main
struct SwiftL10nDemoApp: App {
    var body: some Scene {
        Window("SwiftL10n Demo", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
