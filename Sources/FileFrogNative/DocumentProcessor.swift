import Foundation
import PDFKit

final class DocumentProcessor {
    func process(url: URL) async throws -> ProcessedDocument {
        try await Task.detached(priority: .userInitiated) {
            let kind = FileKind.from(url: url)
            guard kind == .pdf || kind == .plainText || kind == .markdown else {
                throw DocumentProcessingError.unsupported(kind)
            }

            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
            let extraction = try Self.extract(url: url, kind: kind)
            let cleanedText = Self.cleanText(extraction.text)

            guard cleanedText.trimmingCharacters(in: .whitespacesAndNewlines).count >= 12 else {
                throw DocumentProcessingError.emptyText
            }

            let normalizedExtraction = ExtractionResult(
                text: cleanedText,
                pageCount: extraction.pageCount,
                warnings: extraction.warnings
            )
            let summary = RuleBasedSummarizer.summarize(cleanedText)
            let id = UUID()
            let bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
            let record = DocumentRecord(
                id: id,
                fileName: url.lastPathComponent,
                fileKind: kind,
                originalURL: url,
                bookmarkData: bookmark,
                sizeLabel: FileSizeFormatter.label(for: size),
                createdAt: Date(),
                pageCount: extraction.pageCount,
                characterCount: cleanedText.count
            )

            return ProcessedDocument(
                id: id,
                record: record,
                extraction: normalizedExtraction,
                summary: summary
            )
        }.value
    }

    private static func extract(url: URL, kind: FileKind) throws -> ExtractionResult {
        switch kind {
        case .pdf:
            return try extractPDF(url)
        case .plainText, .markdown:
            return try extractText(url)
        case .word, .unsupported:
            throw DocumentProcessingError.unsupported(kind)
        }
    }

    private static func extractPDF(_ url: URL) throws -> ExtractionResult {
        guard let document = PDFDocument(url: url) else {
            throw DocumentProcessingError.unreadable
        }

        var pages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index), let text = page.string else {
                continue
            }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                pages.append(trimmed)
            }
        }

        return ExtractionResult(
            text: pages.joined(separator: "\n\n"),
            pageCount: document.pageCount,
            warnings: pages.isEmpty ? ["未能从 PDF 中提取到文本"] : []
        )
    }

    private static func extractText(_ url: URL) throws -> ExtractionResult {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return ExtractionResult(text: text, pageCount: nil, warnings: [])
        }

        if let text = try? String(contentsOf: url, encoding: .unicode) {
            return ExtractionResult(text: text, pageCount: nil, warnings: ["使用 Unicode 编码读取"])
        }

        throw DocumentProcessingError.unreadable
    }

    private static func cleanText(_ text: String) -> String {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        let frequencies = Dictionary(grouping: lines.filter { $0.count > 4 && $0.count < 80 }, by: { $0 })
            .mapValues(\.count)
        let repeated = Set(frequencies.filter { $0.value >= 4 }.map(\.key))

        let filtered = lines.filter { line in
            if line.isEmpty { return true }
            return !repeated.contains(line)
        }

        var paragraphs: [String] = []
        var buffer: [String] = []
        for line in filtered {
            if line.isEmpty {
                if !buffer.isEmpty {
                    paragraphs.append(buffer.joined(separator: " "))
                    buffer.removeAll()
                }
            } else {
                buffer.append(line)
            }
        }

        if !buffer.isEmpty {
            paragraphs.append(buffer.joined(separator: " "))
        }

        return paragraphs
            .map { collapseSpaces($0) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    private static func collapseSpaces(_ value: String) -> String {
        value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

enum RuleBasedSummarizer {
    static func summarize(_ text: String) -> SummaryResult {
        let paragraphs = splitParagraphs(text)
        let title = paragraphs.first(where: { $0.count >= 6 && $0.count <= 80 }) ?? paragraphs.first ?? text
        let oneLine = trimSentence(title, limit: 120)
        let keyPoints = topParagraphs(from: paragraphs, limit: 3)
        let risks = detectRisks(in: text)
        let snippets = Array(paragraphs.prefix(4)).map { trimSentence($0, limit: 180) }

        return SummaryResult(
            oneLineSummary: oneLine,
            keyPoints: keyPoints.isEmpty ? ["这份文件内容较短，建议打开工作台查看全文。"] : keyPoints,
            risks: risks,
            suggestedQuestions: [
                "这份文件主要讲什么？",
                "有哪些需要注意的风险？",
                "付款或时间相关条款是什么？"
            ],
            sourceSnippets: snippets
        )
    }

    private static func splitParagraphs(_ text: String) -> [String] {
        text.components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func topParagraphs(from paragraphs: [String], limit: Int) -> [String] {
        paragraphs
            .filter { $0.count >= 24 }
            .sorted { score($0) > score($1) }
            .prefix(limit)
            .map { trimSentence($0, limit: 150) }
    }

    private static func score(_ paragraph: String) -> Int {
        var value = min(paragraph.count, 260)
        for keyword in ["合同", "协议", "金额", "付款", "期限", "交付", "责任", "风险", "终止", "赔偿"] where paragraph.contains(keyword) {
            value += 80
        }
        return value
    }

    private static func detectRisks(in text: String) -> [String] {
        let rules: [(String, String)] = [
            ("付款", "存在付款相关条款，建议核对付款节点和付款条件。"),
            ("账期", "存在账期相关条款，建议确认是否影响现金流。"),
            ("违约", "存在违约责任条款，建议核对责任范围和赔付上限。"),
            ("终止", "存在终止条款，建议确认提前终止条件。"),
            ("赔偿", "存在赔偿条款，建议核对赔偿触发条件。"),
            ("保密", "存在保密义务，建议确认期限和例外情况。"),
            ("自动续约", "存在自动续约描述，建议确认取消窗口期。")
        ]

        var seen: Set<String> = []
        var results: [String] = []
        for (keyword, message) in rules where text.contains(keyword) && !seen.contains(message) {
            seen.insert(message)
            results.append(message)
        }

        return results
    }

    private static func trimSentence(_ value: String, limit: Int) -> String {
        let collapsed = value
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")

        guard collapsed.count > limit else {
            return collapsed
        }

        let index = collapsed.index(collapsed.startIndex, offsetBy: limit)
        return String(collapsed[..<index]) + "..."
    }
}
