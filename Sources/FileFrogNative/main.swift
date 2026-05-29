import AppKit

enum FrogStage {
    case idle
    case detecting
    case readyToEat
    case locked
    case snapping
    case retracting
    case gulp
    case digesting
    case processing
    case almostDone
    case ejecting
    case resultReady

    var message: String? {
        switch self {
        case .idle:
            return nil
        case .detecting:
            return "发现文件"
        case .readyToEat:
            return "放这里"
        case .locked:
            return "准备中"
        case .snapping:
            return "啪"
        case .retracting:
            return "卷回"
        case .gulp:
            return "咕噜"
        case .digesting:
            return "读取文件中"
        case .processing:
            return "整理要点"
        case .almostDone:
            return "生成摘要"
        case .ejecting:
            return "吐出总结"
        case .resultReady:
            return nil
        }
    }
}

struct DroppedFile {
    let name: String
    let size: UInt64
    let url: URL?

    var sizeLabel: String {
        if size < 1_048_576 {
            return "\(max(1, Int(size / 1024))) KB"
        }

        let mb = Double(size) / 1_048_576
        return String(format: "%.1f MB", mb)
    }

    var badge: String {
        let ext = (url?.pathExtension ?? name.split(separator: ".").last.map(String.init) ?? "").lowercased()
        if ext == "doc" || ext == "docx" {
            return "W"
        }
        if ext == "pdf" {
            return "PDF"
        }
        return "FILE"
    }
}

