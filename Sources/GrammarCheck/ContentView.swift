import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var checker: CheckerModel
    @ObservedObject private var presets = PresetStore.shared
    @AppStorage(Prefs.modeKey) private var modeRaw = Prefs.defaultMode.rawValue
    @State private var showChanges = true

    private var mode: CheckMode { CheckMode(rawValue: modeRaw) ?? Prefs.defaultMode }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                pane("Your text") {
                    TextEditor(text: $checker.input)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(8)
                }
                pane(showChanges ? "Suggestion — changes" : "Suggestion — editable") {
                    output
                }
            }
            Divider()
            footer
        }
        .onChange(of: showChanges) { _, nowShowing in
            if nowShowing { checker.refreshDiff() }
        }
    }

    @ViewBuilder
    private var output: some View {
        if checker.isRunning {
            ProgressView("Checking with Claude…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = checker.error {
            ScrollView {
                Text(error)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } else if !checker.hasResult {
            Text("Paste text on the left and press ⌘↩")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if showChanges {
            ScrollView {
                Text(TextDiff.attributed(checker.segments))
                    .font(.system(size: 14))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
        } else {
            TextEditor(text: $checker.corrected)
                .font(.system(size: 14))
                .scrollContentBackground(.hidden)
                .padding(8)
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            ModePicker()
            PresetPicker(store: presets)

            Toggle("Show changes", isOn: $showChanges)
                .toggleStyle(.switch)
                .controlSize(.small)

            Spacer()

            status

            if checker.isRunning {
                Button("Cancel") { checker.cancel() }
                    .keyboardShortcut(.escape, modifiers: [])
            }

            Button("Use as input") { checker.useResultAsInput() }
                .disabled(!checker.hasResult)

            Button("Copy result") { checker.copyResult() }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(!checker.hasResult)

            Button("Check") { checker.check(mode: mode, instructions: presets.selected?.instructions) }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(checker.isRunning || checker.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var status: some View {
        if checker.noChanges {
            Label("No changes needed", systemImage: "checkmark.circle")
                .foregroundStyle(.green)
                .font(.callout)
        } else if checker.hasResult {
            let n = TextDiff.changeCount(checker.segments)
            Text("\(n) change\(n == 1 ? "" : "s")" + (checker.elapsed.map { String(format: " · %.1fs", $0) } ?? ""))
                .foregroundStyle(.secondary)
                .font(.callout)
        }
    }

    private func pane<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            Divider()
            content()
                .background(Color(nsColor: .textBackgroundColor))
        }
        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
    }
}
