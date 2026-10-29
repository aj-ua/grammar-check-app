import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
            PresetsSettingsView()
                .tabItem { Label("Presets", systemImage: "list.bullet.rectangle") }
        }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @AppStorage(Prefs.modelKey) private var model = Prefs.defaultModel
    @AppStorage(Prefs.cliPathKey) private var cliPath = ""

    @State private var testOutput = ""
    @State private var testing = false

    var body: some View {
        Form {
            Section("Claude") {
                Picker("Model", selection: $model) {
                    Text("Sonnet — best balance").tag("sonnet")
                    Text("Haiku — fastest, lightest on limits").tag("haiku")
                    Text("Opus — slowest, heaviest on limits").tag("opus")
                }
                TextField("CLI path", text: $cliPath, prompt: Text("Auto-detect"))
                HStack {
                    Button("Test connection") { test() }.disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                }
                if !testOutput.isEmpty {
                    Text(testOutput)
                        .font(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Section("About") {
                LabeledContent("Version", value: AppInfo.version)
            }
            Section("Selected text in other apps") {
                Text("Shortcut: ⌃⌥G. Needs Accessibility permission (System Settings → Privacy & Security → Accessibility).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
    }

    private func test() {
        testing = true
        testOutput = ""
        Task {
            do {
                let path = try ClaudeCLI.shared.resolveExecutable(override: cliPath).path
                let started = Date()
                let out = try await ClaudeCLI.shared.run(
                    text: "She dont like apple's.", mode: .grammar, instructions: nil,
                    model: model, cliPath: cliPath
                )
                testOutput = String(format: "OK in %.1fs\nCLI: %@\nResult: %@", Date().timeIntervalSince(started), path, out)
            } catch {
                testOutput = error.localizedDescription
            }
            testing = false
        }
    }
}

// MARK: - Presets

struct PresetsSettingsView: View {
    @ObservedObject private var store = PresetStore.shared
    @State private var editingID: UUID?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            detail
        }
        .frame(width: 680, height: 420)
        .onAppear {
            if editingID == nil { editingID = store.presets.first?.id }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $editingID) {
                ForEach(store.presets) { preset in
                    Text(preset.displayName).tag(preset.id)
                }
                .onMove { store.move(from: $0, to: $1) }
            }
            .listStyle(.sidebar)

            Divider()

            HStack(spacing: 2) {
                Button {
                    editingID = store.add().id
                } label: {
                    Image(systemName: "plus").frame(width: 22, height: 20)
                }
                .help("Add preset")

                Button {
                    guard let id = editingID else { return }
                    let idx = store.presets.firstIndex { $0.id == id } ?? 0
                    store.delete(id: id)
                    editingID = store.presets.isEmpty ? nil : store.presets[min(idx, store.presets.count - 1)].id
                } label: {
                    Image(systemName: "minus").frame(width: 22, height: 20)
                }
                .disabled(editingID == nil)
                .help("Delete preset")

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(6)
        }
        .frame(width: 210)
    }

    @ViewBuilder
    private var detail: some View {
        if let id = editingID, store.presets.contains(where: { $0.id == id }) {
            let preset = binding(for: id)
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: preset.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)

                Text("Instructions")
                    .font(.headline)

                TextEditor(text: preset.instructions)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(nsColor: .separatorColor)))

                Text("Describe the audience, tone, formality and spelling variant, e.g. \"Slack message to a UK client; British spelling; polite but concise.\" These override the default rules (not the output format) and apply in both modes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            Text(store.presets.isEmpty ? "Click + to add a preset" : "Select a preset")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// ID-based binding: survives deletes/reorders without index-out-of-range crashes.
    private func binding(for id: UUID) -> Binding<Preset> {
        Binding(
            get: { store.presets.first { $0.id == id } ?? Preset(id: id, name: "", instructions: "") },
            set: { newValue in
                if let i = store.presets.firstIndex(where: { $0.id == id }) { store.presets[i] = newValue }
            }
        )
    }
}

enum AppInfo {
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    }
}
