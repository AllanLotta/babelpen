import AppKit
import Carbon
import ServiceManagement

/// Plain-text log at ~/Library/Logs/Revisor.log. Only timings and counts,
/// never the text you type.
enum Log {
    static let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Revisor.log")
    private static let formatter = ISO8601DateFormatter()

    static func write(_ message: String) {
        let line = "\(formatter.string(from: Date())) \(message)\n"
        let data = Data(line.utf8)
        FileHandle.standardError.write(data)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: url)
        }
    }
}

/// Global hotkeys through Carbon: they work in any app and the keystroke is
/// swallowed, so ⌃⌥G never reaches the app you're typing in.
enum HotKeys {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var refs: [EventHotKeyRef?] = []
    private static var installed = false

    static func register(id: UInt32, keyCode: Int, modifiers: Int, _ handler: @escaping () -> Void) {
        if !installed {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var hotKey = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                  nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
                DispatchQueue.main.async { HotKeys.handlers[hotKey.id]?() }
                return noErr
            }, 1, &spec, nil, nil)
            installed = true
        }
        handlers[id] = handler
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x5256_5352), id: id),
                            GetApplicationEventTarget(), 0, &ref)
        refs.append(ref)
    }
}

/// Launch at login through SMAppService (macOS 13+). Off by default.
enum LoginItem {
    private static let wantedKey = "launchAtLogin"
    private static let teamKey = "loginItemTeam"

    static var status: SMAppService.Status { SMAppService.mainApp.status }
    static var isWanted: Bool { UserDefaults.standard.bool(forKey: wantedKey) }

    /// Re-applies the user's choice on launch. If the app was re-signed by a
    /// different team, re-registers so Login Items shows the current developer.
    static func sync() {
        guard isWanted else { return }
        let service = SMAppService.mainApp
        let team = signingTeam() ?? "adhoc"
        do {
            if service.status == .enabled, UserDefaults.standard.string(forKey: teamKey) != team { try service.unregister() }
            if service.status != .enabled { try service.register() }
            UserDefaults.standard.set(team, forKey: teamKey)
        } catch {
            Log.write("login item: \(error)")
        }
    }

    static func toggle() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
                UserDefaults.standard.set(false, forKey: wantedKey)
            } else {
                try service.register()
                UserDefaults.standard.set(true, forKey: wantedKey)
                if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            Log.write("login item: \(error)")
        }
    }

    private static func signingTeam() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }
}
