import Foundation

struct CLIError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Runs `claude -p` (Claude Code CLI) headlessly. Auth = your Claude Pro login (`claude` → /login).
final class ClaudeCLI: @unchecked Sendable {
    static let shared = ClaudeCLI()

    private let lock = NSLock()
    private var cachedExecutable: String?
    private var cachedShellPATH: String?

    // MARK: - Public

    func run(text: String, mode: CheckMode, instructions: String?, model: String, cliPath: String, timeout: TimeInterval = 180) async throws -> String {
        let exe = try resolveExecutable(override: cliPath)

        let process = Process()
        process.executableURL = exe
        process.arguments = [
            "-p",
            "--output-format", "json",
            "--model", model,
            "--system-prompt", Prompt.system(for: mode, instructions: instructions),
            "--tools", "",                // no tools: pure text in, text out
            "--strict-mcp-config",        // skip loading your MCP servers (faster start)
            "--disable-slash-commands",   // skip skills/commands discovery
            "--no-session-persistence",   // don't litter ~/.claude with sessions
        ]

        var env = ProcessInfo.processInfo.environment
        env["PATH"] = shellPATH()
        // If an API key is present the CLI bills the API instead of your Pro plan.
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")
        process.environment = env

        // Neutral cwd so no project CLAUDE.md / settings get loaded.
        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grammar-check-cwd", isDirectory: true)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        process.currentDirectoryURL = workDir

        let inPipe = Pipe(), outPipe = Pipe(), errPipe = Pipe()
        process.standardInput = inPipe
        process.standardOutput = outPipe
        process.standardError = errPipe

        let flags = RunFlags()
        let input = Data(Prompt.user(text).utf8)

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    if flags.cancelled {
                        cont.resume(throwing: CancellationError())
                        return
                    }
                    do {
                        try process.run()
                    } catch {
                        cont.resume(throwing: CLIError("Failed to launch Claude CLI at \(exe.path): \(error.localizedDescription)"))
                        return
                    }

                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak process] in
                        if let process, process.isRunning {
                            flags.timedOut = true
                            process.terminate()
                        }
                    }

                    // Prompt goes through stdin: no argv length/escaping limits.
                    let writer = inPipe.fileHandleForWriting
                    try? writer.write(contentsOf: input)
                    try? writer.close()

                    // Drain stderr concurrently so neither pipe buffer can fill and deadlock.
                    let errBox = DataBox()
                    let group = DispatchGroup()
                    group.enter()
                    DispatchQueue.global().async {
                        errBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
                        group.leave()
                    }
                    let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                    group.wait()
                    process.waitUntilExit()

                    cont.resume(with: Result {
                        try Self.parse(out: outData, err: errBox.data, status: process.terminationStatus, flags: flags)
                    })
                }
            }
        } onCancel: {
            flags.cancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    func resolveExecutable(override: String) throws -> URL {
        let fm = FileManager.default

        if !override.isEmpty {
            let p = (override as NSString).expandingTildeInPath
            guard fm.isExecutableFile(atPath: p) else { throw CLIError("Claude CLI not found or not executable at \(p)") }
            return URL(fileURLWithPath: p)
        }

        lock.lock()
        let cached = cachedExecutable
        lock.unlock()
        if let cached, fm.isExecutableFile(atPath: cached) { return URL(fileURLWithPath: cached) }

        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",        // native installer
            "\(home)/.claude/local/claude",     // legacy local install
            "/opt/homebrew/bin/claude",         // Homebrew (Apple Silicon)
            "/usr/local/bin/claude",
        ]
        var found = candidates.first(where: { fm.isExecutableFile(atPath: $0) })
        if found == nil, let p = loginShell("command -v claude"), fm.isExecutableFile(atPath: p) {
            found = p // e.g. npm global under nvm
        }
        guard let found else {
            throw CLIError("Claude CLI not found. Install Claude Code, run `claude` once in Terminal and log in with your Pro account, or set the path in Settings.")
        }

        lock.lock(); cachedExecutable = found; lock.unlock()
        return URL(fileURLWithPath: found)
    }

    // MARK: - Private

    /// GUI apps get a minimal PATH; the CLI (especially an npm install) needs `node` etc.
    private func shellPATH() -> String {
        lock.lock()
        if let c = cachedShellPATH { lock.unlock(); return c }
        lock.unlock()

        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let path = loginShell("printf %s \"$PATH\"") ?? fallback
        let result = path.isEmpty ? fallback : path

        lock.lock(); cachedShellPATH = result; lock.unlock()
        return result
    }

    /// Runs a command in an interactive login zsh (loads .zprofile and .zshrc) and returns its output.
    /// Markers isolate the value from any banner text printed by shell startup files.
    private func loginShell(_ command: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-ilc", "printf '__GC__'; \(command); printf '__GC__'"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        let s = String(decoding: data, as: UTF8.self)
        let parts = s.components(separatedBy: "__GC__")
        guard parts.count >= 3 else { return nil }
        let value = parts[parts.count - 2].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private struct CLIResult: Decodable {
        let result: String?
        let is_error: Bool?
        let subtype: String?
    }

    private static func parse(out: Data, err: Data, status: Int32, flags: RunFlags) throws -> String {
        if flags.cancelled { throw CancellationError() }
        if flags.timedOut { throw CLIError("Claude CLI timed out.") }

        let errText = String(decoding: err, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

        guard let decoded = try? JSONDecoder().decode(CLIResult.self, from: out) else {
            let outText = String(decoding: out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            let detail = errText.isEmpty ? outText : errText
            throw CLIError("Claude CLI failed (exit \(status)).\n\(detail.isEmpty ? "No output." : detail)")
        }

        if decoded.is_error == true || status != 0 {
            let detail = decoded.result ?? decoded.subtype ?? errText
            throw CLIError("Claude CLI error: \(detail)")
        }

        guard let result = decoded.result else { throw CLIError("Claude CLI returned no result.") }
        return Prompt.extract(result)
    }
}

private final class DataBox: @unchecked Sendable {
    var data = Data()
}

private final class RunFlags: @unchecked Sendable {
    var cancelled = false
    var timedOut = false
}
