import AppKit

final class WorkspaceWindowController: NSWindowController {
    private let store: DocumentStore
    private let focusPet: () -> Void
    private var currentDocument: ProcessedDocument?
    private var historyStack = NSStackView()
    private var overviewText = NSTextView()
    private var documentActionStack = NSStackView()
    private var detailText = NSTextView()
    private var questionStack = NSStackView()
    private var answerText = NSTextView()

    init(store: DocumentStore, focusPet: @escaping () -> Void) {
        self.store = store
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
        right.addSubview(scrollView(for: overviewText))
        right.addSubview(documentActionStack)
        right.addSubview(label("推荐问题", size: 14, weight: .semibold))
        right.addSubview(questionStack)
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
        guard let document = currentDocument else {
            overviewText.string = "把 PDF、TXT 或 Markdown 拖给咕噜蛙，它会在这里整理结果。"
            detailText.string = "暂无文档"
            answerText.string = ""
            renderDocumentActions(nil)
            renderQuestions([])
            return
        }

        overviewText.string = overview(for: document)
        detailText.string = details(for: document)
        answerText.string = "点击上方问题，咕噜蛙会基于本地摘要给出回答。"
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
                self?.answer(question)
            }
            button.alignment = .left
            button.bezelStyle = .rounded
            questionStack.addArrangedSubview(button)
        }
    }

    private func answer(_ question: String) {
        guard let document = currentDocument else { return }
        if document.extraction.text.count < 20 {
            answerText.string = "这份文件可读内容较少。"
            return
        }

        if question.contains("主要") {
            answerText.string = document.summary.oneLineSummary
        } else if question.contains("风险") {
            answerText.string = document.summary.risks.isEmpty
                ? "未发现明显风险提醒。"
                : document.summary.risks.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        } else {
            let snippets = document.summary.sourceSnippets.filter { snippet in
                snippet.contains("付款") || snippet.contains("期限") || snippet.contains("时间") || snippet.contains("账期")
            }
            answerText.string = snippets.isEmpty ? "本地规则没有抓到明确的付款或时间条款。" : snippets.joined(separator: "\n\n")
        }
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
        guard panel.subviews.count == 5,
              let overview = panel.subviews[0] as? NSScrollView,
              let actions = panel.subviews[1] as? NSStackView,
              let title = panel.subviews[2] as? NSTextField,
              let questions = panel.subviews[3] as? NSStackView,
              let answer = panel.subviews[4] as? NSScrollView else { return }
        actions.translatesAutoresizingMaskIntoConstraints = false
        title.translatesAutoresizingMaskIntoConstraints = false
        questions.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overview.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            overview.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            overview.topAnchor.constraint(equalTo: panel.topAnchor),
            overview.heightAnchor.constraint(equalToConstant: 190),
            actions.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            actions.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            actions.topAnchor.constraint(equalTo: overview.bottomAnchor, constant: 10),
            actions.heightAnchor.constraint(equalToConstant: 28),
            title.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 14),
            title.topAnchor.constraint(equalTo: actions.bottomAnchor, constant: 14),
            questions.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 12),
            questions.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            questions.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 8),
            answer.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            answer.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            answer.topAnchor.constraint(equalTo: questions.bottomAnchor, constant: 14),
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
