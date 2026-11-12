import Foundation

/// One item printed by a script, before it becomes a `ResultItem`.
struct ScriptItem: Sendable, Equatable {
    var title: String
    var subtitle: String?
    var icon: String?
    var actionType: String?
    var actionValue: String?
    var copy: String?
}

/// What running a script gave.
enum RunOutcome: Sendable {
    case items([ScriptItem])
    /// `short` goes in the row title, `detail` (stderr, full message) is what the row copies.
    case failure(short: String, detail: String)
    case cancelled
}

/// Everything needed to run an integration, captured on the main actor.
struct RunSpec: Sendable {
    let id: String
    let folder: URL
    let manifest: IntegrationManifest
}

/// Runs integration scripts with `/bin/zsh -lc` off the main thread, with a timeout and an output cap.
enum IntegrationRunner {
    static let timeout: TimeInterval = 10
    static let maxOutput = 5 * 1024 * 1024

    /// Cancelling the calling task terminates the process.
    static func run(_ spec: RunSpec, query: String) async -> RunOutcome {
        let execution = Execution()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(returning: execution.run(spec, query: query))
                }
            }
        } onCancel: {
            execution.cancel()
        }
    }

    /// `'text'` for the shell, with embedded quotes escaped.
    static func shellQuote(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: - Parsing

    static func parse(stdout: Data) -> Result<[ScriptItem], ParseFailure> {
        let trimmed = stdout.drop(while: { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 })
        guard !trimmed.isEmpty else { return .failure(.empty) }
        guard let object = try? JSONSerialization.jsonObject(with: Data(trimmed), options: [.fragmentsAllowed]) else {
            return .failure(.invalidJSON)
        }
        let list: [Any]
        if let dict = object as? [String: Any] {
            if let error = dict["error"] {
                let message = (error as? String) ?? (error as? [String: Any])?["message"] as? String ?? "\(error)"
                return .failure(.scriptError(message))
            }
            guard let items = dict["items"] as? [Any] else { return .failure(.invalidJSON) }
            list = items
        } else if let array = object as? [Any] {
            list = array
        } else {
            return .failure(.invalidJSON)
        }
        return .success(list.compactMap(item))
    }

    private static func item(_ any: Any) -> ScriptItem? {
        guard let dict = any as? [String: Any], let title = text(dict["title"]), !title.isEmpty else { return nil }
        var item = ScriptItem(title: title, subtitle: text(dict["subtitle"]), icon: text(dict["icon"]),
                              copy: text(dict["copy"]))
        if let action = dict["action"] as? [String: Any] {
            item.actionType = text(action["type"])?.lowercased()
            item.actionValue = text(action["value"])
        }
        return item
    }

    private static func text(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    enum ParseFailure: Error {
        case empty, invalidJSON
        case scriptError(String)
    }
}

/// One process run. Reference type so the cancellation handler can reach the process.
private final class Execution: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        let running = process
        lock.unlock()
        if let running, running.isRunning { running.terminate() }
    }

    private var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    func run(_ spec: RunSpec, query: String) -> RunOutcome {
        if isCancelled { return .cancelled }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", spec.manifest.command + " " + IntegrationRunner.shellQuote(query)]
        process.currentDirectoryURL = spec.folder
        var environment = ProcessInfo.processInfo.environment
        environment.merge(IntegrationVariables.environment(integration: spec.id, manifest: spec.manifest)) { _, new in new }
        environment["SAMUNE_QUERY"] = query
        environment["SAMUNE_INTEGRATION_DIR"] = spec.folder.path
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stdout = Buffer(limit: IntegrationRunner.maxOutput)
        let stderr = Buffer(limit: 64 * 1024)
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            return .failure(short: tr("no se pudo ejecutar"), detail: error.localizedDescription)
        }
        lock.lock()
        self.process = process
        let cancelledEarly = cancelled
        lock.unlock()
        if cancelledEarly { process.terminate() }

        // Readers drain both pipes so a big output never blocks the script.
        let readers = DispatchGroup()
        for (pipe, buffer) in [(outPipe, stdout), (errPipe, stderr)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                let handle = pipe.fileHandleForReading
                while let chunk = try? handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                    if !buffer.append(chunk), buffer === stdout, process.isRunning {
                        process.terminate()
                    }
                }
                readers.leave()
            }
        }

        var timedOut = false
        if exited.wait(timeout: .now() + IntegrationRunner.timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
        }
        // A background child may keep the pipes open; don't wait for it forever.
        _ = readers.wait(timeout: .now() + 1)

        if isCancelled { return .cancelled }
        let errText = String(decoding: stderr.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if timedOut {
            return .failure(short: tr("tardó más de %d s", Int(IntegrationRunner.timeout)), detail: errText)
        }
        if stdout.overflowed {
            return .failure(short: tr("la salida supera los 5 MB"), detail: errText)
        }

        let status = process.terminationStatus
        switch IntegrationRunner.parse(stdout: stdout.data) {
        case .success(let items) where status == 0:
            return .items(items)
        case .failure(.scriptError(let message)):
            return .failure(short: Self.firstLine(message), detail: message)
        case .failure(.invalidJSON) where status == 0:
            let sample = String(decoding: stdout.data.prefix(2000), as: UTF8.self)
            return .failure(short: tr("la salida no es JSON válido"), detail: [errText, sample].filter { !$0.isEmpty }.joined(separator: "\n\n"))
        case .failure(.empty) where status == 0:
            return .failure(short: tr("el script no imprimió nada"), detail: errText)
        default:
            let short = errText.isEmpty ? tr("terminó con el código %d", Int(status)) : Self.firstLine(errText)
            let detail = errText.isEmpty ? short : errText
            return .failure(short: short, detail: detail)
        }
    }

    private static func firstLine(_ text: String) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > 120 ? String(line.prefix(120)) + "…" : line
    }
}

/// Thread-safe byte buffer that stops growing at `limit`.
private final class Buffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()
    private var over = false
    private let limit: Int

    init(limit: Int) { self.limit = limit }

    /// False once the limit has been passed (the extra bytes are dropped).
    func append(_ chunk: Data) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !over else { return false }
        if storage.count + chunk.count > limit {
            storage.append(chunk.prefix(limit - storage.count))
            over = true
            return false
        }
        storage.append(chunk)
        return true
    }

    var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
    var overflowed: Bool { lock.lock(); defer { lock.unlock() }; return over }
}
