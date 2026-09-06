import AppKit
import SwiftUI

enum BrandIconSource {
    static var resourceDirectoryURL: URL {
        if let resources = Bundle.main.resourceURL,
           FileManager.default.fileExists(atPath: resources.appendingPathComponent("icons").path) {
            return resources
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources", isDirectory: true)
    }

    static func url(
        for iconPath: String?,
        isDark: Bool,
        resourceDirectoryURL: URL = resourceDirectoryURL
    ) -> URL? {
        guard let iconPath, !iconPath.isEmpty else { return nil }
        if let url = URL(string: iconPath), let scheme = url.scheme {
            return ["https", "http", "file"].contains(scheme.lowercased()) ? url : nil
        }
        if isDark, iconPath.hasPrefix("icons/light/") {
            let darkPath = "icons/dark/" + iconPath.dropFirst("icons/light/".count)
            let darkURL = resourceDirectoryURL.appendingPathComponent(darkPath)
            if FileManager.default.fileExists(atPath: darkURL.path) { return darkURL }
        }
        if iconPath.hasPrefix("/") { return URL(fileURLWithPath: iconPath) }
        return resourceDirectoryURL.appendingPathComponent(iconPath)
    }
}

final class BrandIconCache: @unchecked Sendable {
    static let shared = BrandIconCache()
    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        c.totalCostLimit = 16 * 1024 * 1024
        return c
    }()

    func image(for url: URL) async -> NSImage? {
        let key = url.absoluteString as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let data: Data
        if url.isFileURL {
            guard let contents = try? Data(contentsOf: url) else { return nil }
            data = contents
        } else {
            guard let (contents, response) = try? await URLSession.shared.data(from: url),
                  let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else { return nil }
            data = contents
        }
        guard let image = NSImage(data: data) else { return nil }
        let cost = max(data.count, 1)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }
}

struct BrandTile: View {
    var iconURL: String?
    var fallbackName: String
    var size: CGFloat = 22

    @State private var loadedImage: NSImage?
    @Environment(\.colorScheme) private var colorScheme

    private var resolvedIconURL: URL? {
        BrandIconSource.url(for: iconURL, isDark: colorScheme == .dark)
    }

    var body: some View {
        let radius = size * 0.27
        ZStack {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .padding(size * 0.08)
            } else {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fallbackGradient)
                Text(initials)
                    .font(.system(size: size * 0.45, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
        )
        .task(id: resolvedIconURL) {
            guard let url = resolvedIconURL else {
                loadedImage = nil
                return
            }
            loadedImage = nil
            let image = await BrandIconCache.shared.image(for: url)
            guard !Task.isCancelled else { return }
            loadedImage = image
        }
    }

    private var initials: String {
        let trimmed = fallbackName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "?" }
        return String(first).uppercased()
    }

    private var fallbackGradient: LinearGradient {
        let seed = fallbackName.utf8.reduce(UInt(0)) { ($0 &* 31) &+ UInt($1) }
        let palette: [(Color, Color)] = [
            (Color(red: 0.353, green: 0.784, blue: 0.980), Color(red: 0.039, green: 0.518, blue: 1.0)),
            (Color(red: 0.482, green: 0.490, blue: 0.910), Color(red: 0.369, green: 0.361, blue: 0.902)),
            (Color(red: 1.0, green: 0.702, blue: 0.251), Color(red: 1.0, green: 0.624, blue: 0.039)),
            (Color(red: 0.310, green: 0.820, blue: 0.349), Color(red: 0.114, green: 0.620, blue: 0.278)),
            (Color(red: 1.0, green: 0.420, blue: 0.710), Color(red: 0.851, green: 0.275, blue: 0.627)),
            (Color(red: 0.686, green: 0.322, blue: 0.871), Color(red: 0.478, green: 0.247, blue: 0.722)),
        ]
        let pair = palette[Int(seed % UInt(palette.count))]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}
