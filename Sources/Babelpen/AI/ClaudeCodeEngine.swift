import Foundation
import BabelpenCore

/// Claude Code (`claude`) kept running in headless streaming mode:
/// `claude -p --input-format stream-json --output-format stream-json`.
///
/// Starting the CLI takes a few seconds; a warm process answers in under a
/// second with Haiku. Requests are answered in order, one `result` line each.
/// The process is recycled every `maxRequests` to keep its context small.
final class ClaudeCodeEngine: AIEngine {
    let displayName = "Claude Code"
    private(set) var fatalReason: String?
    var onLog: ((String) -> Void)?

    private let model: String
    private let effort: String
    private let system: String
    private let label: String
    private let maxRequests = 20
    private let timeout: TimeInterval = 25

    private var process: Process?
    private var input: FileHandle?
    private var buffer = Data()
    private var pending: [(id: Int, completion: (String?) -> Void)] = []
    private var served = 0
    private var nextID = 0

    init(model: String, effort: String, system: String, label: String) {
        self.model = model
        self.effort = effort
        self.system = system
        self.label = label
    }

    func warmUp() { if process == nil { start() } }

    func ask(_ text: String, completion: @escaping (String?) -> Void) {
        if fatalReason != nil { completion(nil); return }
        if process != nil, served >= maxRequests, pending.isEmpty { stopProcess() }
        if process == nil { start() }
        guard let input else { completion(nil); return }

        nextID += 1
        let id = nextID
        pending.append((id, completion))
        served += 1
        let message: [String: Any] = [
            "type": "user",
            "message": ["role": "user", "content": text],
            "parent_tool_use_id": NSNull(),
        ]
        var line = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
        line.append(0x0A)
        do { try input.write(contentsOf: line) } catch {
            log("write failed: \(error)")
            failAllAndStop()
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self, self.pending.contains(where: { $0.id == id }) else { return }
            self.log("timed out after \(Int(self.timeout))s, restarting")
            self.failAllAndStop()
        }
    }

    func shutdown() {
        let callbacks = pending
        pending.removeAll()
        stopProcess()
        callbacks.forEach { $0.completion(nil) }
    }

    // MARK: - Process

    private func start() {
        guard let binary = CLI.find("claude") else {
            fatalReason = "claude CLI not found"
            log("Claude Code CLI not found. Install it and run `claude` once to log in.")
            return
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: binary)
        var args = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                    "--model", model,
                    "--setting-sources", "", "--strict-mcp-config", "--disable-slash-commands",
                    "--system-prompt", system, "--tools", "", "--no-session-persistence"]
        if !effort.isEmpty { args += ["--effort", effort] }
        p.arguments = args
        p.environment = CLI.environment(binary: binary)
        p.currentDirectoryURL = CLI.scratchDirectory

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = errPipe
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.consume(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            guard let s = String(data: data, encoding: .utf8), !s.contains("unrecognized_model") else { return }
            DispatchQueue.main.async { self?.log("stderr: \(s.prefix(300))") }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self, self.process === proc else { return }
                self.log("claude exited (\(self.label), \(proc.terminationStatus))")
                self.failAllAndStop()
            }
        }
        do {
            try p.run()
            process = p
            input = inPipe.fileHandleForWriting
            log("claude started (\(label), pid \(p.processIdentifier), model \(model))")
        } catch {
            fatalReason = "could not start claude"
            log("could not start \(binary): \(error)")
        }
    }

    private func stopProcess() {
        process?.terminationHandler = nil
        process?.terminate()
        process = nil
        input = nil
        buffer.removeAll()
        served = 0
    }

    private func failAllAndStop() {
        let callbacks = pending
        pending.removeAll()
        stopProcess()
        callbacks.forEach { $0.completion(nil) }
    }

    private func consume(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = object["type"] as? String else { continue }
            switch type {
            case "system" where object["subtype"] as? String == "init":
                // Refuse to run on an API key: Babelpen is meant to use your plan.
                if let source = object["apiKeySource"] as? String, source != "none" {
                    fatalReason = "API key detected"
                    log("apiKeySource=\(source): refusing, Babelpen only runs on your Claude login")
                    failAllAndStop()
                    return
                }
            case "result":
                guard !pending.isEmpty else { continue }
                let request = pending.removeFirst()
                let isError = object["is_error"] as? Bool ?? false
                request.completion(isError ? nil : object["result"] as? String)
            default:
                continue
            }
        }
    }

    private func log(_ s: String) { onLog?(s) }
}
