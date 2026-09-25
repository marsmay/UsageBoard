@preconcurrency import Foundation

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

extension Decodable {
    static func decodeTranslations(prefix: String, from container: KeyedDecodingContainer<AnyCodingKey>) -> [String: String] {
        var translations: [String: String] = [:]
        for key in container.allKeys where key.stringValue.hasPrefix(prefix) {
            let language = String(key.stringValue.dropFirst(prefix.count))
            guard !language.isEmpty, let value = try? container.decode(String.self, forKey: key) else { continue }
            translations[language] = value
        }
        return translations
    }
}

extension Encodable {
    static func encodeTranslations(
        _ translations: [String: String],
        prefix: String,
        to container: inout KeyedEncodingContainer<AnyCodingKey>
    ) throws {
        for (language, value) in translations where !language.isEmpty {
            try container.encode(value, forKey: AnyCodingKey(stringValue: "\(prefix)\(language)"))
        }
    }
}

enum LocalizedStrings {
    static func localizedOptionalValue(base: String?, translations: [String: String], language: AppLanguage) -> String? {
        let raw = translations[language.rawValue]
        if let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return raw
        }
        return base
    }

    static func localizedValue(base: String, translations: [String: String], language: AppLanguage) -> String {
        localizedOptionalValue(base: base, translations: translations, language: language) ?? base
    }
}
