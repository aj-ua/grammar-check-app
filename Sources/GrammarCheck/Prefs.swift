import Foundation

enum CheckMode: String, CaseIterable, Identifiable {
    case grammar
    case style

    var id: String { rawValue }

    var label: String {
        switch self {
        case .grammar: return "Grammar only"
        case .style: return "Grammar + style"
        }
    }
}

/// Single source of truth for UserDefaults keys (shared with @AppStorage in views).
enum Prefs {
    static let modelKey = "model"
    static let cliPathKey = "cliPath"
    static let modeKey = "mode"

    static let defaultModel = "sonnet"
    static let defaultMode = CheckMode.style

    static var model: String {
        let v = UserDefaults.standard.string(forKey: modelKey) ?? ""
        return v.isEmpty ? defaultModel : v
    }

    static var cliPath: String {
        UserDefaults.standard.string(forKey: cliPathKey) ?? ""
    }

    static var mode: CheckMode {
        CheckMode(rawValue: UserDefaults.standard.string(forKey: modeKey) ?? "") ?? defaultMode
    }
}
