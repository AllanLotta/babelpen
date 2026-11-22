import Foundation

/// Interface strings. To add a language: add a case to `Language`, its native
/// name, and one entry per key in `table`. Placeholders: {n} {ms} {x} {r} {a}.
public struct L10n {
    public enum Language: String, CaseIterable {
        case en, pt, es, fr, de, it

        /// The language's name in itself, for the menu.
        public var nativeName: String {
            switch self {
            case .en: return "English"
            case .pt: return "Português"
            case .es: return "Español"
            case .fr: return "Français"
            case .de: return "Deutsch"
            case .it: return "Italiano"
            }
        }
    }

    public enum Key: CaseIterable {
        case ready, reviewing, applied, paused, noPermission, noIssues, fixOne, fixMany, failed, noResponse, stats
        case pause, resume, checkNow, engine, customCommand, writingLanguages, matchSystem, interfaceLanguage
        case systemDefault, editVocabulary, addToVocabulary, addedToVocabulary, alreadyInVocabulary, nothingSelected
        case accessibility, launchAtLogin, launchAtLoginApprove, openConfig, reloadConfig, openLog, quit
        case apply, dismiss
    }

    public let language: Language

    public init(_ language: Language) { self.language = language }

    /// `override` comes from the config (a code or empty); otherwise the first
    /// supported language in the system's preferred list wins, then English.
    public static func detect(override: String, preferred: [String] = Locale.preferredLanguages) -> Language {
        if let l = Language(rawValue: override.lowercased()) { return l }
        for code in preferred {
            if let l = Language(rawValue: String(code.prefix(2)).lowercased()) { return l }
        }
        return .en
    }

    public func string(_ key: Key) -> String {
        L10n.table[key]?[language] ?? L10n.table[key]?[.en] ?? "\(key)"
    }

    private func fill(_ key: Key, _ values: [String: String]) -> String {
        values.reduce(string(key)) { $0.replacingOccurrences(of: "{\($1.key)}", with: $1.value) }
    }

    // Status
    public var ready: String { string(.ready) }
    public var reviewing: String { string(.reviewing) }
    public var applied: String { string(.applied) }
    public var paused: String { string(.paused) }
    public var noPermission: String { string(.noPermission) }
    public var noResponse: String { string(.noResponse) }
    public func noIssues(ms: Int) -> String { fill(.noIssues, ["ms": "\(ms)"]) }
    public func fixes(_ n: Int) -> String { fill(n == 1 ? .fixOne : .fixMany, ["n": "\(n)"]) }
    public func fixes(_ n: Int, ms: Int) -> String { "\(fixes(n)) (\(ms) ms)" }
    public func failed(_ reason: String) -> String { fill(.failed, ["x": reason]) }
    public func stats(reviews: Int, applied: Int) -> String { fill(.stats, ["r": "\(reviews)", "a": "\(applied)"]) }
    public func added(_ term: String) -> String { fill(.addedToVocabulary, ["x": term]) }
    public func alreadyThere(_ term: String) -> String { fill(.alreadyInVocabulary, ["x": term]) }
    public var nothingSelected: String { string(.nothingSelected) }

    // Menu
    public var pause: String { string(.pause) }
    public var resume: String { string(.resume) }
    public var checkNow: String { string(.checkNow) + "  ⌃⌥R" }
    public var engine: String { string(.engine) }
    public var customCommand: String { string(.customCommand) }
    public var writingLanguages: String { string(.writingLanguages) }
    public var matchSystem: String { string(.matchSystem) }
    public var interfaceLanguage: String { string(.interfaceLanguage) }
    public var systemDefault: String { string(.systemDefault) }
    public var editVocabulary: String { string(.editVocabulary) }
    public var addToVocabulary: String { string(.addToVocabulary) + "  ⌃⌥V" }
    public var accessibility: String { string(.accessibility) }
    public var launchAtLogin: String { string(.launchAtLogin) }
    public var launchAtLoginApprove: String { string(.launchAtLoginApprove) }
    public var openConfig: String { string(.openConfig) }
    public var reloadConfig: String { string(.reloadConfig) }
    public var openLog: String { string(.openLog) }
    public var quit: String { string(.quit) }

