import Foundation

enum SummaryEngine: String, Codable, CaseIterable {
    case localRules
    case aiPlaceholder

    var displayName: String {
        switch self {
        case .localRules:
            return "本地规则"
        case .aiPlaceholder:
            return "AI 接口占位"
        }
    }
}

struct AppSettings: Codable {
    var schemaVersion: Int
    var summaryEngine: SummaryEngine
    var aiEndpoint: String
    var aiAPIKey: String

    static let currentSchemaVersion = 1

    static var defaults: AppSettings {
        AppSettings(
            schemaVersion: currentSchemaVersion,
            summaryEngine: .localRules,
            aiEndpoint: "",
            aiAPIKey: ""
        )
    }
}

final class SettingsStore {
    private let settingsURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let rootURL = support.appendingPathComponent("File Frog", isDirectory: true)
        settingsURL = rootURL.appendingPathComponent("settings.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> AppSettings {
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? decoder.decode(AppSettings.self, from: data) else {
            return .defaults
        }
        return settings
    }

    func save(_ settings: AppSettings) throws {
        let directoryURL = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
    }
}

protocol DocumentSummarizing {
    func summarize(_ text: String) throws -> SummaryResult
}

struct LocalRuleSummarizer: DocumentSummarizing {
    func summarize(_ text: String) throws -> SummaryResult {
        RuleBasedSummarizer.summarize(text)
    }
}

struct AISummarizerPlaceholder: DocumentSummarizing {
    func summarize(_ text: String) throws -> SummaryResult {
        RuleBasedSummarizer.summarize(text)
    }
}
