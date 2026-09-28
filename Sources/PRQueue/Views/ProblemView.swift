import SwiftUI

/// Takes the place of the list when a refresh failed and there is nothing to
/// show, so an auth failure never looks like an empty queue.
struct ProblemView: View {
    let problem: QueueProblem

    var body: some View {
        ContentUnavailableView {
            Label(problem.title, systemImage: problem.symbol)
        } description: {
            Text(problem.message)
        } actions: {
            VStack(spacing: 12) {
                if let command = problem.fixCommand {
                    Text(command)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                ProblemActions(problem: problem)
                DisclosureGroup("Details") {
                    Text(problem.detail)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(.caption)
                .frame(maxWidth: 420)
            }
        }
    }
}

/// A one-line version for when older results are still on screen.
struct ProblemBanner: View {
    let problem: QueueProblem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: problem.symbol)
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(problem.title).font(.callout.weight(.semibold))
                Text("Showing results from the last successful refresh.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .help(problem.detail)
            Spacer(minLength: 8)
            ProblemActions(problem: problem)
                .controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.12))
    }
}

private struct ProblemActions: View {
    @Environment(AppState.self) private var state
    let problem: QueueProblem
    @State private var launchError: String?

    var body: some View {
        HStack {
            if let command = problem.fixCommand {
                Button("Run in Terminal") {
                    do {
                        try TerminalCommand.run(command)
                    } catch {
                        launchError = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
                .help("Opens Terminal and runs: \(command)")
                Button("Copy Command") { TerminalCommand.copy(command) }
            }
            Button {
                Task { await state.refresh() }
            } label: {
                if state.isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Try Again")
                }
            }
            .disabled(state.isLoading)
        }
        .alert("Could not open Terminal", isPresented: Binding(
            get: { launchError != nil },
            set: { if !$0 { launchError = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(launchError ?? "")
        }
    }
}

extension QueueProblem {
    var symbol: String {
        switch kind {
        case .ghMissing: "terminal"
        case .loggedOut, .tokenRejected: "person.crop.circle.badge.exclamationmark"
        case .rateLimited: "hourglass"
        case .offline: "wifi.exclamationmark"
        case .other: "exclamationmark.triangle"
        }
    }
}
