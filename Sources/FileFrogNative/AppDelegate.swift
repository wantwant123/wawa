import AppKit

final class FileFrogAppDelegate: NSObject, NSApplicationDelegate {
    private var petWindow: NSPanel?
    private weak var frogView: FrogPetView?
    private var statusItem: NSStatusItem?
    private let store = DocumentStore()
    private let processor = DocumentProcessor()
    private lazy var workspaceController = WorkspaceWindowController(
        store: store,
        focusPet: { [weak self] in
            self?.showFrog()
        }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let view = FrogPetView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 520),
            processor: processor,
            store: store
        )
        view.onOpenWorkspace = { [weak self] document in
            self?.openWorkspace(document)
        }
        view.onLibraryChanged = { [weak self] in
            self?.workspaceController.reloadHistory()
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 980, y: 220, width: 520, height: 520),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        panel.title = "File Frog"
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = view
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        panel.setFrameAutosaveName("FileFrogPetWindow")

        petWindow = panel
        frogView = view
        setupStatusMenu()
    }

    private func setupStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐸"
        item.button?.toolTip = "File Frog"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示咕噜蛙", action: #selector(showFrog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "隐藏咕噜蛙", action: #selector(hideFrog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重置咕噜蛙", action: #selector(resetFrog), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "打开理解窗口", action: #selector(openWorkspaceFromMenu), keyEquivalent: "o"))
        menu.addItem(NSMenuItem(title: "显示/隐藏窗口边界", action: #selector(toggleDebugFrame), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 File Frog", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc private func showFrog() {
        petWindow?.orderFrontRegardless()
    }

    @objc private func hideFrog() {
        petWindow?.orderOut(nil)
    }

    @objc private func resetFrog() {
        frogView?.resetToIdle()
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: 520, height: 520)
        let origin = CGPoint(
            x: visible.maxX - size.width - 60,
            y: visible.minY + 80
        )
        petWindow?.setFrame(NSRect(origin: origin, size: size), display: true)
        petWindow?.orderFrontRegardless()
    }

    @objc private func openWorkspaceFromMenu() {
        workspaceController.show(document: store.loadRecentDocuments(limit: 1).first)
    }

    @objc private func toggleDebugFrame() {
        frogView?.toggleDebugFrame()
        petWindow?.orderFrontRegardless()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func openWorkspace(_ document: ProcessedDocument) {
        workspaceController.show(document: document)
        frogView?.resetToIdle(keepResult: false)
    }
}
