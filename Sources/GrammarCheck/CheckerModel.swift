import SwiftUI

/// State for the main window (paste box → suggestion box).
@MainActor
final class CheckerModel: ObservableObject {
    @Published var input = ""
    @Published var corrected = ""
    @Published private(set) var segments: [DiffSegment] = []
    @Published private(set) var isRunning = false
    @Published private(set) var error: String?
    @Published private(set) var elapsed: Double?

    /// The input the current result was produced from (diff baseline).
    private(set) var source = ""
    private var task: Task<Void, Never>?

    var hasResult: Bool { !corrected.isEmpty && error == nil }
    var noChanges: Bool { hasResult && corrected == source }

    func check(mode: CheckMode, instructions: String?) {
        let text = input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        task?.cancel()
        isRunning = true
        error = nil
        elapsed = nil
        let started = Date()

        task = Task { [weak self] in
            do {
                let out = try await GrammarService.shared.correct(text, mode: mode, instructions: instructions)
                try Task.checkCancellation()
                guard let self else { return }
                self.source = text
                self.corrected = out
                self.segments = TextDiff.diff(old: text, new: out)
                self.elapsed = Date().timeIntervalSince(started)
            } catch {
                if Task.isCancelled { return }
                self?.error = error.localizedDescription
            }
            self?.isRunning = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    /// Call after the user edits the corrected text, before showing the diff again.
    func refreshDiff() {
        segments = TextDiff.diff(old: source, new: corrected)
    }

    func copyResult() {
        guard !corrected.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(corrected, forType: .string)
    }

    func useResultAsInput() {
        guard !corrected.isEmpty else { return }
        input = corrected
    }
}
