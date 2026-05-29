import Foundation

final class DocumentStore {
    private struct LibraryFile: Codable {
        let schemaVersion: Int
        let records: [DocumentRecord]
    }

    private let schemaVersion = 1
    private let rootURL: URL
    private let documentsURL: URL
    private let libraryURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        rootURL = support.appendingPathComponent("File Frog", isDirectory: true)
        documentsURL = rootURL.appendingPathComponent("documents", isDirectory: true)
        libraryURL = rootURL.appendingPathComponent("library.json")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func save(_ document: ProcessedDocument) throws {
        try ensureDirectories()
        let documentURL = documentsURL.appendingPathComponent(document.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: documentURL, withIntermediateDirectories: true)

        let textURL = documentURL.appendingPathComponent("extracted.txt")
        try document.extraction.text.write(to: textURL, atomically: true, encoding: .utf8)

        let summaryURL = documentURL.appendingPathComponent("summary.json")
        try encoder.encode(document.summary).write(to: summaryURL, options: .atomic)

        var records = loadRecords()
        records.removeAll { $0.id == document.record.id }
        records.insert(document.record, at: 0)
        records = Array(records.prefix(50))
        try writeRecords(records)
    }

    func loadRecords(limit: Int? = nil) -> [DocumentRecord] {
        guard let data = try? Data(contentsOf: libraryURL) else {
            return []
        }

        let records: [DocumentRecord]
        if let library = try? decoder.decode(LibraryFile.self, from: data) {
            records = library.records
        } else if let legacyRecords = try? decoder.decode([DocumentRecord].self, from: data) {
            records = legacyRecords
        } else {
            return []
        }

        let sorted = records.sorted { $0.createdAt > $1.createdAt }
        if let limit {
            return Array(sorted.prefix(limit))
        }
        return sorted
    }

    func loadDocument(id: UUID) -> ProcessedDocument? {
        guard let record = loadRecords().first(where: { $0.id == id }) else {
            return nil
        }

        let documentURL = documentsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        let textURL = documentURL.appendingPathComponent("extracted.txt")
        let summaryURL = documentURL.appendingPathComponent("summary.json")

        guard let text = try? String(contentsOf: textURL, encoding: .utf8),
              let summaryData = try? Data(contentsOf: summaryURL),
              let summary = try? decoder.decode(SummaryResult.self, from: summaryData) else {
            return nil
        }

        let extraction = ExtractionResult(
            text: text,
            pageCount: record.pageCount,
            warnings: []
        )

        return ProcessedDocument(
            id: record.id,
            record: record,
            extraction: extraction,
            summary: summary
        )
    }

    func loadRecentDocuments(limit: Int = 10) -> [ProcessedDocument] {
        loadRecords(limit: limit).compactMap { loadDocument(id: $0.id) }
    }

    func deleteDocument(id: UUID) throws {
        var records = loadRecords()
        records.removeAll { $0.id == id }
        try ensureDirectories()
        try writeRecords(records)

        let documentURL = documentsURL.appendingPathComponent(id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: documentURL.path) {
            try FileManager.default.removeItem(at: documentURL)
        }
    }

    func clearLibrary() throws {
        try ensureDirectories()
        try writeRecords([])
        if FileManager.default.fileExists(atPath: documentsURL.path) {
            try FileManager.default.removeItem(at: documentsURL)
        }
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
    }

    private func ensureDirectories() throws {
        try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true)
    }

    private func writeRecords(_ records: [DocumentRecord]) throws {
        let library = LibraryFile(schemaVersion: schemaVersion, records: records)
        try encoder.encode(library).write(to: libraryURL, options: .atomic)
    }
}
