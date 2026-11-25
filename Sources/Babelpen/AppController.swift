import AppKit
import ApplicationServices
import Carbon
import BabelpenCore

/// The draft in the focused field and what Babelpen has to offer for it.
struct Suggestion {
    let element: AXUIElement
    let pid: pid_t
    let source: String
    /// The proofreading fix, nil when there was nothing to fix.
    let fixed: String?
    let ops: [Diff.Op]
    /// Language of the draft (on-device guess), nil when unsure.
    let detected: String?
    /// Card header when there's no fix: "Written in Portuguese", "Rewrite".
    let title: String
    /// The rewrite or translation on display, if any.
    var rewrite: (action: Rewrite, text: String)?

    /// What Apply pastes.
    var replacement: String? { rewrite?.text ?? fixed }
}

/// The menu bar app. Every 0.35 s it reads the focused text field of the
/// frontmost app; once you stop typing it asks the AI engine for a corrected
/// version and shows the difference next to the field. From the same card you
/// can ask for a rewrite or a translation. Outside text fields it watches what
/// you select and offers to translate it.
final class AppController: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private var config: Config { store.config }
    private var l10n = L10n(.en)
    private var engine: AIEngine!
    private var assistant: AIEngine!
    private let panel = SuggestionPanel()
    private let selectionPanel = SuggestionPanel()

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let stateLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var stateText = ""
    private var stateIcon = "✎"

    private var enabled = true
    private var trusted = false
    private var lastTrustCheck = Date.distantPast
    private var webEnabledPIDs = Set<pid_t>()

    // Drafts
    private var currentElement: AXUIElement?
    private var currentBundleID: String?
    private var lastText = ""
    private var lastChangeAt = Date()
    private var lastChecked: String?
    private var checking = false
    private var forceNext = false
    private var suggestion: Suggestion?
    private var rewriteToken = 0
    /// The field where you dismissed the translation offer: no more offers there until you leave it.
    private var offerDismissedIn: AXUIElement?
    private var reviews = 0, applied = 0

    // Selected text
    private enum SelectionCard { case none, chip, working, explanation }
    private var selectionCard = SelectionCard.none
    private var lastSelection = ""
    private var selectionChangedAt = Date()
    private var selectionAnchor = CGRect.zero
    /// Selection that already got a chip or a translation, so it doesn't pop up again.
    private var handledSelection = ""
    private var explanation: String?
    private var explainToken = 0

    /// Demo/recording helper: auto-apply suggestions after N seconds.
    private let demoAutoApply = Double(ProcessInfo.processInfo.environment["BABELPEN_DEMO_AUTO_APPLY"] ?? "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let error = store.load() { Log.write(error) }
        l10n = L10n(L10n.detect(override: config.interfaceLanguage))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        stateLine.isEnabled = false

        panel.onPrimary = { [weak self] in self?.apply() }
        panel.onSecondary = { [weak self] in self?.dismiss() }
        panel.onAction = { [weak self] id in
            guard let action = Rewrite(rawValue: id) else { return }
            self?.runRewrite(action)
        }
        selectionPanel.onAction = { [weak self] _ in
            guard let self else { return }
            self.explain(self.handledSelection, anchor: self.selectionAnchor)
        }
        selectionPanel.onPrimary = { [weak self] in self?.copyExplanation() }
        selectionPanel.onSecondary = { [weak self] in self?.hideSelection() }

        HotKeys.register(id: 1, keyCode: kVK_ANSI_G, modifiers: controlKey | optionKey) { [weak self] in self?.apply() }
        HotKeys.register(id: 2, keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey) { [weak self] in self?.checkNow() }
        HotKeys.register(id: 3, keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) { [weak self] in self?.addSelectionToVocabulary() }
        HotKeys.register(id: 4, keyCode: kVK_ANSI_E, modifiers: controlKey | optionKey) { [weak self] in self?.rewriteField() }
        HotKeys.register(id: 5, keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey) { [weak self] in self?.translateNow() }
        HotKeys.register(id: 6, keyCode: kVK_ANSI_B, modifiers: controlKey | optionKey) { [weak self] in self?.showMenuAtPointer() }
        _ = store.vocabulary() // creates vocabulary.txt with instructions on first run

        makeEngine()
        trusted = AX.isTrusted(prompt: true)
        Log.write("start trusted=\(trusted) engine=\(engine.displayName)")
        LoginItem.sync()
        setState("✎", l10n.ready)

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appSwitched), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        // .common mode: keep watching while a menu is open, too.
        let timer = Timer(timeInterval: 0.35, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer, forMode: .common)
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine?.shutdown()
        assistant?.shutdown()
    }

    private func makeEngine() {
        engine?.shutdown()
        assistant?.shutdown()
        engine = EngineFactory.proofreader(config)
        assistant = EngineFactory.assistant(config)
        for e in [engine!, assistant!] { e.onLog = { Log.write("[\($0.hasPrefix("[") ? "" : "engine")] \($0)") } }
        engine.warmUp()
        checking = false
        rebuildMenu()
    }

    // MARK: - Loop

    private func tick() {
        guard enabled else { return }
        if !trusted {
            if Date().timeIntervalSince(lastTrustCheck) > 2 {
                lastTrustCheck = Date()
                trusted = AX.isTrusted(prompt: false)
                if trusted { Log.write("accessibility granted"); setState("✎", l10n.ready) }
            }
            if !trusted { setState("✎⚠", l10n.noPermission); return }
        }
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid() else { return }
        if let id = front.bundleIdentifier, config.ignoredApps.contains(id) { resetFocus(); hideSelection(); return }
        let pid = front.processIdentifier
        if !webEnabledPIDs.contains(pid) {
            AX.enableWebAccessibility(pid: pid, bundleID: front.bundleIdentifier)
            webEnabledPIDs.insert(pid)
        }
        let focused = AX.focusedElement(pid: pid)
        guard let element = focused, AX.isTextInput(element), let text = AX.value(element) else {
            leaveField()
            trackSelection(pid: pid, focused: focused, deep: true)
            return
        }
        // Text selected elsewhere on the page while the caret sits in a field
        // (the field's own selection is your text, not someone else's).
        if (AX.selectedRange(element)?.length ?? 0) == 0 { trackSelection(pid: pid, focused: element, deep: false) }

        let now = Date()
        if currentElement.map({ !CFEqual($0, element) }) ?? true {
            enterField(element, text: text, bundleID: front.bundleIdentifier)
            return
        }
        if text != lastText {
            lastText = text
            lastChangeAt = now
            if suggestion?.source != text { hidePanel() }
            return
        }
        if checking || panel.isVisible { return }
        if !forceNext, now.timeIntervalSince(lastChangeAt) < config.debounceSeconds || text == lastChecked { return }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= config.minCharacters, trimmed.count <= config.maxCharacters,
              trimmed.contains(where: \.isLetter) else {
            lastChecked = text
            return
        }
        forceNext = false
        review(text, element: element, pid: pid)
    }

    private func enterField(_ element: AXUIElement, text: String, bundleID: String?) {
        currentElement = element
        currentBundleID = bundleID
        lastText = text
        lastChangeAt = Date()
        lastChecked = nil
        offerDismissedIn = nil
        hidePanel()
    }

    private func review(_ text: String, element: AXUIElement, pid: pid_t) {
        checking = true
        lastChecked = text
        reviews += 1
        setState("✎…", l10n.reviewing)
        let started = Date()
        engine.ask(Prompt.userMessage(text, context: promptContext())) { [weak self] raw in
            guard let self else { return }
            self.checking = false
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            guard let raw, let parsed = Prompt.parseFixed(raw) else {
                Log.write("review failed after \(ms)ms (\(raw == nil ? "no answer" : "unparsed answer"))")
                self.setState("✎⚠", self.l10n.failed(self.engine.fatalReason ?? self.l10n.noResponse))
                self.lastChecked = nil
                return
            }
            let fixed = Prompt.keepEdges(source: text, fixed: parsed)
            guard let current = self.currentElement, CFEqual(current, element), self.lastText == text else {
                Log.write("stale answer after \(ms)ms, dropped")
                self.setState("✎", self.l10n.ready)
                return
            }
            let detected = LanguageGuess.detect(text, hints: self.writingLanguages)
            if fixed == text {
                Log.write("ok \(ms)ms chars=\(text.count) fixes=0")
                self.setState("✎✓", self.l10n.noIssues(ms: ms))
                if self.shouldOfferTranslation(text, detected: detected, element: element) {
                    let name = Languages.name(detected ?? "", in: self.l10n.language.rawValue)
                    self.showDraft(Suggestion(element: element, pid: pid, source: text, fixed: nil, ops: [],
                                              detected: detected, title: self.l10n.header(self.l10n.writtenIn(name))))
                }
                return
            }
            let ops = Diff.diff(text, fixed)
            let count = Diff.changeCount(ops)
            Log.write("ok \(ms)ms chars=\(text.count) fixes=\(count)")
            self.setState("✎\(count)", self.l10n.fixes(count, ms: ms))
            self.showDraft(Suggestion(element: element, pid: pid, source: text, fixed: fixed, ops: ops,
                                      detected: detected, title: self.l10n.cardHeader(count)))
            if let delay = self.demoAutoApply {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() }
            }
        }
    }

    /// A draft written in another language than the one you translate into.
    private func shouldOfferTranslation(_ text: String, detected: String?, element: AXUIElement) -> Bool {
        guard config.offerTranslation, let detected, detected != translateTo,
              text.filter(\.isLetter).count >= 15 else { return false }
        if let id = currentBundleID, config.offerTranslationIgnoredApps.contains(id) { return false }
        if let dismissed = offerDismissedIn, CFEqual(dismissed, element) { return false }
        return true
    }

    // MARK: - Draft card

    private func showDraft(_ s: Suggestion, working: Rewrite? = nil) {
        suggestion = s
        guard let anchor = draftAnchor(s.element) else { return }
        panel.show(draftCard(s, working: working), anchor: anchor)
        assistant.warmUp()
    }

    /// Small fields (chat composers, inputs): the card sits right below or above
    /// the whole field so it never covers the text. Big fields (email bodies):
    /// next to the caret line.
    private func draftAnchor(_ element: AXUIElement) -> CGRect? {
        let field = AX.frame(element)
        let caret = AX.caretRect(element)
        if let f = field, f.height <= 260 || caret == nil { return f }
        return caret
    }

    private func draftCard(_ s: Suggestion, working: Rewrite?) -> Card {
        let ui = l10n.language.rawValue
        var card = Card(header: s.title, secondary: l10n.dismiss)
        card.actions = [
            (Rewrite.improve.rawValue, l10n.improve),
            (Rewrite.formal.rawValue, l10n.formal),
            (Rewrite.casual.rawValue, l10n.casual),
            (Rewrite.translate.rawValue, l10n.translateInto(Languages.name(translationTarget(s), in: ui))),
        ]
        if let working {
            card.body = DiffRenderer.text(working == .translate ? l10n.translating : l10n.rewriting, dim: true)
            card.activeAction = working.rawValue
        } else if let r = s.rewrite {
            card.header = l10n.header(rewriteTitle(r.action, s))
            card.body = r.action == .translate ? DiffRenderer.text(r.text)
                                               : DiffRenderer.render(Diff.compact(Diff.diff(s.source, r.text)))
            card.activeAction = r.action.rawValue
            card.primary = l10n.apply
        } else if s.fixed != nil {
            card.body = DiffRenderer.render(Diff.compact(s.ops))
            card.primary = l10n.apply
        }
        return card
    }

    private func rewriteTitle(_ action: Rewrite, _ s: Suggestion) -> String {
        switch action {
        case .improve: return l10n.improvedHeader
        case .formal: return l10n.formalHeader
        case .casual: return l10n.casualHeader
        case .translate: return l10n.translatedHeader(Languages.name(translationTarget(s), in: l10n.language.rawValue))
        }
    }

    private func runRewrite(_ action: Rewrite) {
        guard let s = suggestion else { return }
        rewriteToken += 1
        let token = rewriteToken
        showDraft(s, working: action)
        let target = Languages.name(translationTarget(s), in: "en")
        let started = Date()
        assistant.ask(Assist.rewriteMessage(action, text: s.source, targetLanguage: target, context: promptContext())) { [weak self] raw in
            guard let self, token == self.rewriteToken, var current = self.suggestion,
                  CFEqual(current.element, s.element), current.source == s.source, self.lastText == s.source else { return }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            guard let raw, let result = Assist.parseResult(raw), !result.isEmpty else {
                Log.write("\(action.rawValue) failed after \(ms)ms")
                self.setState("✎⚠", self.l10n.failed(self.assistant.fatalReason ?? self.l10n.noResponse))
                self.showDraft(current)
                return
            }
            Log.write("\(action.rawValue) ok \(ms)ms chars=\(s.source.count)")
            current.rewrite = (action, Prompt.keepEdges(source: s.source, fixed: result))
            self.showDraft(current)
        }
    }

    // MARK: - Selected text

    /// Shows a small "Translate" button when you select text (in a message, an
    /// email, a page) written in another language than the one you read best.
    private func trackSelection(pid: pid_t, focused: AXUIElement?, deep: Bool) {
        guard config.translateSelection, NSEvent.pressedMouseButtons == 0 else { return }
        let selection = AX.selection(pid: pid, focused: focused, deep: deep)
        let text = selection?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let now = Date()
        if text != lastSelection {
            lastSelection = text
            selectionChangedAt = now
            // A chip belongs to its selection; a translation stays until you
            // close it or select something else.
            if selectionCard == .chip || (!text.isEmpty && text != handledSelection) { hideSelection() }
            return
        }
        guard !text.isEmpty, selectionCard == .none, text != handledSelection,
              now.timeIntervalSince(selectionChangedAt) >= 0.3, text.count <= config.maxCharacters,
              text.contains(where: \.isLetter) else { return }
        handledSelection = text
        if LanguageGuess.detect(text, hints: writingLanguages + [readingLanguage], minLetters: 4) == readingLanguage { return }
        selectionAnchor = selection?.bounds ?? AX.mouseAnchor()
        selectionCard = .chip
        selectionPanel.show(Card(actions: [("translate", l10n.translateChip)], compact: true), anchor: selectionAnchor)
        assistant.warmUp()
    }

    private func explain(_ text: String, anchor: CGRect) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        explainToken += 1
        let token = explainToken
        handledSelection = text
        selectionAnchor = anchor
        selectionCard = .working
        let ui = l10n.language.rawValue
        let reading = readingLanguage
        let detected = LanguageGuess.detect(text, hints: writingLanguages + [reading], minLetters: 4)
        let header: String
        if let detected, detected != reading {
            header = l10n.header(Languages.name(detected, in: ui) + " → " + Languages.name(reading, in: ui))
        } else {
            header = l10n.header(l10n.translatedHeader(Languages.name(reading, in: ui)))
        }
        selectionPanel.show(Card(header: header, body: DiffRenderer.text(l10n.translating, dim: true), secondary: l10n.close),
                            anchor: anchor)
        let started = Date()
        let message = Assist.explainMessage(text, readingLanguage: Languages.name(reading, in: "en"), context: promptContext())
        assistant.ask(message) { [weak self] raw in
            guard let self, token == self.explainToken, self.selectionCard == .working else { return }
            let ms = Int(Date().timeIntervalSince(started) * 1000)
            self.selectionCard = .explanation
            guard let raw, let result = Assist.parseExplanation(raw) else {
                Log.write("explain failed after \(ms)ms")
                let reason = "⚠ " + (self.assistant.fatalReason ?? self.l10n.noResponse)
                self.selectionPanel.show(Card(header: header, body: DiffRenderer.text(reason, dim: true), secondary: self.l10n.close),
                                         anchor: anchor)
                return
            }
            Log.write("explain ok \(ms)ms chars=\(text.count)")
            self.explanation = result.translation
            self.selectionPanel.show(Card(header: header, body: DiffRenderer.text(result.translation), note: result.note,
                                          primary: self.l10n.copy, secondary: self.l10n.close), anchor: anchor)
        }
    }

    private func copyExplanation() {
        guard let text = explanation else { return }
        Clipboard.copy(text)
        hideSelection()
        setState("✎✓", l10n.copied)
    }

    private func hideSelection() {
        selectionPanel.hide()
        selectionCard = .none
        explainToken += 1
    }

    // MARK: - Languages

    private var writingLanguages: [String] { Languages.effective(config.languages) }
    private var readingLanguage: String { LanguagePlan.reading(configured: config.readingLanguage, interface: l10n.language.rawValue) }
    private var translateTo: String {
        LanguagePlan.translateTo(configured: config.translateTo, writing: writingLanguages, reading: readingLanguage)
    }
    private func translationTarget(_ s: Suggestion) -> String {
        LanguagePlan.target(detected: s.detected, translateTo: translateTo, reading: readingLanguage)
    }

    /// Languages, note and vocabulary sent with each request. Read fresh every
    /// time, so edits to config.json or vocabulary.txt apply immediately.
    private func promptContext() -> PromptContext {
        PromptContext(languages: writingLanguages.map { Languages.name($0, in: "en") },
                      about: config.about,
                      vocabulary: store.vocabulary())
    }

    // MARK: - Actions

    @objc private func apply() {
        guard let s = suggestion, let replacement = s.replacement else { return }
        // The paste goes to the frontmost app, so it must still be the one the
        // suggestion belongs to.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == s.pid,
              let current = AX.value(s.element), current == s.source else {
            Log.write("apply skipped: text changed")
            hidePanel()
            return
        }
        TextReplacer.replaceAll(in: s.element, current: s.source, with: replacement)
        applied += 1
        lastChecked = replacement
        lastChangeAt = Date() // the paste lands a moment later; don't re-review the old text meanwhile
        Log.write("applied \(s.rewrite?.action.rawValue ?? "fix")")
        hidePanel()
        setState("✎✓", l10n.applied)
    }

    private func dismiss() {
        if let s = suggestion, s.fixed == nil, s.rewrite == nil { offerDismissedIn = s.element }
        lastChecked = suggestion?.source ?? lastChecked
        hidePanel()
        setState("✎", l10n.ready)
    }

    @objc private func checkNow() {
        hidePanel()
        lastChecked = nil
        forceNext = true
        lastChangeAt = .distantPast
    }

    /// The focused text field of the frontmost app, if it has some text.
    private func focusedDraft() -> (element: AXUIElement, pid: pid_t, text: String)? {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(),
              !(front.bundleIdentifier.map(config.ignoredApps.contains) ?? false),
              let element = AX.focusedElement(pid: front.processIdentifier), AX.isTextInput(element),
              let text = AX.value(element), text.contains(where: \.isLetter) else { return nil }
        if currentElement.map({ !CFEqual($0, element) }) ?? true {
            enterField(element, text: text, bundleID: front.bundleIdentifier)
        }
        return (element, front.processIdentifier, text)
    }

    /// ⌃⌥E: the rewrite buttons for the current field, even when there's nothing to fix.
    @objc private func rewriteField() {
        guard let draft = focusedDraft() else { setState(stateIcon, l10n.clickTextField); return }
        if let s = suggestion, panel.isVisible, CFEqual(s.element, draft.element), s.source == draft.text { return }
        lastText = draft.text
        lastChecked = draft.text
        showDraft(Suggestion(element: draft.element, pid: draft.pid, source: draft.text, fixed: nil, ops: [],
                             detected: LanguageGuess.detect(draft.text, hints: writingLanguages),
                             title: l10n.header(l10n.rewriteHeader)))
    }

    /// ⌃⌥T: translates the selected text (someone else's), or else your draft.
    @objc private func translateNow() {
        guard let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(),
              !(front.bundleIdentifier.map(config.ignoredApps.contains) ?? false) else { return }
        let pid = front.processIdentifier
        let focused = AX.focusedElement(pid: pid)
        let inField = focused.map(AX.isTextInput) ?? false
        if let selection = AX.selection(pid: pid, focused: focused, deep: !inField) {
            explain(selection.text, anchor: selection.bounds ?? AX.mouseAnchor())
            return
        }
        if inField, focusedDraft() != nil {
            rewriteField()
            runRewrite(.translate)
            return
        }
        // Apps that don't expose their selection: copy it.
        Clipboard.copySelection { [weak self] text in
            guard let self else { return }
            if let text, text.contains(where: \.isLetter) {
                self.explain(text, anchor: AX.mouseAnchor())
            } else {
                self.setState(self.stateIcon, self.l10n.nothingToTranslate)
            }
        }
    }

    /// ⌃⌥B: the Babelpen menu at the mouse pointer. On a crowded menu bar
    /// (MacBooks with a notch) macOS hides status items that don't fit.
    private func showMenuAtPointer() {
        rebuildMenu()
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    @objc private func togglePause() {
        enabled.toggle()
        if enabled { setState("✎", l10n.ready) } else { hidePanel(); hideSelection(); setState("✎⏸", l10n.paused) }
        rebuildMenu()
    }

    @objc private func selectEngine(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let provider = Config.Provider(rawValue: raw),
              provider != config.provider else { return }
        store.update { $0.provider = provider }
        Log.write("engine -> \(provider.rawValue)")
        makeEngine()
        setState("✎", l10n.ready)
    }

    @objc private func toggleWritingLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        store.update { $0.languages = Languages.toggle(code, in: $0.languages) }
        Log.write("writing languages -> \(Languages.effective(config.languages).joined(separator: ","))")
        rebuildMenu()
    }

    @objc private func matchSystemLanguages() {
        store.update { $0.languages = [] }
        rebuildMenu()
    }

    @objc private func selectTranslateTo(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        store.update { $0.translateTo = code }
        rebuildMenu()
    }

    @objc private func toggleOfferTranslation() {
        store.update { $0.offerTranslation.toggle() }
        rebuildMenu()
    }

    @objc private func toggleTranslateSelection() {
        store.update { $0.translateSelection.toggle() }
        if !config.translateSelection { hideSelection() }
        rebuildMenu()
    }

    @objc private func selectInterfaceLanguage(_ sender: NSMenuItem) {
        let code = sender.representedObject as? String ?? ""
        store.update { $0.interfaceLanguage = code }
        l10n = L10n(L10n.detect(override: code))
        stateText = l10n.ready
        rebuildMenu()
    }

    @objc private func editVocabulary() {
        _ = store.vocabulary()
        NSWorkspace.shared.open(store.vocabularyURL)
    }

    /// ⌃⌥V: adds the selected word in the frontmost app to vocabulary.txt.
    @objc private func addSelectionToVocabulary() {
        var selection: String?
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != getpid(),
           let element = AX.focusedElement(pid: front.processIdentifier) {
            selection = AX.attribute(element, kAXSelectedTextAttribute)
        }
        guard let term = selection.flatMap(Vocabulary.normalize) else {
            setState(stateIcon, l10n.nothingSelected)
            return
        }
        if store.addToVocabulary(term) {
            Log.write("vocabulary +1 (\(store.vocabulary().count) terms)")
            setState("✎✓", l10n.added(term))
        } else {
            setState(stateIcon, l10n.alreadyThere(term))
        }
    }

    @objc private func openAccessibilitySettings() {
        _ = AX.isTrusted(prompt: true)
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleLoginItem() {
        LoginItem.toggle()
        rebuildMenu()
    }

    @objc private func openConfig() {
        store.save()
        NSWorkspace.shared.open(store.url)
    }

    @objc private func reloadConfig() {
        if let error = store.load() { Log.write(error) }
        l10n = L10n(L10n.detect(override: config.interfaceLanguage))
        makeEngine()
        setState("✎", l10n.ready)
        Log.write("config reloaded")
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    @objc private func appSwitched() {
        resetFocus()
        hideSelection()
    }

    private func leaveField() {
        currentElement = nil
        hidePanel()
    }

    private func resetFocus() { leaveField() }

    private func hidePanel() {
        panel.hide()
        suggestion = nil
        rewriteToken += 1
    }

    // MARK: - Menu

    private func setState(_ icon: String, _ text: String) {
        stateIcon = icon
        stateText = text
        statusItem?.button?.title = icon
        stateLine.title = "\(text)  ·  \(l10n.stats(reviews: reviews, applied: applied))"
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(stateLine)
        menu.addItem(.separator())
        menu.addItem(item(enabled ? l10n.pause : l10n.resume, #selector(togglePause)))
        menu.addItem(item(l10n.checkNow, #selector(checkNow)))
        menu.addItem(item(l10n.rewriteMenu, #selector(rewriteField)))
        menu.addItem(item(l10n.translateMenu, #selector(translateNow)))

        let engines = NSMenu()
        let choices: [(Config.Provider, String)] = [(.claude, "Claude Code"), (.codex, "Codex"), (.command, l10n.customCommand)]
        for (provider, title) in choices {
            let entry = item(title, #selector(selectEngine(_:)))
            entry.representedObject = provider.rawValue
            entry.state = provider == config.provider ? .on : .off
            if provider == .command, config.command.isEmpty { entry.isEnabled = false; entry.action = nil }
            engines.addItem(entry)
        }
        menu.addItem(submenu(l10n.engine, engines))

        // Writing languages: the system's by default, any combination you like.
        let writing = NSMenu()
        let match = item(l10n.matchSystem, #selector(matchSystemLanguages))
        match.state = config.languages.isEmpty ? .on : .off
        writing.addItem(match)
        writing.addItem(.separator())
        let active = Languages.effective(config.languages)
        let ui = l10n.language.rawValue
        let codes = active.filter { !Languages.common.contains($0) } + Languages.common
        for code in codes.sorted(by: { (active.contains($0) ? 0 : 1, Languages.name($0, in: ui)) < (active.contains($1) ? 0 : 1, Languages.name($1, in: ui)) }) {
            let entry = item(Languages.name(code, in: ui), #selector(toggleWritingLanguage(_:)))
            entry.representedObject = code
            entry.state = active.contains(code) ? .on : .off
            writing.addItem(entry)
        }
        menu.addItem(submenu(l10n.writingLanguages, writing))

        let translate = NSMenu()
        let target = translateTo
        let targets = [target] + active.filter { $0 != target } + Languages.common.filter { $0 != target && !active.contains($0) }
        for code in targets {
            let entry = item(Languages.name(code, in: ui), #selector(selectTranslateTo(_:)))
            entry.representedObject = code
            entry.state = code == target ? .on : .off
            translate.addItem(entry)
            if code == targets.first { translate.addItem(.separator()) }
        }
        menu.addItem(submenu(l10n.translateToMenu, translate))
        let offer = item(l10n.offerTranslationMenu, #selector(toggleOfferTranslation))
        offer.state = config.offerTranslation ? .on : .off
        menu.addItem(offer)
        let onSelection = item(l10n.translateSelectionMenu, #selector(toggleTranslateSelection))
        onSelection.state = config.translateSelection ? .on : .off
        menu.addItem(onSelection)

        let interface = NSMenu()
        let system = item(l10n.systemDefault, #selector(selectInterfaceLanguage(_:)))
        system.representedObject = ""
        system.state = config.interfaceLanguage.isEmpty ? .on : .off
        interface.addItem(system)
        interface.addItem(.separator())
        for language in L10n.Language.allCases {
            let entry = item(language.nativeName, #selector(selectInterfaceLanguage(_:)))
            entry.representedObject = language.rawValue
            entry.state = config.interfaceLanguage == language.rawValue ? .on : .off
            interface.addItem(entry)
        }
        menu.addItem(submenu(l10n.interfaceLanguage, interface))

        menu.addItem(.separator())
        menu.addItem(item(l10n.addToVocabulary, #selector(addSelectionToVocabulary)))
        menu.addItem(item(l10n.editVocabulary, #selector(editVocabulary)))

        menu.addItem(.separator())
        menu.addItem(item(l10n.accessibility, #selector(openAccessibilitySettings)))
        let login = item(LoginItem.status == .requiresApproval ? l10n.launchAtLoginApprove : l10n.launchAtLogin,
                         #selector(toggleLoginItem))
        login.state = LoginItem.status == .enabled ? .on : .off
        menu.addItem(login)
        menu.addItem(item(l10n.openConfig, #selector(openConfig)))
        menu.addItem(item(l10n.reloadConfig, #selector(reloadConfig)))
        menu.addItem(item(l10n.openLog, #selector(openLog)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: l10n.quit, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        setState(stateIcon, stateText.isEmpty ? l10n.ready : stateText)
    }

    private func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        entry.submenu = menu
        return entry
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        return entry
    }
}
