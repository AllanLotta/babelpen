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

    /// AX global coordinates (top-left origin) → Cocoa screen coordinates (bottom-left origin).
    static func toCocoa(_ r: CGRect) -> CGRect {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: r.minX, y: mainHeight - r.maxY, width: r.width, height: r.height)
    }
}
