import Foundation

/// User settings, stored as JSON in ~/Library/Application Support/Babelpen/config.json.
/// Every key is optional in the file; missing keys fall back to the defaults below.
public struct Config: Codable, Equatable {
    public enum Provider: String, Codable, CaseIterable {
        case claude   // Claude Code CLI (`claude`), your Claude plan
        case codex    // OpenAI Codex CLI (`codex`), your ChatGPT plan
        case command  // any CLI that reads the prompt on stdin and prints the answer
    }

    /// Which local AI CLI does the proofreading.
    public var provider: Provider = .claude
    /// Model passed to the CLI. Empty = the CLI's default.
    public var model: String = ""
    /// Reasoning effort passed to the CLI ("low" is plenty for proofreading).
    public var effort: String = "low"
    /// For `provider: "command"`: executable and arguments, e.g. ["ollama", "run", "llama3.2"].
    public var command: [String] = []
    /// Optional context for the model, e.g. "Software engineer, writes in English and Spanish".
    public var about: String = ""
    /// Seconds of no typing before a review starts.
    public var debounceSeconds: Double = 1.0
    public var minCharacters: Int = 8
    public var maxCharacters: Int = 2500
    /// Bundle identifiers where Babelpen stays quiet.
    public var ignoredApps: [String] = Config.defaultIgnoredApps
    /// Languages you write in (ISO 639-1 codes like "en", "it"). Empty = your system languages.
    public var languages: [String] = []
    /// Interface language: "en", "pt", "es", "fr", "de", "it", or empty to follow the system.
    public var interfaceLanguage: String = ""
    /// Model for rewrites, translations and explanations. Empty = same as `model`.
    public var assistModel: String = ""
    /// The language you read best (explanations of selected text). Empty = interface language.
    public var readingLanguage: String = ""
    /// Where drafts get translated to. Empty = first writing language that isn't your reading language.
    public var translateTo: String = ""
    /// Offer a translation when a draft is in another language than `translateTo`.
    public var offerTranslation: Bool = true
    /// Bundle identifiers where that offer never shows (it's still one ⌃⌥T away).
    public var offerTranslationIgnoredApps: [String] = []
    /// Show a "Translate" button when you select text written in another language.
    public var translateSelection: Bool = true

    public static let defaultIgnoredApps = [
        "com.apple.Terminal", "com.googlecode.iterm2", "com.mitchellh.ghostty", "dev.warp.Warp-Stable",
        "com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.apple.dt.Xcode",
        "com.jetbrains.intellij", "com.google.android.studio", "dev.zed.Zed",
        "com.1password.1password", "com.apple.keychainaccess", "com.bitwarden.desktop", "com.apple.Passwords",
    ]

    public init() {}

