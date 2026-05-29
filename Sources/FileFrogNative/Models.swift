import Foundation

enum FrogStage {
    case idle
    case trackingFile
    case readyToEat
    case snapping
    case chewing
    case extracting
    case summarizing
    case resultReady
    case unsupported
    case failed

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .trackingFile:
            return "发现文件"
        case .readyToEat:
            return "放这里"
        case .snapping:
            return "啪"
        case .chewing:
            return "咕噜"
        case .extracting:
            return "咬开文件"
        case .summarizing:
            return "抓重点"
        case .resultReady:
            return nil
        case .unsupported:
            return "这个我还不会读"
        case .failed:
            return "读不出来"
        }
    }
}

enum FileKind: String, Codable {
    case pdf
    case plainText
    case markdown
    case word
    case unsupported

    var displayName: String {
        switch self {
        case .pdf:
            return "PDF"
        case .plainText:
            return "文本"
        case .markdown:
            return "Markdown"
        case .word:
            return "Word"
        case .unsupported:
            return "未知"
        }
    }

    var badge: String {
        switch self {
        case .pdf:
            return "PDF"
        case .plainText:
            return "TXT"
        case .markdown:
            return "MD"
        case .word:
            return "W"
        case .unsupported:
            return "FILE"
        }
    }

    static func from(url: URL) -> FileKind {
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "txt", "text":
            return .plainText
        case "md", "markdown":
            return .markdown
        case "doc", "docx":
            return .word
        default:
            return .unsupported
        }
    }
}

struct DroppedFile {
    let name: String
    let size: UInt64
    let url: URL?
    let fileKind: FileKind

    var sizeLabel: String {
        FileSizeFormatter.label(for: size)
    }

    var badge: String {
        fileKind.badge
    }
}

struct DocumentRecord: Codable, Identifiable {
    let id: UUID
    let fileName: String
    let fileKind: FileKind
    let originalURL: URL
    let bookmarkData: Data?
    let sizeLabel: String
    let createdAt: Date
    let pageCount: Int?
    let characterCount: Int
}

struct ExtractionResult: Codable {
    let text: String
    let pageCount: Int?
    let warnings: [String]
}

struct SummaryResult: Codable {
    let oneLineSummary: String
    let keyPoints: [String]
    let risks: [String]
    let suggestedQuestions: [String]
    let sourceSnippets: [String]
}

struct ProcessedDocument: Codable, Identifiable {
    let id: UUID
    let record: DocumentRecord
    let extraction: ExtractionResult
    let summary: SummaryResult
}

enum DocumentProcessingError: LocalizedError {
    case unsupported(FileKind)
    case emptyText
    case unreadable
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let kind):
            if kind == .word {
                return "Word 文档我先认得出来，但还不会深度读取"
            }
            return "这个文件类型我还不会读"
        case .emptyText:
            return "这可能是扫描件，我现在还读不了"
        case .unreadable:
            return "文件内容读不出来"
        case .failed(let message):
            return message
        }
    }
}

enum FileSizeFormatter {
    static func label(for size: UInt64) -> String {
        if size < 1_048_576 {
            return "\(max(1, Int(size / 1024))) KB"
        }

        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }
}
