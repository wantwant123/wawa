import Foundation

enum SummaryEngine: String, Codable, CaseIterable {
    case localRules
    case ai = "aiPlaceholder"

    var displayName: String {
        switch self {
        case .localRules:
            return "本地规则"
        case .ai:
            return "DeepSeek AI"
        }
    }
}

struct AppSettings: Codable {
    var schemaVersion: Int
    var summaryEngine: SummaryEngine
    var aiEndpoint: String
    var aiModel: String
    var aiAPIKey: String

    static let currentSchemaVersion = 1
    static let defaultAIEndpoint = "https://dd-ai-api.eastmoney.com/v1/chat/completions"
    static let defaultAIModel = "DeepSeek-V4-Pro"

    enum CodingKeys: String, CodingKey {
        case schemaVersion
        case summaryEngine
        case aiEndpoint
        case aiModel
        case aiAPIKey
    }

    init(
        schemaVersion: Int,
        summaryEngine: SummaryEngine,
        aiEndpoint: String,
        aiModel: String,
        aiAPIKey: String
    ) {
        self.schemaVersion = schemaVersion
        self.summaryEngine = summaryEngine
        self.aiEndpoint = aiEndpoint
        self.aiModel = aiModel
        self.aiAPIKey = aiAPIKey
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? Self.currentSchemaVersion
        summaryEngine = try container.decodeIfPresent(SummaryEngine.self, forKey: .summaryEngine) ?? .localRules
        aiEndpoint = try container.decodeIfPresent(String.self, forKey: .aiEndpoint) ?? Self.defaultAIEndpoint
        aiModel = try container.decodeIfPresent(String.self, forKey: .aiModel) ?? Self.defaultAIModel
        aiAPIKey = try container.decodeIfPresent(String.self, forKey: .aiAPIKey) ?? ""
    }

    static var defaults: AppSettings {
        AppSettings(
            schemaVersion: currentSchemaVersion,
            summaryEngine: .localRules,
            aiEndpoint: defaultAIEndpoint,
            aiModel: defaultAIModel,
            aiAPIKey: ""
        )
    }

    var normalized: AppSettings {
        AppSettings(
            schemaVersion: Self.currentSchemaVersion,
            summaryEngine: summaryEngine,
            aiEndpoint: aiEndpoint.isEmpty ? Self.defaultAIEndpoint : aiEndpoint,
            aiModel: aiModel.isEmpty ? Self.defaultAIModel : aiModel,
            aiAPIKey: aiAPIKey
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
        return settings.normalized
    }

    func save(_ settings: AppSettings) throws {
        let directoryURL = settingsURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try encoder.encode(settings).write(to: settingsURL, options: .atomic)
    }
}

protocol DocumentSummarizing {
    func summarize(_ text: String) async throws -> SummaryResult
}

struct LocalRuleSummarizer: DocumentSummarizing {
    func summarize(_ text: String) async throws -> SummaryResult {
        RuleBasedSummarizer.summarize(text)
    }
}

struct AISummarizer: DocumentSummarizing {
    let settings: AppSettings

    func summarize(_ text: String) async throws -> SummaryResult {
        let client = AIChatClient(settings: settings)
        let prompt = """
        你是 File Frog 的文档理解助手。请阅读下面的文档文本，输出严格 JSON，不要 Markdown，不要解释。

        JSON 字段：
        {
          "oneLineSummary": "一句话摘要，80字以内",
          "keyPoints": ["3到5个核心要点"],
          "risks": ["风险提醒，没有则空数组"],
          "suggestedQuestions": ["3个适合继续追问的问题"],
          "sourceSnippets": ["3到4段原文关键片段，每段120字以内"]
        }

        文档文本：
        \(Self.truncate(text, limit: 12000))
        """
        let content = try await client.complete(prompt: prompt)
        return try Self.parseSummary(content)
    }

    private static func parseSummary(_ content: String) throws -> SummaryResult {
        let cleaned = stripCodeFence(content)
        guard let data = cleaned.data(using: .utf8),
              let summary = try? JSONDecoder().decode(SummaryResult.self, from: data) else {
            throw DocumentProcessingError.failed("AI 摘要结果格式不对")
        }
        return SummaryResult(
            oneLineSummary: summary.oneLineSummary.isEmpty ? "AI 未返回摘要" : summary.oneLineSummary,
            keyPoints: summary.keyPoints.isEmpty ? ["AI 未返回核心要点。"] : summary.keyPoints,
            risks: summary.risks,
            suggestedQuestions: summary.suggestedQuestions.isEmpty
                ? ["这份文件主要讲什么？", "有哪些需要注意的风险？", "付款或时间相关条款是什么？"]
                : summary.suggestedQuestions,
            sourceSnippets: summary.sourceSnippets
        )
    }

    static func truncate(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index])
    }

    static func stripCodeFence(_ content: String) -> String {
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```JSON", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }
}