final class FileFrogAppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSPanel?
    private weak var frogView: FrogPetView?
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        let view = FrogPetView(frame: NSRect(x: 0, y: 0, width: 520, height: 520))
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

        self.window = panel
        self.frogView = view
        setupStatusMenu()
    }

    private func setupStatusMenu() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "🐸"
        item.button?.toolTip = "File Frog"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示咕噜蛙", action: #selector(showFrog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "隐藏咕噜蛙", action: #selector(hideFrog), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "重置位置", action: #selector(resetPosition), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "显示/隐藏窗口边界", action: #selector(toggleDebugFrame), keyEquivalent: "d"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出 File Frog", action: #selector(quitApp), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }

        item.menu = menu
        statusItem = item
    }

    @objc private func showFrog() {
        window?.orderFrontRegardless()
    }

    @objc private func hideFrog() {
        window?.orderOut(nil)
    }

    @objc private func resetPosition() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = CGSize(width: 520, height: 520)
        let origin = CGPoint(
            x: visible.maxX - size.width - 60,
            y: visible.minY + 80
        )
        window?.setFrame(NSRect(origin: origin, size: size), display: true)
        window?.orderFrontRegardless()
    }

    @objc private func toggleDebugFrame() {
        frogView?.toggleDebugFrame()
        window?.orderFrontRegardless()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

final class FrogPetView: NSView {
    private let detectRadius: CGFloat = 170
    private let eatRadius: CGFloat = 112
    private var stage: FrogStage = .idle {
        didSet {
            needsDisplay = true
        }
    }
    private var draggedFile: DroppedFile?
    private var capturedFile: DroppedFile?
    private var ghostPoint: CGPoint?
    private var progress: Int?
    private var eyeOffset = CGPoint.zero
    private var animationTimers: [Timer] = []
    private var renderTimer: Timer?
    private let animationStart = Date()
    private var dragWindowStart: CGPoint?
    private var dragMouseStart: CGPoint?
    private var showsDebugFrame = ProcessInfo.processInfo.environment["FILE_FROG_DEBUG"] == "1"

    override var isFlipped: Bool {
        true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        registerForDraggedTypes([.fileURL])
        startRenderLoop()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        renderTimer?.invalidate()
        clearTimers()
    }

    func toggleDebugFrame() {
        showsDebugFrame.toggle()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        if showsDebugFrame {
            drawWindowDebugFrame()
        }
        drawDropAura()
        drawFileGhost()
        drawBubble()
        drawResultCard()
        drawFrog()
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        dragWindowStart = window.frame.origin
        dragMouseStart = NSEvent.mouseLocation
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragWindowStart, let dragMouseStart else { return }
        let current = NSEvent.mouseLocation
        let delta = CGPoint(x: current.x - dragMouseStart.x, y: current.y - dragMouseStart.y)
        window.setFrameOrigin(CGPoint(x: dragWindowStart.x + delta.x, y: dragWindowStart.y + delta.y))
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateDrag(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if stage == .detecting || stage == .readyToEat {
            resetDragState()
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let file = readDroppedFile(sender) else {
            resetDragState()
            return false
        }

        let point = convert(sender.draggingLocation, from: nil)
        draggedFile = file
        ghostPoint = point

        if distanceToFrog(point) > eatRadius {
            stage = .detecting
            schedule(after: 0.7) { [weak self] in
                self?.resetDragState()
            }
            return false
        }

        capturedFile = file
        runStorySequence()
        return true
    }

    private var frogCenter: CGPoint {
        CGPoint(x: bounds.midX + 66, y: bounds.midY + 62)
    }

    private func updateDrag(_ sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        ghostPoint = point
        draggedFile = readDroppedFile(sender) ?? DroppedFile(name: "外部文件", size: 0, url: nil)

        let dx = point.x - frogCenter.x
        let dy = point.y - frogCenter.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        eyeOffset = CGPoint(x: dx / length * 3.5, y: dy / length * 3.5)

        let distance = distanceToFrog(point)
        if distance <= eatRadius {
            stage = .readyToEat
        } else if distance <= detectRadius {
            stage = .detecting
        } else {
            stage = .idle
        }
    }

    private func readDroppedFile(_ sender: NSDraggingInfo) -> DroppedFile? {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let url = urls.first else {
            return nil
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(UInt64.init) ?? 0
        return DroppedFile(name: url.lastPathComponent, size: size, url: url)
    }

    private func distanceToFrog(_ point: CGPoint) -> CGFloat {
        hypot(point.x - frogCenter.x, point.y - frogCenter.y)
    }

    private func runStorySequence() {
        clearTimers()
        stage = .locked
        progress = nil

        schedule(after: 0.35) { [weak self] in
            self?.stage = .snapping
        }
        schedule(after: 0.68) { [weak self] in
            self?.stage = .retracting
        }
        schedule(after: 1.05) { [weak self] in
            self?.draggedFile = nil
            self?.ghostPoint = nil
            self?.stage = .gulp
        }
        schedule(after: 1.55) { [weak self] in
            self?.progress = 15
            self?.stage = .digesting
        }
        schedule(after: 2.35) { [weak self] in
            self?.progress = 45
            self?.stage = .processing
        }
        schedule(after: 3.15) { [weak self] in
            self?.progress = 85
            self?.stage = .almostDone
        }
        schedule(after: 4.05) { [weak self] in
            self?.progress = nil
            self?.stage = .ejecting
        }
        schedule(after: 4.55) { [weak self] in
            self?.stage = .resultReady
            self?.eyeOffset = .zero
        }
    }

    private func resetDragState() {
        draggedFile = nil
        ghostPoint = nil
        progress = nil
        eyeOffset = .zero
        stage = .idle
    }

    private func clearTimers() {
        animationTimers.forEach { $0.invalidate() }
        animationTimers.removeAll()
    }

    private func schedule(after delay: TimeInterval, _ action: @escaping () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { _ in
            action()
        }
        animationTimers.append(timer)
    }

    private func startRenderLoop() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if stage != .idle || draggedFile != nil || capturedFile != nil {
                needsDisplay = true
            } else {
                let phase = Date().timeIntervalSince(animationStart)
                if Int(phase * 10) % 2 == 0 {
                    needsDisplay = true
                }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        renderTimer = timer
    }

    private func drawWindowDebugFrame() {
        NSColor(calibratedRed: 0.33, green: 0.68, blue: 0.52, alpha: 0.55).setStroke()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 10, dy: 10), xRadius: 24, yRadius: 24)
        path.lineWidth = 1
        path.setLineDash([4, 4], count: 2, phase: 0)
        path.stroke()
    }

    private func drawDropAura() {
        guard draggedFile != nil || stage == .detecting || stage == .readyToEat || stage == .locked else {
            return
        }
        let ready = stage == .readyToEat || stage == .locked
        let pulse = CGFloat((sin(Date().timeIntervalSince(animationStart) * 5.0) + 1.0) * 0.5)
        let size = ready ? CGSize(width: 222 + pulse * 14, height: 162 + pulse * 10) : CGSize(width: 198 + pulse * 10, height: 144 + pulse * 8)
        let aura = NSBezierPath(ovalIn: centeredRect(size: size))

        NSGraphicsContext.saveGraphicsState()
        applyShadow(
            color: ready
                ? NSColor(calibratedRed: 0.65, green: 0.94, blue: 0.42, alpha: 0.42)
                : NSColor(calibratedRed: 0.5, green: 0.82, blue: 0.78, alpha: 0.26),
            offset: .zero,
            blur: ready ? 32 : 24
        )
        (ready
            ? NSColor(calibratedRed: 0.82, green: 1.0, blue: 0.52, alpha: 0.18)
            : NSColor(calibratedRed: 0.62, green: 0.91, blue: 0.83, alpha: 0.12)
        ).setFill()
        aura.fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func centeredRect(size: CGSize) -> CGRect {
        CGRect(
            x: frogCenter.x - size.width / 2,
            y: frogCenter.y - size.height / 2 + 6,
            width: size.width,
            height: size.height
        )
    }

    private func drawFileGhost() {
        guard let point = ghostPoint, let file = draggedFile else { return }
        NSGraphicsContext.saveGraphicsState()
        applyShadow(color: NSColor.black.withAlphaComponent(0.22), offset: CGSize(width: 0, height: -8), blur: 16)

        let paper = CGRect(x: point.x - 34, y: point.y - 48, width: 68, height: 78)
        let badgeColor = file.badge == "W" ? NSColor.systemBlue : file.badge == "PDF" ? NSColor.systemRed : NSColor.gray
        badgeColor.setFill()
        NSBezierPath(roundedRect: paper, xRadius: 6, yRadius: 6).fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.92).setStroke()
        let outline = NSBezierPath(roundedRect: paper, xRadius: 6, yRadius: 6)
        outline.lineWidth = 2
        outline.stroke()

        NSColor.white.setFill()
        drawText(file.badge, in: paper.offsetBy(dx: 0, dy: 22), size: 15, weight: .bold, alignment: .center)
        drawText(file.name, in: CGRect(x: point.x - 62, y: point.y + 34, width: 124, height: 18), size: 11, weight: .semibold, alignment: .center, color: .white)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBubble() {
        guard let message = stage.message else { return }
        let rect = CGRect(x: frogCenter.x - 64, y: frogCenter.y - 146, width: 128, height: progress == nil ? 32 : 46)
        NSGraphicsContext.saveGraphicsState()
        applyShadow(color: NSColor.black.withAlphaComponent(0.12), offset: CGSize(width: 0, height: -5), blur: 12)
        NSColor(calibratedRed: 0.93, green: 1.0, blue: 0.74, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 16, yRadius: 16).fill()
        NSGraphicsContext.restoreGraphicsState()
        drawText(message, in: rect.insetBy(dx: 8, dy: 5), size: 13, weight: .bold, alignment: .center, color: NSColor(calibratedRed: 0.1, green: 0.25, blue: 0.18, alpha: 1))
        if let progress {
            drawText("\(progress)%", in: rect.insetBy(dx: 8, dy: 24), size: 11, weight: .bold, alignment: .center, color: NSColor(calibratedRed: 0.36, green: 0.48, blue: 0.12, alpha: 1))
        }
    }

    private func drawResultCard() {
        guard stage == .resultReady, let file = capturedFile else { return }
        let rect = CGRect(x: frogCenter.x - 196, y: frogCenter.y - 168, width: 214, height: 112)
        NSGraphicsContext.saveGraphicsState()
        applyShadow(color: NSColor.black.withAlphaComponent(0.16), offset: CGSize(width: 0, height: -8), blur: 18)
        let card = NSBezierPath()
        card.move(to: CGPoint(x: rect.minX + 18, y: rect.midY))
        card.curve(to: CGPoint(x: rect.minX + 62, y: rect.minY + 10), controlPoint1: CGPoint(x: rect.minX + 28, y: rect.minY + 26), controlPoint2: CGPoint(x: rect.minX + 42, y: rect.minY + 10))
        card.line(to: CGPoint(x: rect.maxX - 28, y: rect.minY + 10))
        card.curve(to: CGPoint(x: rect.maxX - 12, y: rect.midY + 4), controlPoint1: CGPoint(x: rect.maxX - 8, y: rect.minY + 22), controlPoint2: CGPoint(x: rect.maxX - 4, y: rect.midY - 4))
        card.curve(to: CGPoint(x: rect.maxX - 54, y: rect.maxY - 8), controlPoint1: CGPoint(x: rect.maxX - 26, y: rect.maxY - 2), controlPoint2: CGPoint(x: rect.maxX - 40, y: rect.maxY))
        card.line(to: CGPoint(x: rect.minX + 54, y: rect.maxY - 10))
        card.curve(to: CGPoint(x: rect.minX + 18, y: rect.midY), controlPoint1: CGPoint(x: rect.minX + 30, y: rect.maxY - 10), controlPoint2: CGPoint(x: rect.minX + 12, y: rect.maxY - 4))
        card.close()
        NSGradient(
            starting: NSColor(calibratedRed: 0.88, green: 1.0, blue: 0.62, alpha: 0.96),
            ending: NSColor(calibratedRed: 0.66, green: 0.9, blue: 0.38, alpha: 0.94)
        )?.draw(in: card, angle: -18)
        NSGraphicsContext.restoreGraphicsState()

        drawText("理解完成", in: CGRect(x: rect.minX + 24, y: rect.minY + 18, width: 100, height: 16), size: 10, weight: .bold, color: NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.16, alpha: 1))
        drawText(file.name, in: CGRect(x: rect.minX + 24, y: rect.minY + 38, width: rect.width - 48, height: 22), size: 14, weight: .bold, color: NSColor(calibratedRed: 0.09, green: 0.22, blue: 0.1, alpha: 1))
        drawText("3 个要点 · 1 处风险", in: CGRect(x: rect.minX + 24, y: rect.minY + 66, width: rect.width - 48, height: 22), size: 11, weight: .semibold, color: NSColor(calibratedRed: 0.14, green: 0.32, blue: 0.14, alpha: 0.82))
    }

    private func drawFrog() {
        let center = frogCenter
        let phase = Date().timeIntervalSince(animationStart)
        let breath = CGFloat(sin(phase * 2.2))
        let scale: CGFloat
        switch stage {
        case .readyToEat, .locked:
            scale = 1.035
        case .gulp, .digesting, .processing, .almostDone:
            scale = 1.02 + abs(breath) * 0.018
        default:
            scale = 1.0 + breath * 0.012
        }
        let squash: CGFloat = stage == .readyToEat ? 0.965 : 1.0

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: center.x, yBy: center.y + 92)
        transform.scaleX(by: scale, yBy: scale * squash)
        transform.translateX(by: -center.x, yBy: -(center.y + 92))
        transform.concat()

        NSColor(calibratedWhite: 0, alpha: 0.13).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 86, y: center.y + 94, width: 172, height: 24)).fill()

        drawFoot(CGRect(x: center.x - 94, y: center.y + 72, width: 68, height: 36), flip: false)
        drawFoot(CGRect(x: center.x + 26, y: center.y + 72, width: 68, height: 36), flip: true)

        let body = NSBezierPath()
        body.move(to: CGPoint(x: center.x, y: center.y - 62))
        body.curve(
            to: CGPoint(x: center.x - 92, y: center.y + 28),
            controlPoint1: CGPoint(x: center.x - 56, y: center.y - 64),
            controlPoint2: CGPoint(x: center.x - 94, y: center.y - 20)
        )
        body.curve(
            to: CGPoint(x: center.x - 66, y: center.y + 96),
            controlPoint1: CGPoint(x: center.x - 100, y: center.y + 62),
            controlPoint2: CGPoint(x: center.x - 92, y: center.y + 86)
        )
        body.curve(
            to: CGPoint(x: center.x + 66, y: center.y + 96),
            controlPoint1: CGPoint(x: center.x - 30, y: center.y + 122),
            controlPoint2: CGPoint(x: center.x + 30, y: center.y + 122)
        )
        body.curve(
            to: CGPoint(x: center.x + 92, y: center.y + 28),
            controlPoint1: CGPoint(x: center.x + 92, y: center.y + 86),
            controlPoint2: CGPoint(x: center.x + 100, y: center.y + 62)
        )
        body.curve(
            to: CGPoint(x: center.x, y: center.y - 62),
            controlPoint1: CGPoint(x: center.x + 94, y: center.y - 20),
            controlPoint2: CGPoint(x: center.x + 56, y: center.y - 64)
        )
        body.close()
        NSGradient(
            starting: NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.86, alpha: 1),
            ending: NSColor(calibratedRed: 0.40, green: 0.73, blue: 0.56, alpha: 1)
        )?.draw(in: body, angle: -68)
        NSColor(calibratedRed: 0.30, green: 0.61, blue: 0.47, alpha: 1).setStroke()
        body.lineWidth = 4
        body.stroke()

        let highlight = NSBezierPath(ovalIn: CGRect(x: center.x - 48, y: center.y - 26, width: 96, height: 40))
        NSColor(calibratedRed: 0.95, green: 1.0, blue: 0.9, alpha: 0.20).setFill()
        highlight.fill()

        drawArm(CGRect(x: center.x - 91, y: center.y + 28, width: 45, height: 64), flip: false)
        drawArm(CGRect(x: center.x + 46, y: center.y + 28, width: 45, height: 64), flip: true)

        NSColor(calibratedRed: 1.0, green: 0.89, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 58, y: center.y + 28, width: 116, height: 72)).fill()
        NSColor(calibratedRed: 0.89, green: 0.76, blue: 0.45, alpha: 0.28).setStroke()
        let bellyLine = NSBezierPath()
        bellyLine.move(to: CGPoint(x: center.x - 42, y: center.y + 58))
        bellyLine.curve(to: CGPoint(x: center.x + 42, y: center.y + 58), controlPoint1: CGPoint(x: center.x - 18, y: center.y + 75), controlPoint2: CGPoint(x: center.x + 18, y: center.y + 75))
        bellyLine.lineWidth = 2
        bellyLine.lineCapStyle = .round
        bellyLine.stroke()

        drawEye(center: CGPoint(x: center.x - 39, y: center.y - 33))
        drawEye(center: CGPoint(x: center.x + 39, y: center.y - 33))

        NSColor(calibratedRed: 0.30, green: 0.61, blue: 0.47, alpha: 0.8).setStroke()
        let bridge = NSBezierPath()
        bridge.move(to: CGPoint(x: center.x - 13, y: center.y - 30))
        bridge.curve(to: CGPoint(x: center.x + 13, y: center.y - 30), controlPoint1: CGPoint(x: center.x - 5, y: center.y - 36), controlPoint2: CGPoint(x: center.x + 5, y: center.y - 36))
        bridge.lineWidth = 4
        bridge.lineCapStyle = .round
        bridge.stroke()

        NSColor(calibratedRed: 0.96, green: 0.78, blue: 0.40, alpha: 0.72).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 72, y: center.y + 33, width: 30, height: 28)).fill()
        NSBezierPath(ovalIn: CGRect(x: center.x + 42, y: center.y + 33, width: 30, height: 28)).fill()

        NSColor(calibratedRed: 0.23, green: 0.49, blue: 0.39, alpha: 0.55).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 18, y: center.y + 24, width: 5, height: 3)).fill()
        NSBezierPath(ovalIn: CGRect(x: center.x + 13, y: center.y + 24, width: 5, height: 3)).fill()

        if stage == .snapping || stage == .retracting {
            drawTongue()
        }

        NSColor(calibratedRed: 0.28, green: 0.55, blue: 0.42, alpha: 1).setStroke()
        let smile = NSBezierPath()
        smile.move(to: CGPoint(x: center.x - 35, y: center.y + 42))
        smile.curve(to: CGPoint(x: center.x + 35, y: center.y + 42), controlPoint1: CGPoint(x: center.x - 14, y: center.y + 58), controlPoint2: CGPoint(x: center.x + 14, y: center.y + 58))
        smile.lineWidth = 4
        smile.lineCapStyle = .round
        smile.stroke()

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawEye(center: CGPoint) {
        NSColor(calibratedRed: 0.67, green: 0.93, blue: 0.78, alpha: 1).setFill()
        let outer = NSBezierPath(ovalIn: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        outer.fill()
        NSColor(calibratedRed: 0.30, green: 0.61, blue: 0.47, alpha: 1).setStroke()
        outer.lineWidth = 5
        outer.stroke()

        NSColor(calibratedRed: 0.94, green: 1, blue: 0.92, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 18, y: center.y - 18, width: 36, height: 36)).fill()

        NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 10 + eyeOffset.x, y: center.y - 10 + eyeOffset.y, width: 20, height: 20)).fill()
        NSColor(calibratedRed: 0.24, green: 0.36, blue: 0.38, alpha: 0.95).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 5 + eyeOffset.x, y: center.y - 4 + eyeOffset.y, width: 8, height: 8)).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 8 + eyeOffset.x, y: center.y - 11 + eyeOffset.y, width: 8, height: 8)).fill()
        NSBezierPath(ovalIn: CGRect(x: center.x + 3 + eyeOffset.x, y: center.y + 4 + eyeOffset.y, width: 4, height: 4)).fill()
    }

    private func drawFoot(_ rect: CGRect, flip: Bool) {
        NSColor(calibratedRed: 0.45, green: 0.77, blue: 0.59, alpha: 1).setFill()
        let foot = NSBezierPath(roundedRect: rect, xRadius: 22, yRadius: 14)
        foot.fill()
        let toeY = rect.maxY - 8
        let firstToeX = flip ? rect.maxX - 26 : rect.minX + 10
        for index in 0..<3 {
            let toeX = firstToeX + CGFloat(index) * (flip ? -11 : 11)
            NSBezierPath(ovalIn: CGRect(x: toeX, y: toeY, width: 13, height: 8)).fill()
        }
        NSColor(calibratedRed: 0.30, green: 0.61, blue: 0.47, alpha: 1).setStroke()
        foot.lineWidth = 3
        foot.stroke()
    }

    private func drawArm(_ rect: CGRect, flip: Bool) {
        NSColor(calibratedRed: 0.57, green: 0.86, blue: 0.70, alpha: 1).setFill()
        let arm = NSBezierPath(roundedRect: rect, xRadius: 20, yRadius: 24)
        arm.fill()
        NSColor(calibratedRed: 0.30, green: 0.61, blue: 0.47, alpha: 1).setStroke()
        arm.lineWidth = 3
        arm.stroke()
    }

    private func drawTongue() {
        let target = ghostPoint ?? CGPoint(x: frogCenter.x - 176, y: frogCenter.y - 86)
        NSColor(calibratedRed: 0.96, green: 0.43, blue: 0.55, alpha: 1).setStroke()
        let tongue = NSBezierPath()
        tongue.move(to: CGPoint(x: frogCenter.x - 4, y: frogCenter.y + 37))
        tongue.curve(
            to: target,
            controlPoint1: CGPoint(x: frogCenter.x - 44, y: frogCenter.y + 26),
            controlPoint2: CGPoint(x: (frogCenter.x + target.x) / 2, y: target.y + 18)
        )
        tongue.lineWidth = stage == .snapping ? 15 : 11
        tongue.lineCapStyle = .round
        tongue.stroke()
        NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: target.x - 8, y: target.y - 6, width: 16, height: 12)).fill()
    }

    private func applyShadow(color: NSColor, offset: CGSize, blur: CGFloat) {
        let shadow = NSShadow()
        shadow.shadowColor = color
        shadow.shadowOffset = offset
        shadow.shadowBlurRadius = blur
        shadow.set()
    }

    private func drawText(
        _ text: String,
        in rect: CGRect,
        size: CGFloat,
        weight: NSFont.Weight,
        alignment: NSTextAlignment = .left,
        color: NSColor = .labelColor
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = alignment
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph
        ]
        text.draw(in: rect, withAttributes: attributes)
    }
}

let app = NSApplication.shared
let delegate = FileFrogAppDelegate()
app.delegate = delegate
app.run()
