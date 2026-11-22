import AppKit
import ApplicationServices

/// Replaces the whole text of a field.
///
/// Setting AXValue directly is ignored by most web and React editors, so we do
/// what a person would: select everything (through AX, ⌘A as a fallback) and
/// paste. Works in native, web and Electron fields, and keeps the app's own ⌘Z.
/// The clipboard is restored right after.
enum TextReplacer {
    static func replaceAll(in element: AXUIElement, current: String, with text: String) {
        let pasteboard = NSPasteboard.general
        let saved: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            var data: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types { if let d = item.data(forType: type) { data[type] = d } }
            return data
        } ?? []

        let length = (current as NSString).length
        let selected = AX.setSelectedRange(element, CFRange(location: 0, length: length))
            && (AX.selectedRange(element).map { $0.location == 0 && $0.length == length } ?? false)
        if !selected { sendKey(0x00, flags: .maskCommand) } // ⌘A

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            sendKey(0x09, flags: .maskCommand) // ⌘V
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                pasteboard.clearContents()
                let items = saved.map { data -> NSPasteboardItem in
                    let item = NSPasteboardItem()
                    for (type, d) in data { item.setData(d, forType: type) }
                    return item
                }
                if !items.isEmpty { pasteboard.writeObjects(items) }
            }
        }
    }

    static func sendKey(_ code: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
