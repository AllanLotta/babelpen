import Foundation

/// UI strings. English is the default; Portuguese is included. Adding a
/// language = adding a case and filling the switch statements.
public struct L10n {
    public enum Language: String, CaseIterable { case en, pt }

    public let language: Language

    public init(_ language: Language) { self.language = language }

    /// `override` comes from the config ("en", "pt" or empty); otherwise the
    /// first supported language in the system's preferred list wins.
    public static func detect(override: String, preferred: [String] = Locale.preferredLanguages) -> Language {
        if let l = Language(rawValue: override.lowercased()) { return l }
        for code in preferred {
            if let l = Language(rawValue: String(code.prefix(2)).lowercased()) { return l }
        }
        return .en
    }

    private func pick(_ en: String, _ pt: String) -> String { language == .pt ? pt : en }

    // Status line
    public var ready: String { pick("Ready", "Pronto") }
    public var reviewing: String { pick("Reviewing…", "Revisando…") }
    public var applied: String { pick("Applied", "Aplicado") }
    public var paused: String { pick("Paused", "Pausado") }
    public var noPermission: String { pick("Needs Accessibility permission", "Sem permissão de Acessibilidade") }
    public func noIssues(ms: Int) -> String { pick("No issues (\(ms) ms)", "Sem correções (\(ms) ms)") }
    public func fixes(_ n: Int) -> String {
        language == .pt ? "\(n) \(n == 1 ? "correção" : "correções")" : "\(n) \(n == 1 ? "fix" : "fixes")"
    }
    public func fixes(_ n: Int, ms: Int) -> String { "\(fixes(n)) (\(ms) ms)" }
    public func failed(_ reason: String) -> String { pick("Failed (\(reason)). Try ⌃⌥R", "Falhou (\(reason)). Tenta ⌃⌥R") }
    public var noResponse: String { pick("no response", "sem resposta") }
    public func stats(reviews: Int, applied: Int) -> String {
        pick("\(reviews) reviews, \(applied) applied", "\(reviews) revisões, \(applied) aplicadas")
    }

    // Menu
    public var pause: String { pick("Pause", "Pausar") }
    public var resume: String { pick("Resume", "Retomar") }
    public var checkNow: String { pick("Check Now  ⌃⌥R", "Revisar agora  ⌃⌥R") }
    public var engine: String { pick("AI Engine", "Motor de IA") }
    public var customCommand: String { pick("Custom command", "Comando próprio") }
    public var accessibility: String { pick("Accessibility Permission…", "Permissão de Acessibilidade…") }
    public var launchAtLogin: String { pick("Launch at Login", "Abrir no login") }
    public var launchAtLoginApprove: String { pick("Launch at Login (approve in Settings)", "Abrir no login (aprovar em Ajustes)") }
    public var openConfig: String { pick("Open Config File…", "Abrir configuração…") }
    public var reloadConfig: String { pick("Reload Config", "Recarregar configuração") }
    public var openLog: String { pick("Open Log", "Abrir log") }
    public var quit: String { pick("Quit Revisor", "Sair do Revisor") }

    // Suggestion card
    public var apply: String { pick("Apply  ⌃⌥G", "Aplicar  ⌃⌥G") }
    public var dismiss: String { pick("Dismiss", "Ignorar") }
    public func cardHeader(_ n: Int) -> String { "REVISOR · \(fixes(n))".uppercased() }
}
