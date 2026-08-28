import Foundation

enum GitHubAuthError: LocalizedError {
    case ghNotFound
    case ghFailed(String)
    case noToken

    var errorDescription: String? {
        switch self {
        case .ghNotFound:
            "The gh command line tool was not found. Install it with: brew install gh"
        case .ghFailed(let message):
            "gh auth token failed: \(message)"
        case .noToken:
            "gh returned an empty token. Log in with: gh auth login"
        }
    }
}

/// Reads the GitHub token from the already authenticated gh CLI, so the app
/// needs no login of its own.
enum GitHubAuth {
    /// Locations to try, because a GUI app does not inherit the shell PATH.
    private static let candidatePaths = [
        "/opt/homebrew/bin/gh",
        "/usr/local/bin/gh",
        "/usr/bin/gh",
        "/run/current-system/sw/bin/gh",
    ]

    static func ghExecutable() -> URL? {
        let fm = FileManager.default
        for path in candidatePaths where fm.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to a login shell, which knows about custom install locations.
        if let found = try? runCapture(
            URL(fileURLWithPath: "/bin/zsh"),
            ["-lc", "command -v gh"]
        ), !found.isEmpty, fm.isExecutableFile(atPath: found) {
            return URL(fileURLWithPath: found)
        }
        return nil
    }

    static func token() throws -> String {
        guard let gh = ghExecutable() else { throw GitHubAuthError.ghNotFound }
        let token: String
        do {
            token = try runCapture(gh, ["auth", "token"])
        } catch let error as GitHubAuthError {
            throw error
        } catch {
            throw GitHubAuthError.ghFailed(error.localizedDescription)
        }
        guard !token.isEmpty else { throw GitHubAuthError.noToken }
        return token
    }

    /// The logged in account, used to tell "my PRs" from everyone else's.
    static func viewerLogin() throws -> String {
        guard let gh = ghExecutable() else { throw GitHubAuthError.ghNotFound }
        let login = try runCapture(gh, ["api", "user", "--jq", ".login"])
        guard !login.isEmpty else { throw GitHubAuthError.noToken }
        return login
    }

    @discardableResult
    private static func runCapture(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        let outData = out.fileHandleForReading.readDataToEndOfFile()
        let errData = err.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = String(decoding: outData, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let stderr = String(decoding: errData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitHubAuthError.ghFailed(stderr.isEmpty ? "exit \(process.terminationStatus)" : stderr)
        }
        return stdout
    }
}
