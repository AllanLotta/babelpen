import AppKit
import ApplicationServices

/// Thin helpers over the macOS Accessibility API. This is how Babelpen reads
/// what you type in any app: the focused UI element and its AXValue.
enum AX {
    static func isTrusted(prompt: Bool) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    static func elementAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    static func focusedElement(pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return elementAttribute(app, kAXFocusedUIElementAttribute)
    }

    static let chromiumBrowsers: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.canary", "com.brave.Browser", "com.microsoft.edgemac",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// Chromium and Electron apps (Chrome, Slack, Discord…) only build their
    /// accessibility tree when an assistive app asks for it.
    static func enableWebAccessibility(pid: pid_t, bundleID: String?) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        if let id = bundleID, chromiumBrowsers.contains(id) {
            AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue)
        }
    }

    /// Editable text: text areas, text fields, combo/search boxes. Never secure fields.
    static func isTextInput(_ element: AXUIElement) -> Bool {
        let role: String = attribute(element, kAXRoleAttribute) ?? ""
        let subrole: String = attribute(element, kAXSubroleAttribute) ?? ""
        if subrole == kAXSecureTextFieldSubrole as String { return false }
        let textRoles = [kAXTextAreaRole as String, kAXTextFieldRole as String, kAXComboBoxRole as String, "AXSearchField"]
        guard textRoles.contains(role) else { return false }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let editable: Bool = attribute(element, "AXEditable") ?? false
        return settable.boolValue || editable || role == kAXTextAreaRole as String
    }

    static func value(_ element: AXUIElement) -> String? { attribute(element, kAXValueAttribute) }

    /// Element frame in global AX coordinates (origin at the top-left of the main screen).
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p: AXValue = attribute(element, kAXPositionAttribute),
              let s: AXValue = attribute(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        AXValueGetValue(p, .cgPoint, &point)
        AXValueGetValue(s, .cgSize, &size)
        return CGRect(origin: point, size: size)
    }

    static func selectedRange(_ element: AXUIElement) -> CFRange? {
        guard let v: AXValue = attribute(element, kAXSelectedTextRangeAttribute) else { return nil }
        var range = CFRange()
        return AXValueGetValue(v, .cfRange, &range) ? range : nil
    }

    @discardableResult
    static func setSelectedRange(_ element: AXUIElement, _ range: CFRange) -> Bool {
        var range = range
        guard let v = AXValueCreate(.cfRange, &range) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, v) == .success
    }

    /// Screen rect of the caret line (AX coordinates), when the app exposes it.
    static func caretRect(_ element: AXUIElement) -> CGRect? {
        guard let sel = selectedRange(element) else { return nil }
        let candidates = [CFRange(location: sel.location, length: 0),
                          CFRange(location: max(0, sel.location - 1), length: 1)]
        for var range in candidates {
            guard let rv = AXValueCreate(.cfRange, &range) else { continue }
            var out: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &out) == .success,
                let out, CFGetTypeID(out) == AXValueGetTypeID() else { continue }
            var rect = CGRect.zero
            if AXValueGetValue(out as! AXValue, .cgRect, &rect), rect.height > 0, rect.origin != .zero { return rect }
        }
        return nil
    }

    // MARK: - Selected text (read-only, anywhere)

    struct Selection {
        let text: String
        /// Screen rect of the selection (AX coordinates), when the app exposes it.
        let bounds: CGRect?
    }

    private static var webAreaCache: (pid: pid_t, at: Date, areas: [AXUIElement]) = (0, .distantPast, [])

    /// Text selected in the frontmost app: native controls (AXSelectedText), then
    /// web content in Chromium/Electron/WebKit (text markers on the AXWebArea
    /// around the focus, or any web area in the focused window).
    /// `deep` also searches the focused window for web areas (slower, cached).
    static func selection(pid: pid_t, focused: AXUIElement?, deep: Bool = true) -> Selection? {
        if let f = focused {
            if (attribute(f, kAXSubroleAttribute) as String?) == kAXSecureTextFieldSubrole as String { return nil }
            if let text: String = attribute(f, kAXSelectedTextAttribute), text.contains(where: { !$0.isWhitespace }) {
                return Selection(text: text, bounds: selectedBounds(f))
            }
            if let area = webArea(around: f), let s = markerSelection(area) { return s }
        }
        guard deep else { return nil }
        for area in webAreas(pid: pid) {
            if let s = markerSelection(area) { return s }
        }
        return nil
    }

    private static var ancestorCache: (element: AXUIElement, area: AXUIElement?)?

    /// The AXWebArea containing `element` (itself included), remembered per
    /// focused element so the tree is walked once, not on every tick.
    private static func webArea(around element: AXUIElement) -> AXUIElement? {
        if let cache = ancestorCache, CFEqual(cache.element, element) { return cache.area }
        var current: AXUIElement? = element
        var found: AXUIElement?
        for _ in 0..<40 {
            guard let e = current else { break }
            if (attribute(e, kAXRoleAttribute) as String?) == "AXWebArea" { found = e; break }
            current = elementAttribute(e, kAXParentAttribute)
        }
        ancestorCache = (element, found)
        return found
    }

    private static func markerSelection(_ area: AXUIElement) -> Selection? {
        var range: CFTypeRef?
        guard AXUIElementCopyAttributeValue(area, "AXSelectedTextMarkerRange" as CFString, &range) == .success,
              let range else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(area, "AXStringForTextMarkerRange" as CFString, range, &out) == .success,
              let text = out as? String, text.contains(where: { !$0.isWhitespace }) else { return nil }
        var bounds: CGRect?
        var b: CFTypeRef?
        if AXUIElementCopyParameterizedAttributeValue(area, "AXBoundsForTextMarkerRange" as CFString, range, &b) == .success,
           let b, CFGetTypeID(b) == AXValueGetTypeID() {
            var rect = CGRect.zero
            if AXValueGetValue(b as! AXValue, .cgRect, &rect), rect.width > 0, rect.height > 0 { bounds = rect }
        }
        return Selection(text: text, bounds: bounds)
    }

    private static func selectedBounds(_ element: AXUIElement) -> CGRect? {
        guard var range = selectedRange(element), range.length > 0, let rv = AXValueCreate(.cfRange, &range) else { return nil }
        var out: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element, kAXBoundsForRangeParameterizedAttribute as CFString, rv, &out) == .success,
            let out, CFGetTypeID(out) == AXValueGetTypeID() else { return nil }
        var rect = CGRect.zero
        return AXValueGetValue(out as! AXValue, .cgRect, &rect) && rect.width > 0 && rect.height > 0 ? rect : nil
    }

    /// Web areas of the app's focused window, cached for a few seconds (finding
    /// them walks the tree).
    private static func webAreas(pid: pid_t) -> [AXUIElement] {
        if webAreaCache.pid == pid, Date().timeIntervalSince(webAreaCache.at) < 3 { return webAreaCache.areas }
        var found: [AXUIElement] = []
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        if let window = elementAttribute(app, kAXFocusedWindowAttribute) {
            var queue: [(AXUIElement, Int)] = [(window, 0)]
            var visited = 0
            while !queue.isEmpty, visited < 400, found.count < 4 {
                let (element, depth) = queue.removeFirst()
                visited += 1
                if (attribute(element, kAXRoleAttribute) as String?) == "AXWebArea" { found.append(element); continue }
                guard depth < 14, let children: [AXUIElement] = attribute(element, kAXChildrenAttribute) else { continue }
                queue += children.map { ($0, depth + 1) }
            }
        }
        webAreaCache = (pid, Date(), found)
        return found
    }

    /// A small rect at the mouse pointer, in AX coordinates.
    static func mouseAnchor() -> CGRect {
        let p = NSEvent.mouseLocation
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: p.x - 8, y: mainHeight - p.y - 10, width: 16, height: 20)
    }

    /// AX global coordinates (top-left origin) → Cocoa screen coordinates (bottom-left origin).
    static func toCocoa(_ r: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }
}
