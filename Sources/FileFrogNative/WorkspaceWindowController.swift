import AppKit

final class WorkspaceWindowController: NSWindowController {
    private struct QATurn {
        let question: String
        let answer: String
        let source: String
    }

    private let store: DocumentStore
    private let settingsStore: SettingsStore
    private let focusPet: () -> Void
    private var currentDocument: ProcessedDocument?
    private var answerTask: Task<Void, Never>?
    private var qaTurns: [QATurn] = []
    private var historyStack = NSStackView()
    private var overviewText = NSTextView()
    private var documentActionStack = NSStackView()
    private var detailText = NSTextView()
    private var questionStack = NSStackView()
    private var questionInputField = NSTextField()
    private var qaStatusLabel = NSTextField(labelWithString: "")
    private weak var sendQuestionButton: NSButton?
    private weak var cancelQuestionButton: NSButton?
    private var answerText = NSTextView()

    init(store: DocumentStore, settingsStore: SettingsStore, focusPet: @escaping () -> Void) {
        self.store = store
        self.settingsStore = settingsStore
        self.focusPet = focusPet
        let window = NSWindow(
            contentRect: NSRect(x: 220, y: 160, width: 980, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "File Frog 理解窗口"
        window.minSize = NSSize(width: 860, height: 540)
        super.init(window: window)
        buildUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        answerTask?.cancel()
    }

    func show(document: ProcessedDocument?) {
        if let document {
            currentDocument = document
        } else if currentDocument == nil {
            currentDocument = store.loadRecentDocuments(limit: 1).first
        }
        reloadHistory()
        renderCurrentDocument()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func reloadHistory() {
        historyStack.arrangedSubviews.forEach { view in
            historyStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let documents = store.loadRecentDocuments(limit: 10)
        if documents.isEmpty {
            let empty = label("暂无历史", size: 13, weight: .regular, color: .secondaryLabelColor)
            historyStack.addArrangedSubview(empty)
            return
        }

        for document in documents {
            historyStack.addArrangedSubview(historyRow(for: document))
        }
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let root = NSStackView()
        root.orientation = .vertical
        root.spacing = 0
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor)
        ])

        root.addArrangedSubview(toolbar())

        let split = NSStackView()
        split.orientation = .horizontal
        split.spacing = 0
        split.heightAnchor.constraint(greaterThanOrEqualToConstant: 520).isActive = true
        root.addArrangedSubview(split)

        let sidebar = panel(width: 220)
        historyStack = NSStackView()
        historyStack.orientation = .vertical
        historyStack.spacing = 8
        historyStack.alignment = .leading
        sidebar.addSubview(historyHeader())
        sidebar.addSubview(scrollView(for: historyStack))
        layoutSidebar(sidebar)

        let middle = panel(width: 470)
        detailText = textView()
        middle.addSubview(scrollView(for: detailText))

        let right = panel(width: 290)
        overviewText = textView()
        documentActionStack = NSStackView()
        documentActionStack.orientation = .horizontal
        documentActionStack.spacing = 8
        documentActionStack.distribution = .fillEqually
        questionStack = NSStackView()
        questionStack.orientation = .vertical
        questionStack.spacing = 8
        answerText = textView()
        qaStatusLabel.font = .systemFont(ofSize: 11, weight: .regular)
        qaStatusLabel.textColor = .secondaryLabelColor
        qaStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        right.addSubview(scrollView(for: overviewText))
        right.addSubview(documentActionStack)
        right.addSubview(label("推荐问题", size: 14, weight: .semibold))
        right.addSubview(questionStack)
        right.addSubview(questionComposer())
        right.addSubview(qaStatusLabel)
        right.addSubview(scrollView(for: answerText))

        layoutMainPanel(middle)
        layoutRightPanel(right)

        split.addArrangedSubview(sidebar)
        split.addArrangedSubview(middle)
        split.addArrangedSubview(right)
    }

    private func toolbar() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalToConstant: 54).isActive = true

        let title = label("文档理解", size: 17, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let focus = CallbackButton(title: "回到咕噜蛙") { [weak self] in
            self?.focusPet()
        }
        focus.bezelStyle = .rounded
        focus.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(focus)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            focus.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            focus.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        return view
    }

