import Foundation

/// Writing languages: the languages you type in. They're a hint for the model
/// (accents, spelling conventions, ambiguous words). Text is always fixed in
/// the language it's written in and never translated.
public enum Languages {
    /// Offered in the menu. Any ISO 639-1 code also works in config.json.
    public static let common = [
        "en", "es", "pt", "fr", "de", "it", "nl", "pl", "sv", "da", "nb", "fi", "cs", "ro", "hu", "el",
        "tr", "ru", "uk", "he", "ar", "hi", "id", "vi", "ja", "ko", "zh",
    ]

    /// Distinct language codes from the system's preferred languages (at most 3).
    public static func fromSystem(_ preferred: [String] = Locale.preferredLanguages) -> [String] {
        var out: [String] = []
        for identifier in preferred {
            let code = String(identifier.split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "").lowercased()
            if !code.isEmpty, !out.contains(code) { out.append(code) }
            if out.count == 3 { break }
        }
        return out.isEmpty ? ["en"] : out
    }

    /// Configured languages, or the system's when none are set.
    public static func effective(_ configured: [String], preferred: [String] = Locale.preferredLanguages) -> [String] {
        let cleaned = configured.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return cleaned.isEmpty ? fromSystem(preferred) : cleaned
    }

    /// Name of a language in another language ("it" in "pt" → "Italiano").
    public static func name(_ code: String, in displayLanguage: String = "en") -> String {
        let locale = Locale(identifier: displayLanguage)
        guard let name = locale.localizedString(forLanguageCode: code) else { return code }
        return name.prefix(1).uppercased() + name.dropFirst()
    }

    /// Adds or removes `code`. Starting from "match system" turns the system's
    /// languages into an explicit list first. An empty result means "match system".
    public static func toggle(_ code: String, in configured: [String], preferred: [String] = Locale.preferredLanguages) -> [String] {
        var list = effective(configured, preferred: preferred)
        if let i = list.firstIndex(of: code) { list.remove(at: i) } else { list.append(code) }
        return list
    }
}

/// Your own words: names, products, jargon, slang. Babelpen tells the model to
/// keep them exactly as written. Stored one per line in vocabulary.txt.
public enum Vocabulary {
    public static let maxTermLength = 60

    public static let fileHeader = """
    # Babelpen vocabulary: one word or phrase per line.
    # These are kept exactly as written: never corrected, translated or re-capitalized.
    # Good candidates: names, product and company names, internal jargon, slang you mean to use.
    # Lines starting with # are ignored.

    """

    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let term = line.trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty, !term.hasPrefix("#"), !seen.contains(term) else { continue }
            seen.insert(term)
            out.append(term)
        }
        return out
    }

    /// Cleans a selection into a term, or nil if it isn't a sensible one.
    public static func normalize(_ selection: String) -> String? {
        let term = selection.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?\"'()[]{}“”‘’"))
        guard !term.isEmpty, term.count <= maxTermLength, !term.contains(where: \.isNewline) else { return nil }
        return term
    }

    /// Returns the file text with `term` appended, or nil if it's already there.
    public static func appending(_ term: String, to text: String) -> String? {
        if parse(text).contains(term) { return nil }
        var out = text
        if !out.isEmpty, !out.hasSuffix("\n") { out += "\n" }
        return out + term + "\n"
    }
}
