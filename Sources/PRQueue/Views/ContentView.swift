import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var state = state

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 230, max: 300)
        } content: {
            PRListView()
                .navigationSplitViewColumnWidth(min: 380, ideal: 520)
        } detail: {
            PRDetailView()
                .navigationSplitViewColumnWidth(min: 320, ideal: 400)
        }
        .searchable(text: $state.searchText, placement: .toolbar, prompt: "Filter by title, repo, author, or team")
        .toolbar {
            ToolbarItem(placement: .status) {
                if let error = state.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .lineLimit(1)
                        .help(error)
                } else if let last = state.lastRefresh {
                    Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Toggle(isOn: $state.groupByRepo) {
                    Label("Group by repository", systemImage: "rectangle.3.group")
                }
                .help("Group by repository")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await state.refresh() }
                } label: {
                    if state.isLoading {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(state.isLoading)
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
