import AppKit
import ApplicationServices
import Carbon
import BabelpenCore

struct Suggestion {
    let element: AXUIElement
    let pid: pid_t
    let source: String
    let fixed: String
}

/// The menu bar app. Every 0.35 s it reads the focused text field of the
/// frontmost app; once you stop typing it asks the AI engine for a corrected
/// version and shows the difference next to the field.
final class AppController: NSObject, NSApplicationDelegate {
    private let store = ConfigStore()
    private var config: Config { store.config }
    private var l10n = L10n(.en)
    private var engine: ProofreadEngine!
    private let panel = SuggestionPanel()

    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    private let stateLine = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private var stateText = ""
    private var stateIcon = "✎"

    private var enabled = true
    private var trusted = false
    private var lastTrustCheck = Date.distantPast
    private var webEnabledPIDs = Set<pid_t>()

    private var currentElement: AXUIElement?
    private var lastText = ""
    private var lastChangeAt = Date()
    private var lastChecked: String?
    private var checking = false
    private var forceNext = false
    private var suggestion: Suggestion?
    private var reviews = 0, applied = 0

    /// Demo/recording helper: auto-apply suggestions after N seconds.
    private let demoAutoApply = Double(ProcessInfo.processInfo.environment["BABELPEN_DEMO_AUTO_APPLY"] ?? "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let error = store.load() { Log.write(error) }
        l10n = L10n(L10n.detect(override: config.interfaceLanguage))
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = menu
        stateLine.isEnabled = false

        panel.setStrings(l10n)
        panel.onApply = { [weak self] in self?.apply() }
        panel.onDismiss = { [weak self] in self?.dismiss() }
        HotKeys.register(id: 1, keyCode: kVK_ANSI_G, modifiers: controlKey | optionKey) { [weak self] in self?.apply() }
        HotKeys.register(id: 2, keyCode: kVK_ANSI_R, modifiers: controlKey | optionKey) { [weak self] in self?.checkNow() }
        HotKeys.register(id: 3, keyCode: kVK_ANSI_V, modifiers: controlKey | optionKey) { [weak self] in self?.addSelectionToVocabulary() }
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

    func applicationWillTerminate(_ notification: Notification) { engine?.shutdown() }

    private func makeEngine() {
        engine?.shutdown()
        engine = EngineFactory.make(config)
        engine.onLog = { Log.write("[\($0.hasPrefix("[") ? "" : "engine")] \($0)") }
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
        if let id = front.bundleIdentifier, config.ignoredApps.contains(id) { resetFocus(); return }
        let pid = front.processIdentifier
        if !webEnabledPIDs.contains(pid) {
            AX.enableWebAccessibility(pid: pid, bundleID: front.bundleIdentifier)
            webEnabledPIDs.insert(pid)
        }
        guard let element = AX.focusedElement(pid: pid), AX.isTextInput(element),
              let text = AX.value(element) else { resetFocus(); return }

        let now = Date()
        if currentElement.map({ !CFEqual($0, element) }) ?? true {
            currentElement = element
            lastText = text
            lastChangeAt = now
            lastChecked = nil
            hidePanel()
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

    private func review(_ text: String, element: AXUIElement, pid: pid_t) {
        checking = true
        lastChecked = text
        reviews += 1
        setState("✎…", l10n.reviewing)
        let started = Date()
        engine.proofread(text, context: promptContext()) { [weak self] raw in
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
            if fixed == text {
                Log.write("ok \(ms)ms chars=\(text.count) fixes=0")
                self.setState("✎✓", self.l10n.noIssues(ms: ms))
                return
            }
            let ops = Diff.diff(text, fixed)
            let count = Diff.changeCount(ops)
            Log.write("ok \(ms)ms chars=\(text.count) fixes=\(count)")
            self.suggestion = Suggestion(element: element, pid: pid, source: text, fixed: fixed)
            self.setState("✎\(count)", self.l10n.fixes(count, ms: ms))
            self.showCard(ops: ops, count: count, element: element)
        }
    }

    /// Small fields (chat composers, inputs): the card sits right below or above
    /// the whole field so it never covers the text. Big fields (email bodies):
    /// next to the caret line.
    private func showCard(ops: [Diff.Op], count: Int, element: AXUIElement) {
        let field = AX.frame(element)
        let caret = AX.caretRect(element)
        let anchor: CGRect
        if let f = field, f.height <= 260 || caret == nil { anchor = f }
        else if let c = caret { anchor = c }
        else { return }
        panel.show(diff: DiffRenderer.render(Diff.compact(ops)), header: l10n.cardHeader(count), anchor: anchor)
        if let delay = demoAutoApply {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.apply() }
        }
    }

    /// Languages, note and vocabulary sent with each review. Read fresh every
    /// time, so edits to config.json or vocabulary.txt apply immediately.
    private func promptContext() -> PromptContext {
        PromptContext(languages: Languages.effective(config.languages).map { Languages.name($0, in: "en") },
                      about: config.about,
                      vocabulary: store.vocabulary())
    }

    // MARK: - Actions

    @objc private func apply() {
        guard let s = suggestion else { return }
        // The paste goes to the frontmost app, so it must still be the one the
        // suggestion belongs to.
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == s.pid,
              let current = AX.value(s.element), current == s.source else {
            Log.write("apply skipped: text changed")
            hidePanel()
            return
        }
        TextReplacer.replaceAll(in: s.element, current: s.source, with: s.fixed)
        applied += 1
        lastChecked = s.fixed
        lastChangeAt = Date() // the paste lands a moment later; don't re-review the old text meanwhile
        Log.write("applied")
        hidePanel()
        setState("✎✓", l10n.applied)
    }

    private func dismiss() {
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

    @objc private func togglePause() {
        enabled.toggle()
        if enabled { setState("✎", l10n.ready) } else { hidePanel(); setState("✎⏸", l10n.paused) }
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

    @objc private func selectInterfaceLanguage(_ sender: NSMenuItem) {
        let code = sender.representedObject as? String ?? ""
        store.update { $0.interfaceLanguage = code }
        l10n = L10n(L10n.detect(override: code))
        panel.setStrings(l10n)
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
        panel.setStrings(l10n)
        makeEngine()
        setState("✎", l10n.ready)
        Log.write("config reloaded")
    }

    @objc private func openLog() { NSWorkspace.shared.open(Log.url) }

    @objc private func appSwitched() { resetFocus() }

    private func resetFocus() {
        currentElement = nil
        hidePanel()
    }

    private func hidePanel() {
        panel.hide()
        suggestion = nil
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
