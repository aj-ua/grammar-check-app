import Foundation
import SwiftUI

struct Preset: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var instructions: String

    var displayName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Untitled preset" : n
    }
}

/// Presets persisted in UserDefaults as JSON. Shared by Settings, main window and selection panel.
@MainActor
final class PresetStore: ObservableObject {
    static let shared = PresetStore()

    private static let presetsKey = "presets.v1"
    private static let selectedKey = "presets.selectedID"

    @Published var presets: [Preset] {
        didSet {
            save()
            if let id = selectedID, !presets.contains(where: { $0.id == id }) { selectedID = nil }
        }
    }

    @Published var selectedID: UUID? {
        didSet { UserDefaults.standard.set(selectedID?.uuidString, forKey: Self.selectedKey) }
    }

    var selected: Preset? {
        guard let selectedID else { return nil }
        return presets.first { $0.id == selectedID }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Self.presetsKey),
           let decoded = try? JSONDecoder().decode([Preset].self, from: data) {
            presets = decoded
        } else {
            presets = Self.starterPresets
            if let data = try? JSONEncoder().encode(presets) { defaults.set(data, forKey: Self.presetsKey) }
        }
        selectedID = defaults.string(forKey: Self.selectedKey).flatMap(UUID.init(uuidString:))
    }

    @discardableResult
    func add() -> Preset {
        let p = Preset(name: "New preset", instructions: "")
        presets.append(p)
        return p
    }

    func delete(id: UUID) {
        presets.removeAll { $0.id == id }
    }

    func move(from source: IndexSet, to destination: Int) {
        presets.move(fromOffsets: source, toOffset: destination)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
    }

    private static let starterPresets: [Preset] = [
        Preset(
            name: "Slack — colleague",
            instructions: """
            The text is a Slack message to a colleague. Keep it casual, friendly and concise. \
            Contractions and informal phrasing are fine; do not make it formal. \
            Keep emoji, @mentions, :emoji: codes and Slack formatting (*bold*, _italic_, `code`) intact.
            """
        ),
        Preset(
            name: "Slack — UK client",
            instructions: """
            The text is a Slack message to a client based in the UK. \
            Use British English spelling and vocabulary (e.g. colour, organise, centre). \
            Keep it polite and professional but not stiff, and concise. \
            Keep @mentions and Slack formatting (*bold*, _italic_, `code`) intact.
            """
        ),
    ]
}

// MARK: - Shared pickers (main window + selection panel)


struct PresetPicker: View {
    @ObservedObject var store: PresetStore

    var body: some View {
        Picker("Preset:", selection: $store.selectedID) {
            Text("No preset").tag(UUID?.none)
            if !store.presets.isEmpty { Divider() }
            ForEach(store.presets) { preset in
                Text(preset.displayName).tag(Optional(preset.id))
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .help(store.selected?.instructions ?? "No extra instructions")
    }
}

struct ModePicker: View {
    @AppStorage(Prefs.modeKey) private var modeRaw = Prefs.defaultMode.rawValue

    var body: some View {
        Picker("Mode:", selection: $modeRaw) {
            ForEach(CheckMode.allCases) { Text($0.label).tag($0.rawValue) }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }
}
