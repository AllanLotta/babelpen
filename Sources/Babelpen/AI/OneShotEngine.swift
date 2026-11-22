import Foundation
import BabelpenCore

/// Runs one CLI process per review: the prompt goes in on stdin, the answer
/// comes back on stdout (or in a file). Used for Codex and for any custom
/// command (Gemini CLI, Ollama, a local script…). Slower than the warm Claude
/// Code engine because each review pays the CLI's startup time.
final class OneShotEngine: ProofreadEngine {
    let displayName: String
    private(set) var fatalReason: String?
    var onLog: ((String) -> Void)?

    private let executable: String?
    private let baseArguments: [String]
    /// Codex writes its final message to a file (`-o`); custom commands use stdout.
    private let usesOutputFile: Bool
    private let timeout: TimeInterval = 45
    private var running: Process?

    private init(displayName: String, executable: String?, arguments: [String], usesOutputFile: Bool) {
        self.displayName = displayName
        self.executable = executable
        self.baseArguments = arguments
        self.usesOutputFile = usesOutputFile
        if executable == nil { fatalReason = "\(displayName) not found" }
    }

    /// OpenAI Codex CLI on your ChatGPT login: `codex exec`, read-only sandbox, ephemeral session.
    static func codex(model: String, effort: String) -> OneShotEngine {
        var args = ["exec", "--skip-git-repo-check", "--ephemeral", "-s", "read-only", "--color", "never"]
        if !effort.isEmpty { args += ["-c", "model_reasoning_effort=\(effort)"] }
        if !model.isEmpty { args += ["-m", model] }
        return OneShotEngine(displayName: "Codex", executable: CLI.find("codex"), arguments: args, usesOutputFile: true)
    }

    /// Any command that reads a prompt on stdin and prints the answer.
    static func custom(command: [String]) -> OneShotEngine {
        let name = command.first ?? ""
        return OneShotEngine(displayName: name.isEmpty ? "custom command" : name,
                             executable: name.isEmpty ? nil : CLI.find(name),
                             arguments: Array(command.dropFirst()), usesOutputFile: false)
    }

    func warmUp() {
        if let reason = fatalReason { log(reason) }
    }

    func proofread(_ text: String, context: PromptContext, completion: @escaping (String?) -> Void) {
        guard let executable, fatalReason == nil else { completion(nil); return }
        let outputFile = CLI.scratchDirectory.appendingPathComponent("answer-\(UUID().uuidString).txt")
        var args = baseArguments
        if usesOutputFile { args += ["-o", outputFile.path, "-"] }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        p.environment = CLI.environment(binary: executable)
        p.currentDirectoryURL = CLI.scratchDirectory
        let inPipe = Pipe(), outPipe = Pipe()
        p.standardInput = inPipe
        p.standardOutput = outPipe
        p.standardError = FileHandle.nullDevice

        var stdout = Data()
        let readQueue = DispatchQueue(label: "babelpen.oneshot.read")
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil; return }
            readQueue.sync { stdout.append(data) }
        }

        var finished = false
        let finish: (String?) -> Void = { [weak self] answer in
            DispatchQueue.main.async {
                guard !finished else { return }
                finished = true
                if self?.running === p { self?.running = nil }
                try? FileManager.default.removeItem(at: outputFile)
                completion(answer)
            }
        }
        p.terminationHandler = { [weak self] proc in
            // Give the stdout reader a moment to drain.
            readQueue.asyncAfter(deadline: .now() + 0.05) {
                let answer: String?
                if self?.usesOutputFile == true {
                    answer = try? String(contentsOf: outputFile, encoding: .utf8)
                } else {
                    answer = String(data: stdout, encoding: .utf8)
                }
                if proc.terminationStatus != 0 { self?.log("\(self?.displayName ?? "cli") exited \(proc.terminationStatus)") }
                finish(answer?.isEmpty == false ? answer : nil)
            }
        }
        do {
            try p.run()
            running = p
        } catch {
            log("could not start \(executable): \(error)")
            finish(nil)
            return
        }
        let prompt = Prompt.oneShot(text, context: context)
        try? inPipe.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
        try? inPipe.fileHandleForWriting.close()

        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard !finished else { return }
            self?.log("\(self?.displayName ?? "cli") timed out")
            p.terminate()
            finish(nil)
        }
    }

    func shutdown() {
        running?.terminate()
        running = nil
    }

    private func log(_ s: String) { onLog?(s) }
}
