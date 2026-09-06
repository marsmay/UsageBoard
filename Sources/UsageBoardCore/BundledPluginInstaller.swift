@preconcurrency import Foundation

public struct BundledPluginInstaller: Sendable {
    public var sourceDirectoryURL: URL
    public var destinationDirectoryURL: URL

    public init(sourceDirectoryURL: URL, destinationDirectoryURL: URL = ConfigStore.pluginsDirectoryURL()) {
        self.sourceDirectoryURL = sourceDirectoryURL
        self.destinationDirectoryURL = destinationDirectoryURL
    }

    @discardableResult
    public func installIfNeeded() throws -> [URL] {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceDirectoryURL.path) else {
            return []
        }

        try fileManager.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)

        let sourceFiles = try fileManager.contentsOfDirectory(
            at: sourceDirectoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "py" && !$0.lastPathComponent.hasPrefix("_") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var installed: [URL] = []
        for sourceURL in sourceFiles {
            let destinationURL = destinationDirectoryURL.appendingPathComponent(sourceURL.lastPathComponent)
            let existingDestination = try? fileManager.destinationOfSymbolicLink(atPath: destinationURL.path)

            if let existingDestination,
               URL(fileURLWithPath: existingDestination).resolvingSymlinksInPath() == sourceURL.resolvingSymlinksInPath() {
                continue
            }

            // A regular file may be a user-customized plugin. Only replace links.
            if existingDestination == nil, fileManager.fileExists(atPath: destinationURL.path) {
                continue
            }
            if existingDestination != nil {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.createSymbolicLink(at: destinationURL, withDestinationURL: sourceURL)
            installed.append(destinationURL)
        }
        return installed
    }
}
