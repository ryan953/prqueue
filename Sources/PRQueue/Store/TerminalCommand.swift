import AppKit

/// Runs a shell command in a new Terminal window. `gh auth login` is
/// interactive, so it needs a real terminal. Opening a `.command` file works
/// without the Automation permission that scripting Terminal would ask for.
enum TerminalCommand {
    static func run(_ command: String) throws {
        let script = """
        #!/bin/zsh -l
        rm -f -- "$0"
        echo "$ \(command)"
        \(command)
        echo
        echo "Done. Switch back to PR Queue and it will refresh."
        read -s -k '?Press any key to close this window.'
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("prqueue-fix-\(UUID().uuidString).command")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        NSWorkspace.shared.open(url)
    }

    static func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}
