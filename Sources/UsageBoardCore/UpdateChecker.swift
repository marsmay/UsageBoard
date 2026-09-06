@preconcurrency import Foundation

public struct UpdateInfo: Decodable, Equatable, Sendable {
    public var latestVersion: String
    public var downloadURL: String
    public var updatedAt: Date?
    public var notes: String?

    public init(latestVersion: String, downloadURL: String, updatedAt: Date? = nil, notes: String? = nil) {
        self.latestVersion = latestVersion
        self.downloadURL = downloadURL
        self.updatedAt = updatedAt
        self.notes = notes
    }
}

public struct UpdateCheckResult: Equatable, Sendable {
    public var info: UpdateInfo
    public var hasUpdate: Bool
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
    public init() {}

    public func download(from url: URL, expectedVersion: String? = nil) async throws -> DownloadedUpdate {
        try UpdateChecker.validateURL(url)
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        defer { try? FileManager.default.removeItem(at: tempURL) }
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

    public var errorDescription: String? {
        switch self {
        case .extractionFailed: return "更新包解压失败"
        case .invalidApplication: return "更新包中的应用标识、版本或可执行文件无效"
        }
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
