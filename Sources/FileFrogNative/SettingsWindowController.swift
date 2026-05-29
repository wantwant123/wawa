import AppKit

final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private var testTask: Task<Void, Never>?
    private let enginePopup = NSPopUpButton()
    private let endpointField = NSTextField()
    private let modelField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 360, y: 240, width: 500, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "File Frog 设置"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        buildUI()
        loadSettings()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        testTask?.cancel()
    }

    func show() {
        loadSettings()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let title = label("摘要引擎", size: 17, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(title)

        let engineLabel = label("模式", size: 13, weight: .regular, color: .secondaryLabelColor)
        engineLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(engineLabel)

        enginePopup.addItems(withTitles: SummaryEngine.allCases.map(\.displayName))
        enginePopup.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(enginePopup)

        let endpointLabel = label("AI 接口地址", size: 13, weight: .regular, color: .secondaryLabelColor)
        endpointLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(endpointLabel)

        endpointField.placeholderString = AppSettings.defaultAIEndpoint
        endpointField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(endpointField)

        let modelLabel = label("模型", size: 13, weight: .regular, color: .secondaryLabelColor)
        modelLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(modelLabel)

        modelField.placeholderString = AppSettings.defaultAIModel
        modelField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(modelField)

        let apiKeyLabel = label("API Key", size: 13, weight: .regular, color: .secondaryLabelColor)
        apiKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(apiKeyLabel)

        apiKeyField.placeholderString = "可先留空"
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(apiKeyField)

        let note = label("选择 DeepSeek AI 后，摘要和右侧问答会调用该接口；失败时自动回退本地规则。", size: 12, weight: .regular, color: .secondaryLabelColor)
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        note.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(note)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        let save = CallbackButton(title: "保存") { [weak self] in
            self?.saveSettings()
        }
        save.bezelStyle = .rounded
        save.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(save)

        let test = CallbackButton(title: "测试连接") { [weak self] in
            self?.testConnection()
        }
        test.bezelStyle = .rounded
        test.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(test)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),

            engineLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            engineLabel.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 22),
            enginePopup.leadingAnchor.constraint(equalTo: title.leadingAnchor, constant: 108),
            enginePopup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            enginePopup.centerYAnchor.constraint(equalTo: engineLabel.centerYAnchor),

            endpointLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            endpointLabel.topAnchor.constraint(equalTo: engineLabel.bottomAnchor, constant: 26),
            endpointField.leadingAnchor.constraint(equalTo: enginePopup.leadingAnchor),
            endpointField.trailingAnchor.constraint(equalTo: enginePopup.trailingAnchor),
            endpointField.centerYAnchor.constraint(equalTo: endpointLabel.centerYAnchor),

            modelLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            modelLabel.topAnchor.constraint(equalTo: endpointLabel.bottomAnchor, constant: 26),
            modelField.leadingAnchor.constraint(equalTo: enginePopup.leadingAnchor),
            modelField.trailingAnchor.constraint(equalTo: enginePopup.trailingAnchor),
            modelField.centerYAnchor.constraint(equalTo: modelLabel.centerYAnchor),

            apiKeyLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            apiKeyLabel.topAnchor.constraint(equalTo: modelLabel.bottomAnchor, constant: 26),
            apiKeyField.leadingAnchor.constraint(equalTo: enginePopup.leadingAnchor),
            apiKeyField.trailingAnchor.constraint(equalTo: enginePopup.trailingAnchor),
            apiKeyField.centerYAnchor.constraint(equalTo: apiKeyLabel.centerYAnchor),

            note.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            note.topAnchor.constraint(equalTo: apiKeyLabel.bottomAnchor, constant: 26),

            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            statusLabel.trailingAnchor.constraint(lessThanOrEqualTo: test.leadingAnchor, constant: -10),
            statusLabel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            test.trailingAnchor.constraint(equalTo: save.leadingAnchor, constant: -10),
            test.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            save.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            save.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    private func loadSettings() {
        let settings = store.load()
        enginePopup.selectItem(at: SummaryEngine.allCases.firstIndex(of: settings.summaryEngine) ?? 0)
        endpointField.stringValue = settings.aiEndpoint
        modelField.stringValue = settings.aiModel
        apiKeyField.stringValue = settings.aiAPIKey
        statusLabel.stringValue = ""
    }

    private func saveSettings() {
        let settings = currentSettings()

        do {
            try store.save(settings)
            statusLabel.textColor = .secondaryLabelColor
            statusLabel.stringValue = "已保存"
        } catch {
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "保存失败：\(error.localizedDescription)"
        }
    }

    private func testConnection() {
        testTask?.cancel()
        let settings = currentSettings()
        statusLabel.textColor = .secondaryLabelColor

        guard !settings.aiAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            statusLabel.textColor = .systemOrange
            statusLabel.stringValue = "先填 API Key"
            return
        }

        statusLabel.stringValue = "正在测试..."
        testTask = Task { [weak self] in
            do {
                let response = try await AIChatClient(settings: settings).testConnection()
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.statusLabel.textColor = .systemGreen
                    self?.statusLabel.stringValue = "连接正常：\(response)"
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    self?.statusLabel.textColor = .systemRed
                    self?.statusLabel.stringValue = "连接失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func currentSettings() -> AppSettings {
        let selected = SummaryEngine.allCases[safe: enginePopup.indexOfSelectedItem] ?? .localRules
        return AppSettings(
            schemaVersion: AppSettings.currentSchemaVersion,
            summaryEngine: selected,
            aiEndpoint: endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            aiModel: modelField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            aiAPIKey: apiKeyField.stringValue
        ).normalized
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor = .labelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = color
        return label
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
