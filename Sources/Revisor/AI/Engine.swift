import Foundation
import RevisorCore

/// Something that proofreads text through a local AI CLI. Revisor never talks
/// to an API with a key: it drives the CLI you're already logged into, so the
/// work runs on your existing plan.
protocol ProofreadEngine: AnyObject {
    var displayName: String { get }
    /// Set when the engine can't work at all (CLI missing, API key detected…).
    var fatalReason: String? { get }
    var onLog: ((String) -> Void)? { get set }
    func warmUp()
    /// Calls back on the main queue with the model's raw answer, or nil on failure.
    func proofread(_ text: String, completion: @escaping (String?) -> Void)
    func shutdown()
}

enum EngineFactory {
    static func make(_ config: Config) -> ProofreadEngine {
        switch config.provider {
        case .claude:
            return ClaudeCodeEngine(model: config.model.isEmpty ? "haiku" : config.model,
                                    effort: config.effort, about: config.about)
        case .codex:
            return OneShotEngine.codex(model: config.model, effort: config.effort, about: config.about)
        case .command:
            return OneShotEngine.custom(command: config.command, about: config.about)
        }
    }
}

enum CLI {
    /// Apps launched from Finder get a minimal PATH, so look where CLIs usually live.
    static var searchPaths: [String] {
        let home = NSHomeDirectory()
        let fromEnv = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return fromEnv + ["/opt/homebrew/bin", "/usr/local/bin", "\(home)/.local/bin", "\(home)/.claude/local",
                          "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin", "/usr/bin", "/bin"]
    }

    static func find(_ name: String) -> String? {
        if name.hasPrefix("/") { return FileManager.default.isExecutableFile(atPath: name) ? name : nil }
        for dir in searchPaths {
            let path = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }

    /// Child environment built from an allowlist. API keys are never passed on,
    /// so the CLI always runs on your logged-in subscription, not on metered billing.
    static func environment(binary: String) -> [String: String] {
        let source = ProcessInfo.processInfo.environment
        var env: [String: String] = [:]
        for key in ["HOME", "USER", "LOGNAME", "LANG", "TMPDIR", "SHELL"] { env[key] = source[key] }
        env["HOME"] = env["HOME"] ?? NSHomeDirectory()
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        let binDir = (binary as NSString).deletingLastPathComponent
        env["PATH"] = ([binDir] + searchPaths).joined(separator: ":")
        // Claude Code: don't load project memory files or check for updates in this headless child.
        env["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        env["CLAUDE_CODE_DISABLE_AUTO_MEMORY"] = "1"
        env["DISABLE_AUTOUPDATER"] = "1"
        return env
    }

    static var scratchDirectory: URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("revisor")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
