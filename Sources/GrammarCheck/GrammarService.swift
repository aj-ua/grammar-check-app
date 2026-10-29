import Foundation

/// Front door for checks: whitespace preservation + small in-memory LRU cache.
@MainActor
final class GrammarService {
    static let shared = GrammarService()

    private var cache: [String: String] = [:]
    private var order: [String] = []
    private let capacity = 40

    func correct(_ text: String, mode: CheckMode, instructions: String?) async throws -> String {
        // Send only the trimmed core; re-attach original leading/trailing whitespace,
        // so replacing a selection that ends with a newline keeps that newline.
        let lead = String(text.prefix(while: { $0.isWhitespace }))
        let rest = text.dropFirst(lead.count)
        let trailCount = rest.reversed().prefix(while: { $0.isWhitespace }).count
        let trail = String(rest.suffix(trailCount))
        let core = String(rest.dropLast(trailCount))
        guard !core.isEmpty else { return text }

        let model = Prefs.model
        let extra = instructions?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        // Preset text is part of the key: same text + different preset = different result.
        let key = "\(mode.rawValue)|\(model)|\(extra)|\u{1F}\(core)"

        if let hit = cache[key] {
            touch(key)
            return lead + hit + trail
        }

        let out = try await ClaudeCLI.shared.run(
            text: core, mode: mode, instructions: extra.isEmpty ? nil : extra,
            model: model, cliPath: Prefs.cliPath
        )
        let cleaned = out.trimmingCharacters(in: .whitespacesAndNewlines)

        cache[key] = cleaned
        touch(key)
        if order.count > capacity {
            let evicted = order.removeFirst()
            cache.removeValue(forKey: evicted)
        }
        return lead + cleaned + trail
    }

    private func touch(_ key: String) {
        if let i = order.firstIndex(of: key) { order.remove(at: i) }
        order.append(key)
    }
}
