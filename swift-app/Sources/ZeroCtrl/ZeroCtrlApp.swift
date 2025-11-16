import SwiftUI

@main
struct ZeroCtrlApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1300, height: 1000)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
