@preconcurrency import Foundation

public struct UpdateInfo: Decodable, Equatable, Sendable {
    public var latestVersion: String
    public var downloadURL: String
    public var updatedAt: Date?
    public var notes: String?
    public var latestBuild: Int?

    public init(latestVersion: String, downloadURL: String, updatedAt: Date? = nil, notes: String? = nil, latestBuild: Int? = nil) {
        self.latestVersion = latestVersion
        self.downloadURL = downloadURL
        self.updatedAt = updatedAt
        self.notes = notes
        self.latestBuild = latestBuild
    }
}

public struct UpdateCheckResult: Equatable, Sendable {
    public var info: UpdateInfo
    public var hasUpdate: Bool

    public init(info: UpdateInfo, hasUpdate: Bool) {
        self.info = info
        self.hasUpdate = hasUpdate
    }
}

public struct DownloadedUpdate: Equatable, Sendable {
    public var appURL: URL
    public var cleanupDirectoryURL: URL

    public init(appURL: URL, cleanupDirectoryURL: URL) {
        self.appURL = appURL
        self.cleanupDirectoryURL = cleanupDirectoryURL
    }
}

public struct UpdateDownloader: Sendable {
    /// Current release zips are ~2.2 MB; the cap leaves wide headroom without
    /// letting a hostile or broken server stream unbounded data.
    public static let defaultMaxDownloadBytes: Int64 = 64 * 1024 * 1024

    private let maxDownloadBytes: Int64
    private let makeConfiguration: @Sendable () -> URLSessionConfiguration

    public init(maxDownloadBytes: Int64 = UpdateDownloader.defaultMaxDownloadBytes) {
        self.init(maxDownloadBytes: maxDownloadBytes) {
            let config = URLSessionConfiguration.ephemeral
            config.requestCachePolicy = .reloadIgnoringLocalCacheData
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 300
            return config
        }
    }

    init(maxDownloadBytes: Int64, makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration) {
        self.maxDownloadBytes = maxDownloadBytes
        self.makeConfiguration = makeConfiguration
    }

    public func download(from url: URL, expectedVersion: String? = nil) async throws -> DownloadedUpdate {
        try UpdateChecker.validateURL(url)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-download-\(UUID().uuidString).zip")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let response = try await downloadBody(from: url, to: tempURL)
        try UpdateChecker.validateResponse(response)

        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("usageboard-update-\(UUID().uuidString)")
        var shouldCleanExtractDir = true
        defer {
            if shouldCleanExtractDir {
                try? FileManager.default.removeItem(at: extractDir)
            }
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", tempURL.path, extractDir.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.extractionFailed
        }

        let appURLs = try FileManager.default.contentsOfDirectory(at: extractDir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard appURLs.count == 1, let appURL = appURLs.first else {
            throw UpdateError.extractionFailed
        }
        try Self.validateApp(at: appURL, expectedVersion: expectedVersion)
        shouldCleanExtractDir = false
        return DownloadedUpdate(appURL: appURL, cleanupDirectoryURL: extractDir)
    }

    /// Streams the body to `destination`, enforcing `maxDownloadBytes` while
    /// bytes arrive (not just via Content-Length) and the session's total
    /// time budget. Over-limit, timed-out, or cancelled transfers fail before
    /// any extraction is attempted.
    private func downloadBody(from url: URL, to destination: URL) async throws -> URLResponse {
        let delegate = LimitedDownloadDelegate(maxBytes: maxDownloadBytes, destinationURL: destination)
        let session = URLSession(configuration: makeConfiguration(), delegate: delegate, delegateQueue: nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.start(continuation: continuation, session: session, url: url)
            }
        } onCancel: {
            delegate.cancel()
        }
    }

