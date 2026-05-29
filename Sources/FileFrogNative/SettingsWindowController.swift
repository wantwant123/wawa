import AppKit

final class SettingsWindowController: NSWindowController {
    private let store: SettingsStore
    private let enginePopup = NSPopUpButton()
    private let endpointField = NSTextField()
    private let apiKeyField = NSSecureTextField()
    private let statusLabel = NSTextField(labelWithString: "")

    init(store: SettingsStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 360, y: 260, width: 460, height: 300),
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

        endpointField.placeholderString = "等你给接口后填这里"
        endpointField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(endpointField)

        let apiKeyLabel = label("API Key", size: 13, weight: .regular, color: .secondaryLabelColor)
        apiKeyLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(apiKeyLabel)

        apiKeyField.placeholderString = "可先留空"
        apiKeyField.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(apiKeyField)

        let note = label("当前 AI 模式只是预留接口，不会联网；真实调用等接入你的接口后启用。", size: 12, weight: .regular, color: .secondaryLabelColor)
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 2
        note.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(note)

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(statusLabel)

        let save = CallbackButton(title: "保存") { [weak self] in
            self?.saveSettings()
        }
        save.bezelStyle = .rounded
        save.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(save)

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

            apiKeyLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            apiKeyLabel.topAnchor.constraint(equalTo: endpointLabel.bottomAnchor, constant: 26),
            apiKeyField.leadingAnchor.constraint(equalTo: enginePopup.leadingAnchor),
            apiKeyField.trailingAnchor.constraint(equalTo: enginePopup.trailingAnchor),
            apiKeyField.centerYAnchor.constraint(equalTo: apiKeyLabel.centerYAnchor),

            note.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            note.topAnchor.constraint(equalTo: apiKeyLabel.bottomAnchor, constant: 26),

            statusLabel.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: save.centerYAnchor),
            save.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            save.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -22)
        ])
    }

    private func loadSettings() {
        let settings = store.load()
        enginePopup.selectItem(at: SummaryEngine.allCases.firstIndex(of: settings.summaryEngine) ?? 0)
        endpointField.stringValue = settings.aiEndpoint
        apiKeyField.stringValue = settings.aiAPIKey
        statusLabel.stringValue = ""
    }

    private func saveSettings() {
        let selected = SummaryEngine.allCases[safe: enginePopup.indexOfSelectedItem] ?? .localRules
        let settings = AppSettings(
            schemaVersion: AppSettings.currentSchemaVersion,
            summaryEngine: selected,
            aiEndpoint: endpointField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
            aiAPIKey: apiKeyField.stringValue
        )

        do {
            try store.save(settings)
            statusLabel.stringValue = "已保存"
        } catch {
            statusLabel.stringValue = "保存失败：\(error.localizedDescription)"
        }
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