    private enum Keys: String, CodingKey {
        case provider, model, effort, command, about, debounceSeconds, minCharacters, maxCharacters, ignoredApps
        case languages, interfaceLanguage
        case assistModel, readingLanguage, translateTo, offerTranslation, offerTranslationIgnoredApps, translateSelection
        case language // 0.1 name of interfaceLanguage, still read
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        let d = Config()
        provider = (try? c.decodeIfPresent(Provider.self, forKey: .provider)) ?? d.provider
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? d.model
        effort = try c.decodeIfPresent(String.self, forKey: .effort) ?? d.effort
        command = try c.decodeIfPresent([String].self, forKey: .command) ?? d.command
        about = try c.decodeIfPresent(String.self, forKey: .about) ?? d.about
        debounceSeconds = try c.decodeIfPresent(Double.self, forKey: .debounceSeconds) ?? d.debounceSeconds
        minCharacters = try c.decodeIfPresent(Int.self, forKey: .minCharacters) ?? d.minCharacters
        maxCharacters = try c.decodeIfPresent(Int.self, forKey: .maxCharacters) ?? d.maxCharacters
        ignoredApps = try c.decodeIfPresent([String].self, forKey: .ignoredApps) ?? d.ignoredApps
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? d.languages
        interfaceLanguage = try c.decodeIfPresent(String.self, forKey: .interfaceLanguage)
            ?? c.decodeIfPresent(String.self, forKey: .language) ?? d.interfaceLanguage
        assistModel = try c.decodeIfPresent(String.self, forKey: .assistModel) ?? d.assistModel
        readingLanguage = try c.decodeIfPresent(String.self, forKey: .readingLanguage) ?? d.readingLanguage
        translateTo = try c.decodeIfPresent(String.self, forKey: .translateTo) ?? d.translateTo
        offerTranslation = try c.decodeIfPresent(Bool.self, forKey: .offerTranslation) ?? d.offerTranslation
        offerTranslationIgnoredApps = try c.decodeIfPresent([String].self, forKey: .offerTranslationIgnoredApps)
            ?? d.offerTranslationIgnoredApps
        translateSelection = try c.decodeIfPresent(Bool.self, forKey: .translateSelection) ?? d.translateSelection
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: Keys.self)
        try c.encode(provider, forKey: .provider)
        try c.encode(model, forKey: .model)
        try c.encode(effort, forKey: .effort)
        try c.encode(command, forKey: .command)
        try c.encode(about, forKey: .about)
        try c.encode(debounceSeconds, forKey: .debounceSeconds)
        try c.encode(minCharacters, forKey: .minCharacters)
        try c.encode(maxCharacters, forKey: .maxCharacters)
        try c.encode(ignoredApps, forKey: .ignoredApps)
        try c.encode(languages, forKey: .languages)
        try c.encode(interfaceLanguage, forKey: .interfaceLanguage)
        try c.encode(assistModel, forKey: .assistModel)
        try c.encode(readingLanguage, forKey: .readingLanguage)
        try c.encode(translateTo, forKey: .translateTo)
        try c.encode(offerTranslation, forKey: .offerTranslation)
        try c.encode(offerTranslationIgnoredApps, forKey: .offerTranslationIgnoredApps)
        try c.encode(translateSelection, forKey: .translateSelection)
    }

    public static func decode(_ data: Data) throws -> Config { try JSONDecoder().decode(Config.self, from: data) }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}

/// Loads and saves the config file.
public final class ConfigStore {
    public let url: URL
    public private(set) var config = Config()

    public init(url: URL = ConfigStore.defaultURL) { self.url = url }

    /// vocabulary.txt, next to config.json.
    public var vocabularyURL: URL { url.deletingLastPathComponent().appendingPathComponent("vocabulary.txt") }

    /// Your vocabulary terms. Creates the file with instructions on first use.
    public func vocabulary() -> [String] {
        guard let text = try? String(contentsOf: vocabularyURL, encoding: .utf8) else {
            writeVocabulary(Vocabulary.fileHeader)
            return []
        }
        return Vocabulary.parse(text)
    }

    /// Adds a term. Returns false when it was already there.
    @discardableResult
    public func addToVocabulary(_ term: String) -> Bool {
        let current = (try? String(contentsOf: vocabularyURL, encoding: .utf8)) ?? Vocabulary.fileHeader
        guard let updated = Vocabulary.appending(term, to: current) else { return false }
        writeVocabulary(updated)
        return true
    }

    private func writeVocabulary(_ text: String) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? text.write(to: vocabularyURL, atomically: true, encoding: .utf8)
    }

    public static var defaultURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Babelpen/config.json")
    }

    /// Reads the file, creating it with defaults on first run. Returns an error
    /// message when the file exists but can't be parsed (defaults are used then).
    @discardableResult
    public func load() -> String? {
        guard let data = try? Data(contentsOf: url) else {
            config = Config()
            save()
            return nil
        }
        do {
            config = try Config.decode(data)
            return nil
        } catch {
            config = Config()
            return "config.json: \(error.localizedDescription)"
        }
    }

    public func update(_ change: (inout Config) -> Void) {
        change(&config)
        save()
    }

    public func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? config.encoded() { try? data.write(to: url, options: .atomic) }
    }
}
