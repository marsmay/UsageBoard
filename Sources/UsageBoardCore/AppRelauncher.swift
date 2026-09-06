@preconcurrency import Foundation

public enum AppRelauncher {
    public static func relaunchCurrent() throws {
        let currentBundleURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let escapedCurrent = shellEscaped(currentBundleURL.path)

        let script = """
        #!/bin/bash
        mkdir -p ~/Library/Logs/UsageBoard
        exec 2>>~/Library/Logs/UsageBoard/relauncher.log
        set -e
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        open \(escapedCurrent)
        rm -f "$0"
        """

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-relaunch-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = scriptURL
        try process.run()
    }

    public static func relaunch(replacingWith newBundleURL: URL, cleanupDirectoryURL: URL? = nil) throws {
        let currentBundleURL = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier

        guard currentBundleURL.pathExtension == "app" else { throw UpdateError.invalidApplication }
        let parent = currentBundleURL.deletingLastPathComponent()
        let staged = parent.appendingPathComponent(".usageboard-staged-\(UUID().uuidString).app")
        let backup = parent.appendingPathComponent(".usageboard-backup-\(UUID().uuidString).app")
        var launched = false
        defer { if !launched { try? FileManager.default.removeItem(at: staged) } }
        // Prepare on the destination volume while the running application remains intact.
        try FileManager.default.copyItem(at: newBundleURL, to: staged)
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--deep", "--sign", "-", staged.path]
        try signer.run()
        signer.waitUntilExit()
        guard signer.terminationStatus == 0 else { throw UpdateError.invalidApplication }
        let script = replacementScript(current: currentBundleURL, staged: staged, backup: backup,
                                       pid: pid, cleanupDirectoryURL: cleanupDirectoryURL,
                                       logDirectoryURL: FileManager.default.homeDirectoryForCurrentUser
                                        .appendingPathComponent("Library/Logs/UsageBoard"))

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let process = Process()
        process.executableURL = scriptURL
        try process.run()
        launched = true
    }

    static func replacementScript(current: URL, staged: URL, backup: URL, pid: Int32,
                                  cleanupDirectoryURL: URL? = nil, logDirectoryURL: URL? = nil) -> String {
        let cleanup = cleanupDirectoryURL.map { "rm -rf \(shellEscaped($0.path))" } ?? ":"
        let logging = logDirectoryURL.map {
            "mkdir -p \(shellEscaped($0.path))\nexec 2>>\(shellEscaped($0.appendingPathComponent("relauncher.log").path))"
        } ?? ":"
        return """
        #!/bin/bash
        \(logging)
        set -e
        current=\(shellEscaped(current.path))
        staged=\(shellEscaped(staged.path))
        backup=\(shellEscaped(backup.path))
        rollback() {
            status=$?
            if [ -e "$backup" ]; then
                rm -rf "$current"
                mv "$backup" "$current"
                open "$current" || true
            fi
            rm -rf "$staged"
            rm -f "$0"
            exit "$status"
        }
        trap rollback EXIT
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        mv "$current" "$backup"
        mv "$staged" "$current"
        open "$current"
        trap - EXIT
        rm -rf "$backup"
        \(cleanup)
        rm -f "$0"
        """
    }

    private static func shellEscaped(_ path: String) -> String {
        let escaped = path.replacingOccurrences(of: "'", with: "'\\''")
        return "'\(escaped)'"
    }
}