    // Suggestion card
    public var apply: String { string(.apply) + "  ⌃⌥G" }
    public var dismiss: String { string(.dismiss) }
    public func cardHeader(_ n: Int) -> String { "BABELPEN · " + fixes(n).uppercased(with: Locale(identifier: language.rawValue)) }

    // swiftlint:disable line_length
    static let table: [Key: [Language: String]] = [
        .ready: [.en: "Ready", .pt: "Pronto", .es: "Listo", .fr: "Prêt", .de: "Bereit", .it: "Pronto"],
        .reviewing: [.en: "Reviewing…", .pt: "Revisando…", .es: "Revisando…", .fr: "Relecture…", .de: "Wird geprüft…", .it: "Revisione…"],
        .applied: [.en: "Applied", .pt: "Aplicado", .es: "Aplicado", .fr: "Appliqué", .de: "Übernommen", .it: "Applicato"],
        .paused: [.en: "Paused", .pt: "Pausado", .es: "En pausa", .fr: "En pause", .de: "Pausiert", .it: "In pausa"],
        .noPermission: [.en: "Needs Accessibility permission", .pt: "Precisa da permissão de Acessibilidade", .es: "Falta el permiso de Accesibilidad", .fr: "Autorisation d’accessibilité requise", .de: "Bedienungshilfen-Zugriff erforderlich", .it: "Serve il permesso di Accessibilità"],
        .noIssues: [.en: "No issues ({ms} ms)", .pt: "Sem correções ({ms} ms)", .es: "Sin errores ({ms} ms)", .fr: "Aucune faute ({ms} ms)", .de: "Keine Fehler ({ms} ms)", .it: "Nessun errore ({ms} ms)"],
        .fixOne: [.en: "{n} fix", .pt: "{n} correção", .es: "{n} corrección", .fr: "{n} correction", .de: "{n} Korrektur", .it: "{n} correzione"],
        .fixMany: [.en: "{n} fixes", .pt: "{n} correções", .es: "{n} correcciones", .fr: "{n} corrections", .de: "{n} Korrekturen", .it: "{n} correzioni"],
        .failed: [.en: "Failed ({x}). Try ⌃⌥R", .pt: "Falhou ({x}). Tente ⌃⌥R", .es: "Falló ({x}). Prueba ⌃⌥R", .fr: "Échec ({x}). Essayez ⌃⌥R", .de: "Fehlgeschlagen ({x}). Versuche ⌃⌥R", .it: "Non riuscito ({x}). Prova ⌃⌥R"],
        .noResponse: [.en: "no response", .pt: "sem resposta", .es: "sin respuesta", .fr: "pas de réponse", .de: "keine Antwort", .it: "nessuna risposta"],
        .stats: [.en: "{r} reviews, {a} applied", .pt: "{r} revisões, {a} aplicadas", .es: "{r} revisiones, {a} aplicadas", .fr: "{r} relectures, {a} appliquées", .de: "{r} Prüfungen, {a} übernommen", .it: "{r} revisioni, {a} applicate"],
        .pause: [.en: "Pause", .pt: "Pausar", .es: "Pausar", .fr: "Mettre en pause", .de: "Pausieren", .it: "Metti in pausa"],
        .resume: [.en: "Resume", .pt: "Retomar", .es: "Reanudar", .fr: "Reprendre", .de: "Fortsetzen", .it: "Riprendi"],
        .checkNow: [.en: "Check Now", .pt: "Revisar agora", .es: "Revisar ahora", .fr: "Relire maintenant", .de: "Jetzt prüfen", .it: "Controlla ora"],
        .engine: [.en: "AI Engine", .pt: "Motor de IA", .es: "Motor de IA", .fr: "Moteur d’IA", .de: "KI-Engine", .it: "Motore IA"],
        .customCommand: [.en: "Custom command", .pt: "Comando próprio", .es: "Comando propio", .fr: "Commande personnalisée", .de: "Eigener Befehl", .it: "Comando personalizzato"],
        .writingLanguages: [.en: "Writing Languages", .pt: "Idiomas de escrita", .es: "Idiomas de escritura", .fr: "Langues d’écriture", .de: "Schreibsprachen", .it: "Lingue di scrittura"],
        .matchSystem: [.en: "Match System", .pt: "Iguais ao sistema", .es: "Igual que el sistema", .fr: "Comme le système", .de: "Wie im System", .it: "Come il sistema"],
        .interfaceLanguage: [.en: "Interface Language", .pt: "Idioma da interface", .es: "Idioma de la interfaz", .fr: "Langue de l’interface", .de: "Sprache der Oberfläche", .it: "Lingua dell’interfaccia"],
        .systemDefault: [.en: "System Default", .pt: "Padrão do sistema", .es: "Predeterminado del sistema", .fr: "Par défaut du système", .de: "Systemstandard", .it: "Predefinita di sistema"],
        .editVocabulary: [.en: "Edit Vocabulary…", .pt: "Editar vocabulário…", .es: "Editar vocabulario…", .fr: "Modifier le vocabulaire…", .de: "Vokabular bearbeiten…", .it: "Modifica vocabolario…"],
        .addToVocabulary: [.en: "Add Selection to Vocabulary", .pt: "Adicionar seleção ao vocabulário", .es: "Añadir selección al vocabulario", .fr: "Ajouter la sélection au vocabulaire", .de: "Auswahl zum Vokabular hinzufügen", .it: "Aggiungi selezione al vocabolario"],
        .addedToVocabulary: [.en: "Added “{x}” to vocabulary", .pt: "“{x}” adicionado ao vocabulário", .es: "“{x}” añadido al vocabulario", .fr: "« {x} » ajouté au vocabulaire", .de: "„{x}“ zum Vokabular hinzugefügt", .it: "“{x}” aggiunto al vocabolario"],
        .alreadyInVocabulary: [.en: "“{x}” is already in vocabulary", .pt: "“{x}” já está no vocabulário", .es: "“{x}” ya está en el vocabulario", .fr: "« {x} » est déjà dans le vocabulaire", .de: "„{x}“ ist schon im Vokabular", .it: "“{x}” è già nel vocabolario"],
        .nothingSelected: [.en: "Select a word first", .pt: "Selecione uma palavra antes", .es: "Selecciona una palabra primero", .fr: "Sélectionnez d’abord un mot", .de: "Zuerst ein Wort markieren", .it: "Seleziona prima una parola"],
        .accessibility: [.en: "Accessibility Permission…", .pt: "Permissão de Acessibilidade…", .es: "Permiso de Accesibilidad…", .fr: "Autorisation d’accessibilité…", .de: "Bedienungshilfen-Zugriff…", .it: "Permesso di Accessibilità…"],
        .launchAtLogin: [.en: "Launch at Login", .pt: "Abrir no login", .es: "Abrir al iniciar sesión", .fr: "Ouvrir à la connexion", .de: "Beim Anmelden öffnen", .it: "Apri al login"],
        .launchAtLoginApprove: [.en: "Launch at Login (approve in Settings)", .pt: "Abrir no login (aprovar em Ajustes)", .es: "Abrir al iniciar sesión (aprobar en Ajustes)", .fr: "Ouvrir à la connexion (à approuver dans Réglages)", .de: "Beim Anmelden öffnen (in Einstellungen erlauben)", .it: "Apri al login (approva in Impostazioni)"],
        .openConfig: [.en: "Open Config File…", .pt: "Abrir configuração…", .es: "Abrir configuración…", .fr: "Ouvrir la configuration…", .de: "Konfiguration öffnen…", .it: "Apri configurazione…"],
        .reloadConfig: [.en: "Reload Config", .pt: "Recarregar configuração", .es: "Recargar configuración", .fr: "Recharger la configuration", .de: "Konfiguration neu laden", .it: "Ricarica configurazione"],
        .openLog: [.en: "Open Log", .pt: "Abrir log", .es: "Abrir registro", .fr: "Ouvrir le journal", .de: "Protokoll öffnen", .it: "Apri log"],
        .quit: [.en: "Quit Babelpen", .pt: "Sair do Babelpen", .es: "Salir de Babelpen", .fr: "Quitter Babelpen", .de: "Babelpen beenden", .it: "Esci da Babelpen"],
        .apply: [.en: "Apply", .pt: "Aplicar", .es: "Aplicar", .fr: "Appliquer", .de: "Übernehmen", .it: "Applica"],
        .dismiss: [.en: "Dismiss", .pt: "Ignorar", .es: "Descartar", .fr: "Ignorer", .de: "Verwerfen", .it: "Ignora"],
    ]
    // swiftlint:enable line_length
}
