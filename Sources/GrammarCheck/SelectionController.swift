import AppKit
import SwiftUI
import Carbon.HIToolbox

/// Secondary flow: ⌃⌥G in any app → copy selection → check → review panel → paste replacement.
@MainActor
final class SelectionController {
    static let shared = SelectionController()

    private var hotKey: HotKey?
    private var panel: NSPanel?
    private var previousApp: NSRunningApplication?
    private var task: Task<Void, Never>?
    private let state = ReviewState()

    func install() {
        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(controlKey | optionKey)) {
            SelectionController.shared.trigger()
        }
    }

    func trigger() {
        // Posting ⌘C / ⌘V into other apps requires Accessibility permission.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        guard AXIsProcessTrustedWithOptions(options) else { return }

        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            NSSound.beep() // our own window is focused: use the main window instead
            return
        }
        previousApp = front

        task?.cancel()
        task = Task { await self.captureAndCheck() }
    }

    private func captureAndCheck() async {
        await waitForModifierRelease()

        let pb = NSPasteboard.general
        let saved = Pasteboard.snapshot()
        let before = pb.changeCount

        Keys.post(CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        var text: String?
        for _ in 0..<40 {
            try? await Task.sleep(for: .milliseconds(20))
            if pb.changeCount != before {
                text = pb.string(forType: .string)
                break
            }
        }
        // Give the user's clipboard back right away; it's not needed while Claude runs.
        Pasteboard.restore(saved)

        guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state.fail(original: "", "No text selected, or the app didn't copy it.")
            showPanel()
            return
        }

        state.start(original: text)
        showPanel()
        await runCheck(text)
    }

    /// Re-run on the same captured text after mode/preset change in the panel.
    func recheck() {
        guard panel?.isVisible == true, !state.original.isEmpty else { return }
        let text = state.original
        task?.cancel()
        task = Task { await self.runCheck(text) }
    }

    private func runCheck(_ text: String) async {
        state.start(original: text)
        do {
            let out = try await GrammarService.shared.correct(
                text, mode: Prefs.mode, instructions: PresetStore.shared.selected?.instructions
            )
            try Task.checkCancellation()
            state.finish(corrected: out)
        } catch {
            if Task.isCancelled { return }
            state.fail(original: text, error.localizedDescription)
        }
    }

    func replace() {
        let text = state.corrected
        guard !text.isEmpty, let app = previousApp else { return }
        closePanel()

        Task {
            // Normally the source app is still frontmost (panel is non-activating);
            // re-activate only if the user switched apps meanwhile.
            if NSWorkspace.shared.frontmostApplication?.processIdentifier != app.processIdentifier {
                app.activate(options: [])
            }
            for _ in 0..<50 {
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier { break }
                try? await Task.sleep(for: .milliseconds(20))
            }
            // Let key focus return from the panel to the source app's window.
            try? await Task.sleep(for: .milliseconds(120))

            let saved = Pasteboard.snapshot()
            Pasteboard.setString(text)
            Keys.post(CGKeyCode(kVK_ANSI_V), flags: .maskCommand)
            // Target app reads the pasteboard asynchronously; restore after it has pasted.
            try? await Task.sleep(for: .milliseconds(500))
            Pasteboard.restore(saved)
        }
    }

    func copyResult() {
        guard !state.corrected.isEmpty else { return }
        Pasteboard.setString(state.corrected)
        closePanel()
    }

    func closePanel() {
        task?.cancel()
        task = nil
        panel?.orderOut(nil)
    }

    private func showPanel() {
        if panel == nil {
            // Non-activating panel (Spotlight-style): it takes keyboard focus without activating
            // the app, so the main window is NOT brought forward and the source app stays frontmost.
            let p = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 420),
                styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.title = "Grammar Check — Selection"
            p.level = .floating
            p.isReleasedWhenClosed = false
            p.hidesOnDeactivate = false        // app is never active in this flow; default would hide it
            p.becomesKeyOnlyIfNeeded = false   // take key focus so ↩ / Esc work immediately
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary] // show over full-screen apps
            p.contentView = NSHostingView(rootView: ReviewView(state: state))
            p.center()
            panel = p
        }
        panel?.makeKeyAndOrderFront(nil)
        panel?.orderFrontRegardless()
    }

    /// The hotkey's ⌃⌥ may still be held; a ⌘C posted now would arrive as ⌃⌥⌘C.
    private func waitForModifierRelease() async {
        let mask: CGEventFlags = [.maskControl, .maskAlternate, .maskCommand, .maskShift]
        for _ in 0..<50 {
            if CGEventSource.flagsState(.combinedSessionState).intersection(mask).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(20))
        }
    }
}

// MARK: - Review panel

@MainActor
final class ReviewState: ObservableObject {
    @Published var original = ""
    @Published var corrected = ""
    @Published var segments: [DiffSegment] = []
    @Published var isRunning = false
    @Published var error: String?

    func start(original: String) {
        self.original = original
        corrected = ""
        segments = []
        error = nil
        isRunning = true
    }

    func finish(corrected: String) {
        self.corrected = corrected
        segments = TextDiff.diff(old: original, new: corrected)
        isRunning = false
    }

    func fail(original: String, _ message: String) {
        self.original = original
        corrected = ""
        segments = []
        error = message
        isRunning = false
    }
}

struct ReviewView: View {
    @ObservedObject var state: ReviewState
    @ObservedObject private var presets = PresetStore.shared
    @AppStorage(Prefs.modeKey) private var modeRaw = Prefs.defaultMode.rawValue

    private var canApply: Bool {
        !state.isRunning && state.error == nil && !state.corrected.isEmpty && state.corrected != state.original
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if state.isRunning {
                    ProgressView("Checking with Claude…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = state.error {
                    ScrollView {
                        Text(error).foregroundStyle(.red).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }
                } else if state.corrected == state.original {
                    Label("No changes needed", systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        Text(TextDiff.attributed(state.segments))
                            .font(.system(size: 14))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))

            Divider()

            HStack {
                ModePicker()
                PresetPicker(store: presets)
                Spacer()
                Button("Close") { SelectionController.shared.closePanel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Copy") { SelectionController.shared.copyResult() }
                    .disabled(!canApply)
                Button("Replace") { SelectionController.shared.replace() }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(.borderedProminent)
                    .disabled(!canApply)
            }
            .padding(10)
        }
        .frame(minWidth: 620, minHeight: 260)
        .onChange(of: modeRaw) { _, _ in SelectionController.shared.recheck() }
        .onChange(of: presets.selectedID) { _, _ in SelectionController.shared.recheck() }
    }
}

// MARK: - Helpers

enum Keys {
    static func post(_ key: CGKeyCode, flags: CGEventFlags) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

enum Pasteboard {
    typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    /// Copies every item and type so images, rich text, files etc. survive the round trip.
    static func snapshot() -> Snapshot {
        (NSPasteboard.general.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    static func restore(_ snapshot: Snapshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        guard !snapshot.isEmpty else { return }
        let items = snapshot.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }

    static func setString(_ s: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }
}

/// Global hotkey via Carbon. Needs no permission (unlike event taps).
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let hotKey = Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { hotKey.action() } }
            return noErr
        }, 1, &spec, userData, &handlerRef)

        let id = EventHotKeyID(signature: OSType(0x4752_4D52), id: 1) // 'GRMR'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            NSLog("GrammarCheck: hotkey registration failed (\(status)); combination may be taken.")
        }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}
