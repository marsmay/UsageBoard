@preconcurrency import Foundation
import Darwin

private final class DataBuffer: @unchecked Sendable {
    private var data = Data()
    private let lock = NSLock()

    func append(_ chunk: Data) {
        lock.lock()
        data.append(chunk)
        lock.unlock()
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

        let outputBuffer = DataBuffer()
        let errorBuffer = DataBuffer()
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

        let finished = exitSemaphore.wait(timeout: .now() + timeoutSeconds) == .success
        if !finished {
            process.terminate()
            if exitSemaphore.wait(timeout: .now() + 1.0) != .success {
                Darwin.kill(process.processIdentifier, SIGKILL)
                _ = exitSemaphore.wait(timeout: .now() + 1.0)
            }
        }

        // Wait briefly for readability handlers to drain remaining buffered data after EOF.
        _ = outputDrained.wait(timeout: .now() + 1.0)
        _ = errorDrained.wait(timeout: .now() + 1.0)
        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

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
                chart: pluginOutput.chart
            )
        } catch {
            if let errorOutput = try? UsageBoardJSON.decoder().decode(PluginOutputError.self, from: outputData),
               !errorOutput.error.isEmpty {
                return failed(configuration: configuration, displayName: displayName, message: errorOutput.error)
            }
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
        case timeout
        case exitCode(Int32)
        case jsonParseFailed
    }

    private func text(_ message: Message, language: AppLanguage) -> String {
        switch (message, language) {
        case (.missingExecutablePath, .en):
            return "Executable path is not configured"
        case (.missingExecutablePath, .zhHans):
            return "未配置可执行路径"
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
