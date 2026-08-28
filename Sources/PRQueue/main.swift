import Foundation

/// Entry point. With no arguments the SwiftUI app opens. With --report the
/// same triage rules run headless and print the queue, which makes the
/// ranking easy to check and to script.
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--report") || arguments.contains("--help") {
    if arguments.contains("--help") {
        print("""
        PR Queue

          PRQueue                Open the app.
          PRQueue --report       Print the triaged queue and exit.
          PRQueue --report --all Print every lane, not only the ones with items.
        """)
        exit(0)
    }
    await runReport(showEmptyLanes: arguments.contains("--all"))
    exit(0)
}

PRQueueApp.main()

// MARK: - Report

func runReport(showEmptyLanes: Bool) async {
    let store = PreferencesStore()
    let preferences = store.load()
    do {
        let token = try GitHubAuth.token()
        let viewer = try GitHubAuth.viewerLogin()
        let client = GitHubClient(token: token, viewer: viewer)
        let pullRequests = try await client.fetchQueue()
        let engine = TriageEngine(preferences: preferences, viewer: viewer)
        let triaged = engine.triage(pullRequests)

        print("PR Queue for \(viewer) — \(pullRequests.count) open pull requests\n")
        for lane in Lane.sidebarOrder {
            let rows = triaged.filter { $0.lane == lane }
            if rows.isEmpty && !showEmptyLanes { continue }
            print("\(lane.title.uppercased())  (\(rows.count))")
            for row in rows {
                let pr = row.pullRequest
                let score = String(row.score).padded(to: 5, alignRight: true)
                let name = "\(pr.shortRepo)#\(pr.number)".padded(to: 20)
                let idle = pr.idleDays().asAgeText.padded(to: 5, alignRight: true)
                print("  \(score)  \(name) \(idle) idle  \(pr.title.prefix(62))")
            }
            print("")
        }
    } catch {
        FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
        exit(1)
    }
}

private extension String {
    func padded(to width: Int, alignRight: Bool = false) -> String {
        guard count < width else { return String(prefix(width)) }
        let pad = String(repeating: " ", count: width - count)
        return alignRight ? pad + self : self + pad
    }
}
