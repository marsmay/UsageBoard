@preconcurrency import Foundation
import Darwin

private final class DataBuffer: @unchecked Sendable {
    private var data = Data()
    private let limit: Int
    private var exceeded = false
    private let lock = NSLock()

    init(limit: Int) { self.limit = limit }

    func append(_ chunk: Data) {
        lock.lock()
        let remaining = limit - data.count
        if chunk.count > remaining { exceeded = true }
        data.append(chunk.prefix(remaining))
        lock.unlock()
    }

    var exceededLimit: Bool {
        lock.lock()
        defer { lock.unlock() }
        return exceeded
    }

    func snapshot() -> Data {
        lock.lock()
        defer { lock.unlock() }
        return data
    }
}

public struct PluginExecutor: Sendable {
    public var timeoutSeconds: TimeInterval

    public init(timeoutSeconds: TimeInterval = 15) {
        self.timeoutSeconds = timeoutSeconds
    }

    public func run(configuration: PluginConfiguration, displayName: String, language: AppLanguage) -> PluginSnapshot {
        guard configuration.enabled else {
            return PluginSnapshot(id: configuration.id, displayName: displayName, iconURL: configuration.metadata?.icon)
        }

        guard !configuration.executablePath.isEmpty else {
            return failed(configuration: configuration, displayName: displayName, message: text(.missingExecutablePath, language: language))
        }
        // `~` 只在 shell 中展开；两类插件统一拒绝而非静默展开或跑错脚本（architecture.md §3）。
        guard !configuration.executablePath.hasPrefix("~") else {
            return failed(configuration: configuration, displayName: displayName, message: text(.tildePath, language: language))
        }

        let process = Process()
        process.environment = pluginEnvironment()
        let executableURL = URL(fileURLWithPath: configuration.executablePath)
        let pluginArguments = pluginParameterArguments(configuration: configuration, language: language)
        if executableURL.pathExtension.lowercased() == "py" {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", configuration.executablePath] + pluginArguments
        } else {
            process.executableURL = executableURL
            process.arguments = pluginArguments
        }
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let outputBuffer = DataBuffer(limit: 8 * 1024 * 1024)
        let errorBuffer = DataBuffer(limit: 64 * 1024)
        let outputDrained = DispatchSemaphore(value: 0)
        let errorDrained = DispatchSemaphore(value: 0)

        stdout.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                outputDrained.signal()
            } else {
                outputBuffer.append(chunk)
            }
        }
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                errorDrained.signal()
            } else {
                errorBuffer.append(chunk)
            }
        }

        let exitSemaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exitSemaphore.signal() }

        do {
            try process.run()
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            return failed(configuration: configuration, displayName: displayName, message: error.localizedDescription)
        }
        // Only signal the process group if this plugin was its leader.
        let pluginPid = process.processIdentifier
        let leadsProcessGroup = Darwin.getpgid(pluginPid) == pluginPid

        let deadline = DispatchTime.now() + timeoutSeconds
        var finished = false
        var wasCancelled = false
        while !outputBuffer.exceededLimit {
            if Task.isCancelled { wasCancelled = true; break }
            if exitSemaphore.wait(timeout: min(.now() + 0.05, deadline)) == .success {
                finished = true
                break
            }
            if DispatchTime.now() >= deadline { break }
        }
        let signalTarget = leadsProcessGroup ? -pluginPid : pluginPid
        if !finished || (leadsProcessGroup && Self.isAlive(signalTarget)) {
            // A normally exited parent may still leave descendants holding the
            // pipes. Give the whole group time to clean up, even if the parent
            // exits immediately in response to SIGTERM.
            Darwin.kill(signalTarget, SIGTERM)
            let graceDeadline = DispatchTime.now() + 1.0
            while Self.isAlive(signalTarget) && DispatchTime.now() < graceDeadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
            var didKill = false
            if Self.isAlive(signalTarget) {
                Darwin.kill(signalTarget, SIGKILL)
                didKill = true
            }
            // 响应 SIGTERM 在宽限期内自行退出的进程按实际退出处理，不误报超时；
            // 被 SIGKILL 强杀的进程仍按超时/取消报告。
            if !finished, !didKill, exitSemaphore.wait(timeout: .now() + 1.0) == .success {
                finished = true
            }
        }

        // Wait briefly for readability handlers to drain remaining buffered data after EOF.
        _ = outputDrained.wait(timeout: .now() + 1.0)
        _ = errorDrained.wait(timeout: .now() + 1.0)
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        if outputBuffer.exceededLimit {
            return failed(configuration: configuration, displayName: displayName, message: text(.outputTooLarge, language: language))
        }
        if wasCancelled || Task.isCancelled {
            return failed(configuration: configuration, displayName: displayName, message: text(.cancelled, language: language))
        }
        if !finished {
            return failed(configuration: configuration, displayName: displayName, message: text(.timeout, language: language))
        }

        let outputData = outputBuffer.snapshot()
        let errorData = errorBuffer.snapshot()
        if process.terminationStatus != 0 {
            let stderrText = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return failed(configuration: configuration, displayName: displayName, message: stderrText?.isEmpty == false ? stderrText! : text(.exitCode(process.terminationStatus), language: language))
        }

        do {
            if let errorOutput = try? UsageBoardJSON.decoder().decode(PluginOutputError.self, from: outputData),
               !errorOutput.error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return failed(configuration: configuration, displayName: displayName, message: errorOutput.error)
            }
            let pluginOutput = try UsageBoardJSON.decoder().decode(PluginOutput.self, from: outputData)
            return PluginSnapshot(
                id: configuration.id,
                displayName: displayName,
                state: .ready,
                items: pluginOutput.items,
                updatedAt: pluginOutput.updatedAt,
                badge: pluginOutput.badge,
                badgeColor: pluginOutput.badgeColor,
                iconURL: configuration.metadata?.icon,
                chart: pluginOutput.chart,
                credits: pluginOutput.credits ?? []
            )
        } catch {
            return failed(configuration: configuration, displayName: displayName, message: "\(text(.jsonParseFailed, language: language))\(decodeErrorDescription(error))")
        }
    }

    public func pluginParameterArguments(configuration: PluginConfiguration, language: AppLanguage? = nil) -> [String] {
        var values = configuration.parameterValues
        if let language {
            values["USAGEBOARD_LANGUAGE"] = language.rawValue
        }

        return values
            .filter { !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .flatMap { ["--usageboard-param", "\($0.key)=\($0.value)"] }
    }

    private func pluginEnvironment() -> [String: String] {
        ProcessInfo.processInfo.environment.merging([
            "PYTHONIOENCODING": "utf-8",
            "PYTHONDONTWRITEBYTECODE": "1",
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
        ]) { _, new in new }
    }

    private func failed(configuration: PluginConfiguration, displayName: String, message: String) -> PluginSnapshot {
        PluginSnapshot(
            id: configuration.id,
            displayName: displayName,
            state: .failed(message),
            items: [],
            updatedAt: Date(),
            iconURL: configuration.metadata?.icon
        )
    }

    private struct PluginOutputError: Decodable {
        let error: String
    }

    private func decodeErrorDescription(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context):
            return formatDecodingError(context: context, fallback: error.localizedDescription)
        case DecodingError.keyNotFound(let key, let context):
            return formatDecodingError(context: context, fallback: "Missing key '\(key.stringValue)'")
        case DecodingError.typeMismatch(_, let context):
            return formatDecodingError(context: context, fallback: context.debugDescription)
        case DecodingError.valueNotFound(_, let context):
            return formatDecodingError(context: context, fallback: context.debugDescription)
        default:
            return error.localizedDescription
        }
    }

    private func formatDecodingError(context: DecodingError.Context, fallback: String) -> String {
        let path = context.codingPath.map(\.stringValue).joined(separator: ".")
        let detail = context.debugDescription.isEmpty ? fallback : context.debugDescription
        guard !path.isEmpty else { return detail }
        return "\(path): \(detail)"
    }

    private enum Message {
        case missingExecutablePath
        case tildePath
        case timeout
        case cancelled
        case outputTooLarge
        case exitCode(Int32)
        case jsonParseFailed
    }

    /// 存活探测：EPERM 表示进程存在但无权发信号，同样视为存活。
    private static func isAlive(_ pid: pid_t) -> Bool {
        Darwin.kill(pid, 0) == 0 || errno == EPERM
    }

    private func text(_ message: Message, language: AppLanguage) -> String {
        switch (message, language) {
        case (.outputTooLarge, .en): return "Plugin output exceeds the 8 MiB limit"
        case (.outputTooLarge, .zhHans): return "插件输出超过 8 MiB 上限"
        case (.missingExecutablePath, .en):
            return "Executable path is not configured"
        case (.missingExecutablePath, .zhHans):
            return "未配置可执行路径"
        case (.tildePath, .en):
            return "Executable path must be absolute; '~' is not expanded"
        case (.tildePath, .zhHans):
            return "可执行路径需为绝对路径，不支持展开 ~"
        case (.cancelled, .en):
            return "Plugin execution cancelled"
        case (.cancelled, .zhHans):
            return "插件执行已取消"
        case (.timeout, .en):
            return "Plugin execution timed out"
        case (.timeout, .zhHans):
            return "插件执行超时"
        case (.exitCode(let code), .en):
            return "Plugin exited with code \(code)"
        case (.exitCode(let code), .zhHans):
            return "插件退出码 \(code)"
        case (.jsonParseFailed, .en):
            return "JSON parsing failed: "
        case (.jsonParseFailed, .zhHans):
            return "JSON 解析失败："
        }
    }
}
