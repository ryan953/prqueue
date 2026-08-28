import SwiftUI


struct PRQueueApp: App {
    @State private var state = AppState()

    var body: some Scene {
        Window("PR Queue", id: "main") {
            ContentView()
                .environment(state)
                .frame(minWidth: 1_040, minHeight: 620)
                .task {
                    await state.refresh()
                    state.startAutoRefresh()
                }
        }
        .defaultSize(width: 1_280, height: 800)
        .commands {
            CommandGroup(after: .toolbar) {
                Button("Refresh") {
                    Task { await state.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environment(state)
        }
    }
}