    static func validateApp(at url: URL, expectedVersion: String?) throws {
        guard url.lastPathComponent == "UsageBoard.app",
              (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == false,
              let bundle = Bundle(url: url),
              bundle.bundleIdentifier == "ltd.may.UsageBoard",
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              expectedVersion == nil || version == expectedVersion,
              let executable = bundle.executableURL,
              executable.resolvingSymlinksInPath().path.hasPrefix(url.resolvingSymlinksInPath().path + "/"),
              (try? executable.resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
              FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw UpdateError.invalidApplication
        }
    }
}

public enum UpdateError: Error, LocalizedError {
    case extractionFailed
    case invalidApplication
    case downloadTooLarge

    public var errorDescription: String? {
        switch self {
        case .extractionFailed: return "更新包解压失败"
        case .invalidApplication: return "更新包中的应用标识、版本或可执行文件无效"
        case .downloadTooLarge: return "更新包体积超过下载限制"
        }
    }
}

/// Download delegate that aborts the transfer as soon as the received (or
/// declared) byte count exceeds the limit. Retains its session until the task
/// completes so the transfer cannot be deallocated mid-flight.
private final class LimitedDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let maxBytes: Int64
    private let destinationURL: URL
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URLResponse, Error>?
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var didExceedLimit = false
    private var cancelRequested = false

    init(maxBytes: Int64, destinationURL: URL) {
        self.maxBytes = maxBytes
        self.destinationURL = destinationURL
    }

    func start(continuation: CheckedContinuation<URLResponse, Error>, session: URLSession, url: URL) {
        let task = session.downloadTask(with: url)
        lock.lock()
        self.continuation = continuation
        self.session = session
        self.task = task
        let cancelRequested = self.cancelRequested
        lock.unlock()
        if cancelRequested {
            task.cancel()
        } else {
            task.resume()
        }
    }

    func cancel() {
        lock.lock()
        cancelRequested = true
        let task = self.task
        lock.unlock()
        task?.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        // totalBytesExpectedToWrite is -1 when the server does not declare a
        // length, so the running total is the enforcement that always applies.
        guard totalBytesWritten > maxBytes || totalBytesExpectedToWrite > maxBytes else { return }
        lock.lock()
        didExceedLimit = true
        lock.unlock()
        downloadTask.cancel()
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        do {
            // The system deletes `location` when this method returns.
            try FileManager.default.moveItem(at: location, to: destinationURL)
            if let response = downloadTask.response {
                finish(.success(response))
            } else {
                finish(.failure(URLError(.badServerResponse)))
            }
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            lock.lock()
            let exceeded = didExceedLimit
            lock.unlock()
            finish(.failure(exceeded ? UpdateError.downloadTooLarge : error))
        }
        session.finishTasksAndInvalidate()
        lock.lock()
        self.session = nil
        self.task = nil
        lock.unlock()
    }

    private func finish(_ result: Result<URLResponse, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }
}

public struct UpdateChecker: Sendable {
    public init() {}

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    public func check(currentVersion: String, url: URL) async throws -> UpdateCheckResult {
        try Self.validateURL(url)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let existing = components?.queryItems ?? []
        components?.queryItems = existing + [URLQueryItem(name: "_", value: String(Int.random(in: 1_000_000...9_999_999)))]
        guard let cacheBustURL = components?.url else {
            throw URLError(.badURL)
        }
        let (data, response) = try await Self.session.data(from: cacheBustURL)
        try Self.validateResponse(response)
        let info = try UsageBoardJSON.decoder().decode(UpdateInfo.self, from: data)
        guard let downloadURL = URL(string: info.downloadURL) else { throw URLError(.badURL) }
        try Self.validateURL(downloadURL)
        return UpdateCheckResult(info: info, hasUpdate: Self.isVersion(info.latestVersion, newerThan: currentVersion))
    }

    static func validateURL(_ url: URL) throws {
        guard url.scheme?.lowercased() == "https", url.host?.isEmpty == false,
              url.user == nil, url.password == nil else { throw URLError(.badURL) }
    }

    static func validateResponse(_ response: URLResponse) throws {
        guard let response = response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode), let url = response.url else {
            throw URLError(.badServerResponse)
        }
        try validateURL(url)
    }

    public static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let left = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let right = current.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(left.count, right.count)

        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l != r { return l > r }
        }

        return false
    }
}