    private func renderCurrentDocument() {
        answerTask?.cancel()
        setAnswering(false, status: "")

        guard let document = currentDocument else {
            overviewText.string = "把 PDF、TXT 或 Markdown 拖给咕噜蛙，它会在这里整理结果。"
            detailText.string = "暂无文档"
            qaTurns.removeAll()
            renderQAHistory(emptyMessage: "暂无问答")
            updateQAStatus()
            renderDocumentActions(nil)
            renderQuestions([])
            return
        }

        overviewText.string = overview(for: document)
        detailText.string = details(for: document)
        qaTurns.removeAll()
        renderQAHistory(emptyMessage: "可以点击推荐问题，也可以直接输入你想问的内容。")
        updateQAStatus()
        renderDocumentActions(document)
        renderQuestions(document.summary.suggestedQuestions)
    }

    private func renderDocumentActions(_ document: ProcessedDocument?) {
        documentActionStack.arrangedSubviews.forEach { view in
            documentActionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        guard document != nil else { return }

        let open = CallbackButton(title: "打开") { [weak self] in
            self?.openOriginalFile()
        }
        open.bezelStyle = .rounded
        let reveal = CallbackButton(title: "定位") { [weak self] in
            self?.revealOriginalFile()
        }
        reveal.bezelStyle = .rounded
        let delete = CallbackButton(title: "删除") { [weak self] in
            self?.deleteCurrentDocument()
        }
        delete.bezelStyle = .rounded

        documentActionStack.addArrangedSubview(open)
        documentActionStack.addArrangedSubview(reveal)
        documentActionStack.addArrangedSubview(delete)
    }

    private func renderQuestions(_ questions: [String]) {
        questionStack.arrangedSubviews.forEach { view in
            questionStack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for question in questions {
            let button = CallbackButton(title: question) { [weak self] in
                self?.submitQuestion(question)
            }
            button.alignment = .left
            button.bezelStyle = .rounded
            questionStack.addArrangedSubview(button)
        }
    }

    private func submitCurrentQuestion() {
        submitQuestion(questionInputField.stringValue)
    }

    private func submitQuestion(_ rawQuestion: String) {
        guard let document = currentDocument else { return }
        let question = rawQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            qaStatusLabel.stringValue = "先输入一个问题"
            return
        }

        questionInputField.stringValue = ""
        answerTask?.cancel()

        let settings = settingsStore.load()
        if settings.summaryEngine == .ai, !settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            setAnswering(true, status: "正在使用 DeepSeek AI 回答...")
            answerTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let response = try await self.aiAnswer(question: question, document: document, settings: settings)
                    if Task.isCancelled { return }
                    await MainActor.run {
                        self.qaTurns.append(QATurn(question: question, answer: response, source: "DeepSeek AI"))
                        self.renderQAHistory()
                        self.setAnswering(false, status: "AI 回答完成")
                    }
                } catch {
                    if Task.isCancelled { return }
                    await MainActor.run {
                        let fallback = self.localAnswer(question, document: document)
                        self.qaTurns.append(
                            QATurn(
                                question: question,
                                answer: fallback + "\n\nAI 暂时没答上：\(error.localizedDescription)",
                                source: "本地回退"
                            )
                        )
                        self.renderQAHistory()
                        self.setAnswering(false, status: "AI 失败，已回退本地回答")
                    }
                }
            }
            return
        }

        qaTurns.append(QATurn(question: question, answer: localAnswer(question, document: document), source: "本地规则"))
        renderQAHistory()
        updateQAStatus()
    }

    private func cancelAnswer() {
        answerTask?.cancel()
        setAnswering(false, status: "已取消当前问答")
    }

    private func setAnswering(_ isAnswering: Bool, status: String) {
        sendQuestionButton?.isEnabled = !isAnswering
        cancelQuestionButton?.isEnabled = isAnswering
        qaStatusLabel.stringValue = status
    }

    private func updateQAStatus() {
        let settings = settingsStore.load()
        if settings.summaryEngine == .ai {
            qaStatusLabel.stringValue = settings.aiAPIKey.isEmpty ? "DeepSeek AI 未配置 Key，将使用本地回答" : "DeepSeek AI 已启用"
        } else {
            qaStatusLabel.stringValue = "当前使用本地规则回答"
        }
        sendQuestionButton?.isEnabled = true
        cancelQuestionButton?.isEnabled = false
    }

    private func renderQAHistory(emptyMessage: String = "暂无问答") {
        guard !qaTurns.isEmpty else {
            answerText.string = emptyMessage
            return
        }

        answerText.string = qaTurns.enumerated()
            .map { index, turn in
                """
                Q\(index + 1) · \(turn.question)
                \(turn.source)
                \(turn.answer)
                """
            }
            .joined(separator: "\n\n")
    }

    private func localAnswer(_ question: String, document: ProcessedDocument) -> String {
        if document.extraction.text.count < 20 {
            return "这份文件可读内容较少。"
        }

        if question.contains("主要") {
            return document.summary.oneLineSummary
        } else if question.contains("风险") {
            return document.summary.risks.isEmpty
                ? "未发现明显风险提醒。"
                : document.summary.risks.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        } else {
            let snippets = document.summary.sourceSnippets.filter { snippet in
                snippet.contains("付款") || snippet.contains("期限") || snippet.contains("时间") || snippet.contains("账期")
            }
            return snippets.isEmpty ? "本地规则没有抓到明确的付款或时间条款。" : snippets.joined(separator: "\n\n")
        }
    }

    private func aiAnswer(question: String, document: ProcessedDocument, settings: AppSettings) async throws -> String {
        let client = AIChatClient(settings: settings)
        let prompt = """
        你是 File Frog 的文档问答助手。请基于文档文本回答用户问题，不要编造；如果文档没有相关信息，请明确说没有找到。

        用户问题：
        \(question)

        文档摘要：
        \(document.summary.oneLineSummary)

        核心要点：
        \(document.summary.keyPoints.joined(separator: "\n"))

        风险提醒：
        \((document.summary.risks.isEmpty ? ["未发现明显风险提醒"] : document.summary.risks).joined(separator: "\n"))

        文档文本：
        \(AISummarizer.truncate(document.extraction.text, limit: 10000))
        """
        return try await client.complete(prompt: prompt)
    }

    private func openOriginalFile() {
        guard let document = currentDocument else { return }
        let url = document.record.originalURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            answerText.string = "原文件不在之前的位置了，可以重新拖给咕噜蛙分析一次。"
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func revealOriginalFile() {
        guard let document = currentDocument else { return }
        let url = document.record.originalURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            answerText.string = "原文件不在之前的位置了，Finder 没法定位。"
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func deleteCurrentDocument() {
        guard let document = currentDocument else { return }
        do {
            try store.deleteDocument(id: document.id)
            currentDocument = store.loadRecentDocuments(limit: 1).first
            reloadHistory()
            renderCurrentDocument()
        } catch {
            answerText.string = "删除历史失败：\(error.localizedDescription)"
        }
    }

    private func clearHistory() {
        let alert = NSAlert()
        alert.messageText = "清空历史记录？"
        alert.informativeText = "会删除本地缓存的抽取文本和摘要，但不会删除你的原文件。"
        alert.addButton(withTitle: "清空")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try store.clearLibrary()
            currentDocument = nil
            reloadHistory()
            renderCurrentDocument()
        } catch {
            answerText.string = "清空历史失败：\(error.localizedDescription)"
        }
    }

    private func overview(for document: ProcessedDocument) -> String {
        let date = DateFormatter.localizedString(from: document.record.createdAt, dateStyle: .medium, timeStyle: .short)
        let pages = document.record.pageCount.map { "\($0) 页" } ?? "\(document.record.characterCount) 字"
        return """
        文件：\(document.record.fileName)
        类型：\(document.record.fileKind.displayName)
        大小：\(document.record.sizeLabel)
        内容：\(pages)
        时间：\(date)

        摘要：
        \(document.summary.oneLineSummary)
        """
    }

    private func details(for document: ProcessedDocument) -> String {
        let keyPoints = document.summary.keyPoints.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
        let risks = document.summary.risks.isEmpty
            ? "未发现明显风险提醒"
            : document.summary.risks.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        let snippets = document.summary.sourceSnippets.enumerated()
            .map { "片段 \($0.offset + 1)\n\($0.element)" }
            .joined(separator: "\n\n")

        return """
        核心要点
        \(keyPoints)

        风险提醒
        \(risks)

        原文片段
        \(snippets)
        """
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }

    private func historyHeader() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false

        let title = label("最近投喂", size: 15, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(title)

        let clear = CallbackButton(title: "清空") { [weak self] in
            self?.clearHistory()
        }
        clear.bezelStyle = .inline
        clear.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(clear)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 26),
            title.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            clear.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            clear.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        return view
    }

    private func historyRow(for document: ProcessedDocument) -> NSView {
        let row = NSStackView()
        row.orientation = .vertical
        row.spacing = 2
        row.alignment = .leading
        row.translatesAutoresizingMaskIntoConstraints = false

        let button = CallbackButton(title: document.record.fileName) { [weak self] in
            self?.currentDocument = document
            self?.renderCurrentDocument()
        }
        button.alignment = .left
        button.bezelStyle = .rounded
        button.lineBreakMode = .byTruncatingTail
        button.widthAnchor.constraint(equalToConstant: 188).isActive = true
        row.addArrangedSubview(button)

        let meta = "\(document.record.fileKind.displayName) · \(document.record.sizeLabel)"
        row.addArrangedSubview(label(meta, size: 11, weight: .regular, color: .secondaryLabelColor))

        return row
    }

    private func questionComposer() -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false

        questionInputField.placeholderString = "问这份文件..."
        questionInputField.font = .systemFont(ofSize: 13)
        questionInputField.translatesAutoresizingMaskIntoConstraints = false
        questionInputField.target = self
        questionInputField.action = #selector(submitQuestionFromField)
        row.addArrangedSubview(questionInputField)

        let send = CallbackButton(title: "发送") { [weak self] in
            self?.submitCurrentQuestion()
        }
        send.bezelStyle = .rounded
        send.widthAnchor.constraint(equalToConstant: 58).isActive = true
        row.addArrangedSubview(send)
        sendQuestionButton = send

        let cancel = CallbackButton(title: "取消") { [weak self] in
            self?.cancelAnswer()
        }
        cancel.bezelStyle = .rounded
        cancel.isEnabled = false
        cancel.widthAnchor.constraint(equalToConstant: 58).isActive = true
        row.addArrangedSubview(cancel)
        cancelQuestionButton = cancel

        return row
    }

    @objc private func submitQuestionFromField() {
        submitCurrentQuestion()
    }

    private func textView() -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.font = .systemFont(ofSize: 13)
        view.textContainerInset = NSSize(width: 12, height: 12)
        return view
    }

    private func panel(width: CGFloat) -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.widthAnchor.constraint(equalToConstant: width).isActive = true
        return view
    }

    private func scrollView(for documentView: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.documentView = documentView
        documentView.translatesAutoresizingMaskIntoConstraints = false
        if documentView is NSStackView {
            documentView.frame = NSRect(x: 0, y: 0, width: 240, height: 600)
        }
        return scroll
    }

    private func layoutSidebar(_ sidebar: NSView) {
        guard let header = sidebar.subviews.first,
              let scroll = sidebar.subviews.last as? NSScrollView else { return }
        header.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -14),
            header.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: 18),
            scroll.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 12),
            scroll.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -16)
        ])
    }

    private func layoutMainPanel(_ panel: NSView) {
        guard let scroll = panel.subviews.first as? NSScrollView else { return }
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
    }

    private func layoutRightPanel(_ panel: NSView) {
        guard panel.subviews.count == 7,
              let overview = panel.subviews[0] as? NSScrollView,
              let actions = panel.subviews[1] as? NSStackView,
              let title = panel.subviews[2] as? NSTextField,
              let questions = panel.subviews[3] as? NSStackView,
              let composer = panel.subviews[4] as? NSStackView,
              let status = panel.subviews[5] as? NSTextField,
              let answer = panel.subviews[6] as? NSScrollView else { return }
        actions.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        questions.translatesAutoresizingMaskIntoConstraints = false
        composer.translatesAutoresizingMaskIntoConstraints = false
        status.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overview.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            overview.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            overview.topAnchor.constraint(equalTo: panel.topAnchor),
            overview.heightAnchor.constraint(equalToConstant: 150),
            actions.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            actions.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            actions.topAnchor.constraint(equalTo: overview.bottomAnchor, constant: 10),
            actions.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 14),
            questions.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            questions.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            questions.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            composer.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            composer.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            composer.topAnchor.constraint(equalTo: questions.bottomAnchor, constant: 12),
            composer.heightAnchor.constraint(equalToConstant: 30),
            status.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            status.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -14),
            status.topAnchor.constraint(equalTo: composer.bottomAnchor, constant: 6),
            answer.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            answer.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            answer.topAnchor.constraint(equalTo: status.bottomAnchor, constant: 8),
            answer.bottomAnchor.constraint(equalTo: panel.bottomAnchor)
        ])
    }
}

final class CallbackButton: NSButton {
    private let callback: () -> Void

    init(title: String, callback: @escaping () -> Void) {
        self.callback = callback
        super.init(frame: .zero)
        self.title = title
        target = self
        action = #selector(runCallback)
        translatesAutoresizingMaskIntoConstraints = false
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func runCallback() {
        callback()
    }
}
