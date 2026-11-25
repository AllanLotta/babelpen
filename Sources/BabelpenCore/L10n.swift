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
        case improve, formal, casual, translateInto, rewriting, translating, improvedHeader, formalHeader, casualHeader
        case translatedHeader, writtenIn, rewriteHeader, copy, copied, close, translateChip
        case rewriteMenu, translateMenu, translateToMenu, offerTranslationMenu, translateSelectionMenu
        case nothingToTranslate, clickTextField
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
    public func cardHeader(_ n: Int) -> String { header(fixes(n)) }
    public func header(_ text: String) -> String { "BABELPEN · " + text.uppercased(with: Locale(identifier: language.rawValue)) }

    // Rewrite and translate
    public var improve: String { "✨ " + string(.improve) }
    public var formal: String { string(.formal) }
    public var casual: String { string(.casual) }
    public func translateInto(_ languageName: String) -> String { fill(.translateInto, ["x": languageName]) }
    public var rewriting: String { string(.rewriting) }
    public var translating: String { string(.translating) }
    public var improvedHeader: String { string(.improvedHeader) }
    public var formalHeader: String { string(.formalHeader) }
    public var casualHeader: String { string(.casualHeader) }
    public func translatedHeader(_ languageName: String) -> String { fill(.translatedHeader, ["x": languageName]) }
    public func writtenIn(_ languageName: String) -> String { fill(.writtenIn, ["x": languageName]) }
    public var rewriteHeader: String { string(.rewriteHeader) }
    public var copy: String { string(.copy) }
    public var copied: String { string(.copied) }
    public var close: String { string(.close) }
    public var translateChip: String { "🌐 " + string(.translateChip) + "  ⌃⌥T" }
    public var rewriteMenu: String { string(.rewriteMenu) + "  ⌃⌥E" }
    public var translateMenu: String { string(.translateMenu) + "  ⌃⌥T" }
    public var translateToMenu: String { string(.translateToMenu) }
    public var offerTranslationMenu: String { string(.offerTranslationMenu) }
    public var translateSelectionMenu: String { string(.translateSelectionMenu) }
    public var nothingToTranslate: String { string(.nothingToTranslate) }
    public var clickTextField: String { string(.clickTextField) }

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
        .improve: [.en: "Improve", .pt: "Melhorar", .es: "Mejorar", .fr: "Améliorer", .de: "Verbessern", .it: "Migliora"],
        .formal: [.en: "Formal", .pt: "Formal", .es: "Formal", .fr: "Formel", .de: "Förmlich", .it: "Formale"],
        .casual: [.en: "Casual", .pt: "Casual", .es: "Casual", .fr: "Détendu", .de: "Locker", .it: "Informale"],
        .translateInto: [.en: "→ {x}", .pt: "→ {x}", .es: "→ {x}", .fr: "→ {x}", .de: "→ {x}", .it: "→ {x}"],
        .rewriting: [.en: "Rewriting…", .pt: "Reescrevendo…", .es: "Reescribiendo…", .fr: "Réécriture…", .de: "Wird umgeschrieben…", .it: "Riscrittura…"],
        .translating: [.en: "Translating…", .pt: "Traduzindo…", .es: "Traduciendo…", .fr: "Traduction…", .de: "Wird übersetzt…", .it: "Traduzione…"],
        .improvedHeader: [.en: "Improved", .pt: "Melhorado", .es: "Mejorado", .fr: "Amélioré", .de: "Verbessert", .it: "Migliorato"],
        .formalHeader: [.en: "More formal", .pt: "Mais formal", .es: "Más formal", .fr: "Plus formel", .de: "Förmlicher", .it: "Più formale"],
        .casualHeader: [.en: "More casual", .pt: "Mais casual", .es: "Más casual", .fr: "Plus détendu", .de: "Lockerer", .it: "Più informale"],
        .translatedHeader: [.en: "In {x}", .pt: "Em {x}", .es: "En {x}", .fr: "En {x}", .de: "Auf {x}", .it: "In {x}"],
        .writtenIn: [.en: "Written in {x}", .pt: "Escrito em {x}", .es: "Escrito en {x}", .fr: "Écrit en {x}", .de: "Auf {x} geschrieben", .it: "Scritto in {x}"],
        .rewriteHeader: [.en: "Rewrite", .pt: "Reescrever", .es: "Reescribir", .fr: "Réécrire", .de: "Umschreiben", .it: "Riscrivi"],
        .copy: [.en: "Copy", .pt: "Copiar", .es: "Copiar", .fr: "Copier", .de: "Kopieren", .it: "Copia"],
        .copied: [.en: "Copied", .pt: "Copiado", .es: "Copiado", .fr: "Copié", .de: "Kopiert", .it: "Copiato"],
        .close: [.en: "Close", .pt: "Fechar", .es: "Cerrar", .fr: "Fermer", .de: "Schließen", .it: "Chiudi"],
        .translateChip: [.en: "Translate", .pt: "Traduzir", .es: "Traducir", .fr: "Traduire", .de: "Übersetzen", .it: "Traduci"],
        .rewriteMenu: [.en: "Rewrite Field…", .pt: "Reescrever campo…", .es: "Reescribir campo…", .fr: "Réécrire le champ…", .de: "Feld umschreiben…", .it: "Riscrivi campo…"],
        .translateMenu: [.en: "Translate", .pt: "Traduzir", .es: "Traducir", .fr: "Traduire", .de: "Übersetzen", .it: "Traduci"],
        .translateToMenu: [.en: "Translate Drafts To", .pt: "Traduzir rascunhos para", .es: "Traducir borradores a", .fr: "Traduire les brouillons en", .de: "Entwürfe übersetzen nach", .it: "Traduci bozze in"],
        .offerTranslationMenu: [.en: "Offer Translation While Typing", .pt: "Oferecer tradução ao digitar", .es: "Ofrecer traducción al escribir", .fr: "Proposer la traduction en écrivant", .de: "Beim Schreiben Übersetzung anbieten", .it: "Proponi traduzione mentre scrivi"],
        .translateSelectionMenu: [.en: "Translate Button on Selected Text", .pt: "Botão de traduzir no texto selecionado", .es: "Botón de traducir en el texto seleccionado", .fr: "Bouton Traduire sur le texte sélectionné", .de: "Übersetzen-Knopf bei markiertem Text", .it: "Pulsante Traduci sul testo selezionato"],
        .nothingToTranslate: [.en: "Select some text first", .pt: "Selecione um texto antes", .es: "Selecciona un texto primero", .fr: "Sélectionnez d’abord du texte", .de: "Zuerst Text markieren", .it: "Seleziona prima del testo"],
        .clickTextField: [.en: "Click a text field first", .pt: "Clique num campo de texto antes", .es: "Haz clic en un campo de texto primero", .fr: "Cliquez d’abord dans un champ de texte", .de: "Zuerst in ein Textfeld klicken", .it: "Fai clic prima in un campo di testo"],
    ]
    // swiftlint:enable line_length
}
