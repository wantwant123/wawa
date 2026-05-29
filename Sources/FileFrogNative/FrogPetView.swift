import AppKit

final class FrogPetView: NSView {
    var onOpenWorkspace: ((ProcessedDocument) -> Void)?
    var onLibraryChanged: (() -> Void)?

    private let detectRadius: CGFloat = 170
    private let eatRadius: CGFloat = 112
    private let processor: DocumentProcessor
    private let store: DocumentStore
    private var stage: FrogStage = .idle {
        didSet {
            if oldValue != stage {
                stageStartedAt = Date()
            }
            needsDisplay = true
        }
    }
    private var draggedFile: DroppedFile?
    private var capturedFile: DroppedFile?
    private var resultDocument: ProcessedDocument?
    private var ghostPoint: CGPoint?
    private var progress: Int?
    private var errorMessage: String?
    private var eyeOffset = CGPoint.zero
    private var animationTimers: [Timer] = []
    private var renderTimer: Timer?
    private var processingTask: Task<Void, Never>?
    private var processingRunID = UUID()
    private let animationStart = Date()
    private var stageStartedAt = Date()
    private var dragWindowStart: CGPoint?
    private var dragMouseStart: CGPoint?
    private var showsDebugFrame = ProcessInfo.processInfo.environment["FILE_FROG_DEBUG"] == "1"

    override var isFlipped: Bool {
        true
    }

    init(frame frameRect: NSRect, processor: DocumentProcessor, store: DocumentStore) {
        self.processor = processor
        self.store = store
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
        processingTask?.cancel()
        clearTimers()
    }

    func toggleDebugFrame() {
        showsDebugFrame.toggle()
        needsDisplay = true
    }

    func resetToIdle(keepResult: Bool = false) {
        processingTask?.cancel()
        processingTask = nil
        processingRunID = UUID()
        clearTimers()
        draggedFile = nil
        ghostPoint = nil
        progress = nil
        errorMessage = nil
        eyeOffset = .zero
        if !keepResult {
            capturedFile = nil
            resultDocument = nil
        }
        stage = .idle
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
        let point = convert(event.locationInWindow, from: nil)
        if stage == .resultReady, let resultDocument, resultCardRect.contains(point) {
            if event.clickCount >= 2 {
                resetToIdle()
            } else {
                onOpenWorkspace?(resultDocument)
            }
            return
        }

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
        guard canAcceptFileDrop else { return [] }
        updateDrag(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAcceptFileDrop else { return [] }
        updateDrag(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        if stage == .trackingFile || stage == .readyToEat {
            resetDragState()
        }
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard canAcceptFileDrop else { return false }
        guard let file = readDroppedFile(sender), let url = file.url else {
            showFailure("文件读不出来", stage: .failed)
            return false
        }

        let point = convert(sender.draggingLocation, from: nil)
        draggedFile = file
        ghostPoint = point

        guard distanceToFrog(point) <= eatRadius else {
            stage = .trackingFile
            schedule(after: 0.7) { [weak self] in
                self?.resetDragState()
            }
            return false
        }

        guard file.fileKind == .pdf || file.fileKind == .plainText || file.fileKind == .markdown else {
            let message = file.fileKind == .word ? "Word 我先认得，还不会深读" : "这个我还不会读"
            showFailure(message, stage: .unsupported)
            return false
        }

        capturedFile = file
        runProcessingSequence(url: url)
        return true
    }

    private var frogCenter: CGPoint {
        CGPoint(x: bounds.midX + 66, y: bounds.midY + 62)
    }

    private var resultCardRect: CGRect {
        CGRect(x: frogCenter.x - 224, y: frogCenter.y - 178, width: 250, height: 132)
    }

    private var stageElapsed: TimeInterval {
        Date().timeIntervalSince(stageStartedAt)
    }

    private var canAcceptFileDrop: Bool {
        switch stage {
        case .snapping, .chewing, .extracting, .summarizing, .findingRisks, .finishing:
            return false
        case .idle, .trackingFile, .readyToEat, .resultReady, .unsupported, .failed:
            return true
        }
    }

    private func updateDrag(_ sender: NSDraggingInfo) {
        let point = convert(sender.draggingLocation, from: nil)
        if stage == .unsupported || stage == .failed {
            clearTimers()
            errorMessage = nil
        }
        ghostPoint = point
        draggedFile = readDroppedFile(sender) ?? DroppedFile(name: "外部文件", size: 0, url: nil, fileKind: .unsupported)
        if stage == .resultReady {
            resultDocument = nil
            capturedFile = nil
        }

        let dx = point.x - frogCenter.x
        let dy = point.y - frogCenter.y
        let length = max(1, sqrt(dx * dx + dy * dy))
        eyeOffset = CGPoint(x: dx / length * 3.5, y: dy / length * 3.5)

        let distance = distanceToFrog(point)
        if distance <= eatRadius {
            stage = .readyToEat
        } else if distance <= detectRadius {
            stage = .trackingFile
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
        return DroppedFile(
            name: url.lastPathComponent,
            size: size,
            url: url,
            fileKind: FileKind.from(url: url)
        )
    }

    private func distanceToFrog(_ point: CGPoint) -> CGFloat {
        hypot(point.x - frogCenter.x, point.y - frogCenter.y)
    }

    private func runProcessingSequence(url: URL) {
        processingTask?.cancel()
        clearTimers()
        let runID = UUID()
        processingRunID = runID
        resultDocument = nil
        errorMessage = nil
        stage = .snapping
        progress = nil

        schedule(after: 0.24, runID: runID) { [weak self] in
            self?.stage = .chewing
        }
        schedule(after: 0.64, runID: runID) { [weak self] in
            self?.draggedFile = nil
            self?.ghostPoint = nil
            self?.startProgressTicker(from: 18, cap: 62)
            self?.stage = .extracting
        }

        processingTask = Task { [weak self] in
            guard let self else { return }
            do {
                let document = try await processor.process(url: url)
                if Task.isCancelled { return }
                try store.save(document)
                await MainActor.run {
                    guard self.processingRunID == runID else { return }
                    self.onLibraryChanged?()
                    self.finishProcessing(document, runID: runID)
                }
            } catch {
                if Task.isCancelled { return }
                let message = (error as? LocalizedError)?.errorDescription ?? "读文件时出错了"
                await MainActor.run {
                    guard self.processingRunID == runID else { return }
                    self.showFailure(message, stage: .failed)
                }
            }
        }
    }

    private func showFailure(_ message: String, stage: FrogStage) {
        processingTask?.cancel()
        clearTimers()
        progress = nil
        errorMessage = message
        draggedFile = nil
        ghostPoint = nil
        self.stage = stage
        schedule(after: 3.0) { [weak self] in
            self?.resetToIdle()
        }
    }

    private func resetDragState() {
        draggedFile = nil
        ghostPoint = nil
        progress = nil
        errorMessage = nil
        eyeOffset = .zero
        stage = .idle
    }

    private func clearTimers() {
        animationTimers.forEach { $0.invalidate() }
        animationTimers.removeAll()
    }

    private func schedule(after delay: TimeInterval, runID: UUID? = nil, _ action: @escaping () -> Void) {
        let timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self else { return }
            if let runID, runID != self.processingRunID {
                return
            }
            action()
        }
        animationTimers.append(timer)
    }

    private func startProgressTicker(from start: Int, cap: Int) {
        progress = start
        let timer = Timer.scheduledTimer(withTimeInterval: 0.22, repeats: true) { [weak self] _ in
            guard let self, let progress = self.progress else { return }
            guard progress < cap else { return }
            let step = progress < 36 ? 5 : 3
            self.progress = min(cap, progress + step)
        }
        animationTimers.append(timer)
    }

    private func finishProcessing(_ document: ProcessedDocument, runID: UUID) {
        clearTimers()
        progress = 68
        stage = .summarizing

        schedule(after: 0.42, runID: runID) { [weak self] in
            self?.progress = 84
            self?.stage = .findingRisks
        }
        schedule(after: 0.86, runID: runID) { [weak self] in
            self?.progress = 96
            self?.stage = .finishing
        }
        schedule(after: 1.24, runID: runID) { [weak self] in
            self?.progress = nil
            self?.resultDocument = document
            self?.stage = .resultReady
            self?.eyeOffset = .zero
        }
    }

    private func startRenderLoop() {
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            if stage != .idle || draggedFile != nil || resultDocument != nil {
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
        guard draggedFile != nil || stage == .trackingFile || stage == .readyToEat || stage == .extracting || stage == .summarizing || stage == .findingRisks || stage == .finishing else {
            return
        }
        let ready = stage == .readyToEat || stage == .extracting || stage == .summarizing || stage == .findingRisks || stage == .finishing
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
        let snapScale = stage == .snapping ? max(0.18, 1.0 - CGFloat(stageElapsed / 0.28) * 0.72) : 1
        let pull = stage == .snapping ? CGFloat(min(1, stageElapsed / 0.22)) : 0
        let displayPoint = CGPoint(
            x: point.x + (frogCenter.x - point.x) * pull * 0.58,
            y: point.y + (frogCenter.y + 20 - point.y) * pull * 0.58
        )
        let alpha = stage == .snapping ? max(0.08, 1 - CGFloat(stageElapsed / 0.35)) : 1
        NSGraphicsContext.current?.cgContext.setAlpha(alpha)

        let transform = NSAffineTransform()
        transform.translateX(by: displayPoint.x, yBy: displayPoint.y)
        transform.scale(by: snapScale)
        transform.translateX(by: -displayPoint.x, yBy: -displayPoint.y)
        transform.concat()

        applyShadow(color: NSColor.black.withAlphaComponent(0.22), offset: CGSize(width: 0, height: -8), blur: 16)

        let paper = CGRect(x: displayPoint.x - 34, y: displayPoint.y - 48, width: 68, height: 78)
        let badgeColor: NSColor
        switch file.fileKind {
        case .pdf:
            badgeColor = .systemRed
        case .plainText, .markdown:
            badgeColor = .systemTeal
        case .word:
            badgeColor = .systemBlue
        case .unsupported:
            badgeColor = .gray
        }
        badgeColor.setFill()
        NSBezierPath(roundedRect: paper, xRadius: 6, yRadius: 6).fill()

        NSColor(calibratedWhite: 1.0, alpha: 0.92).setStroke()
        let outline = NSBezierPath(roundedRect: paper, xRadius: 6, yRadius: 6)
        outline.lineWidth = 2
        outline.stroke()

        NSColor.white.setFill()
        drawText(file.badge, in: paper.offsetBy(dx: 0, dy: 22), size: 15, weight: .bold, alignment: .center)
        drawText(file.name, in: CGRect(x: displayPoint.x - 62, y: displayPoint.y + 34, width: 124, height: 18), size: 11, weight: .semibold, alignment: .center, color: .white)
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBubble() {
        let message = errorMessage ?? stage.message
        guard let message else { return }
        let rect = CGRect(x: frogCenter.x - 82, y: frogCenter.y - 150, width: 164, height: progress == nil ? 36 : 52)
        NSGraphicsContext.saveGraphicsState()
        applyShadow(color: NSColor.black.withAlphaComponent(0.12), offset: CGSize(width: 0, height: -5), blur: 12)
        let isError = stage == .failed || stage == .unsupported
        (isError
            ? NSColor(calibratedRed: 1.0, green: 0.89, blue: 0.76, alpha: 0.96)
            : NSColor(calibratedRed: 0.93, green: 1.0, blue: 0.74, alpha: 0.94)
        ).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 17, yRadius: 17).fill()
        NSGraphicsContext.restoreGraphicsState()
        drawText(message, in: rect.insetBy(dx: 10, dy: 7), size: 12, weight: .bold, alignment: .center, color: NSColor(calibratedRed: 0.1, green: 0.25, blue: 0.18, alpha: 1))
        if let progress {
            drawText("\(progress)%", in: rect.insetBy(dx: 10, dy: 28), size: 11, weight: .bold, alignment: .center, color: NSColor(calibratedRed: 0.36, green: 0.48, blue: 0.12, alpha: 1))
        }
    }

    private func drawResultCard() {
        guard stage == .resultReady, let document = resultDocument else { return }
        var rect = resultCardRect
        let appear = easeOutBack(min(1, CGFloat(stageElapsed / 0.52)))
        rect.origin.y += (1 - appear) * 30

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(max(0, min(1, appear)))
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX, yBy: rect.midY)
        transform.scale(by: 0.84 + appear * 0.16)
        transform.translateX(by: -rect.midX, yBy: -rect.midY)
        transform.concat()

        applyShadow(color: NSColor.black.withAlphaComponent(0.18), offset: CGSize(width: 0, height: -8), blur: 18)
        let card = NSBezierPath()
        card.move(to: CGPoint(x: rect.minX + 20, y: rect.midY))
        card.curve(to: CGPoint(x: rect.minX + 70, y: rect.minY + 10), controlPoint1: CGPoint(x: rect.minX + 28, y: rect.minY + 30), controlPoint2: CGPoint(x: rect.minX + 44, y: rect.minY + 10))
        card.line(to: CGPoint(x: rect.maxX - 28, y: rect.minY + 10))
        card.curve(to: CGPoint(x: rect.maxX - 12, y: rect.midY + 4), controlPoint1: CGPoint(x: rect.maxX - 8, y: rect.minY + 24), controlPoint2: CGPoint(x: rect.maxX - 4, y: rect.midY - 2))
        card.curve(to: CGPoint(x: rect.maxX - 60, y: rect.maxY - 8), controlPoint1: CGPoint(x: rect.maxX - 24, y: rect.maxY - 2), controlPoint2: CGPoint(x: rect.maxX - 44, y: rect.maxY))
        card.line(to: CGPoint(x: rect.minX + 58, y: rect.maxY - 10))
        card.curve(to: CGPoint(x: rect.minX + 20, y: rect.midY), controlPoint1: CGPoint(x: rect.minX + 32, y: rect.maxY - 10), controlPoint2: CGPoint(x: rect.minX + 12, y: rect.maxY - 4))
        card.close()
        NSGradient(
            starting: NSColor(calibratedRed: 0.90, green: 1.0, blue: 0.64, alpha: 0.98),
            ending: NSColor(calibratedRed: 0.68, green: 0.91, blue: 0.39, alpha: 0.96)
        )?.draw(in: card, angle: -18)

        drawText("理解完成 · \(document.record.fileKind.displayName) · \(document.record.sizeLabel)", in: CGRect(x: rect.minX + 26, y: rect.minY + 18, width: rect.width - 52, height: 16), size: 10, weight: .bold, color: NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.16, alpha: 1))
        drawText(document.record.fileName, in: CGRect(x: rect.minX + 26, y: rect.minY + 38, width: rect.width - 52, height: 20), size: 14, weight: .bold, color: NSColor(calibratedRed: 0.09, green: 0.22, blue: 0.1, alpha: 1))
        drawText(document.summary.oneLineSummary, in: CGRect(x: rect.minX + 26, y: rect.minY + 62, width: rect.width - 52, height: 34), size: 10, weight: .regular, color: NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.12, alpha: 0.88))
        let riskText = document.summary.risks.isEmpty ? "未发现明显风险" : "\(document.summary.risks.count) 处风险"
        drawText("打开理解窗口 · \(document.summary.keyPoints.count) 个要点 · \(riskText)", in: CGRect(x: rect.minX + 26, y: rect.minY + 103, width: rect.width - 52, height: 18), size: 10, weight: .semibold, color: NSColor(calibratedRed: 0.14, green: 0.32, blue: 0.14, alpha: 0.82))
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawFrog() {
        let center = frogCenter
        let phase = Date().timeIntervalSince(animationStart)
        let breath = CGFloat(sin(phase * 2.2))
        let chew = CGFloat(sin(phase * 13.0))
        let think = CGFloat(sin(phase * 4.4))
        let shake = (stage == .failed || stage == .unsupported) ? CGFloat(sin(stageElapsed * 28.0) * max(0, 1 - stageElapsed / 0.8)) : 0
        let hop = stage == .finishing ? -abs(CGFloat(sin(stageElapsed * 10.0))) * max(0, 1 - CGFloat(stageElapsed / 0.9)) * 8 : 0
        let scale: CGFloat
        switch stage {
        case .readyToEat:
            scale = 1.035
        case .chewing:
            scale = 1.02 + abs(chew) * 0.028
        case .extracting:
            scale = 1.02 + abs(breath) * 0.018
        case .summarizing, .findingRisks:
            scale = 1.015 + abs(think) * 0.012
        case .finishing:
            scale = 1.04 + abs(breath) * 0.012
        case .unsupported, .failed:
            scale = 0.985
        default:
            scale = 1.0 + breath * 0.012
        }
        let squash: CGFloat
        switch stage {
        case .readyToEat:
            squash = 0.955
        case .chewing:
            squash = 0.985 + abs(chew) * 0.026
        case .snapping:
            squash = 0.94
        default:
            squash = 1.0
        }

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: shake * 5, yBy: hop)
        if stage == .trackingFile || stage == .readyToEat {
            transform.translateX(by: eyeOffset.x * 1.2, yBy: eyeOffset.y * 0.8)
        }
        if stage == .summarizing || stage == .findingRisks {
            transform.rotate(byDegrees: think * 1.4)
        }
        transform.translateX(by: center.x, yBy: center.y + 92)
        transform.scaleX(by: scale, yBy: scale * squash)
        transform.translateX(by: -center.x, yBy: -(center.y + 92))
        transform.concat()

        NSColor(calibratedWhite: 0, alpha: 0.13).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 86, y: center.y + 94, width: 172, height: 24)).fill()

        drawFoot(CGRect(x: center.x - 94, y: center.y + 72, width: 68, height: 36), flip: false)
        drawFoot(CGRect(x: center.x + 26, y: center.y + 72, width: 68, height: 36), flip: true)
        drawBody(center: center)
        drawArm(CGRect(x: center.x - 91, y: center.y + 28, width: 45, height: 64), flip: false)
        drawArm(CGRect(x: center.x + 46, y: center.y + 28, width: 45, height: 64), flip: true)

        NSColor(calibratedRed: 1.0, green: 0.89, blue: 0.62, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 58, y: center.y + 28, width: 116, height: 72)).fill()

        drawEye(center: CGPoint(x: center.x - 39, y: center.y - 33))
        drawEye(center: CGPoint(x: center.x + 39, y: center.y - 33))
        drawBridgeAndFace(center: center)
        drawMouth(center: center)

        if stage == .snapping {
            drawTongue()
        }

        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawBody(center: CGPoint) {
        let body = NSBezierPath()
        body.move(to: CGPoint(x: center.x, y: center.y - 62))
        body.curve(to: CGPoint(x: center.x - 92, y: center.y + 28), controlPoint1: CGPoint(x: center.x - 56, y: center.y - 64), controlPoint2: CGPoint(x: center.x - 94, y: center.y - 20))
        body.curve(to: CGPoint(x: center.x - 66, y: center.y + 96), controlPoint1: CGPoint(x: center.x - 100, y: center.y + 62), controlPoint2: CGPoint(x: center.x - 92, y: center.y + 86))
        body.curve(to: CGPoint(x: center.x + 66, y: center.y + 96), controlPoint1: CGPoint(x: center.x - 30, y: center.y + 122), controlPoint2: CGPoint(x: center.x + 30, y: center.y + 122))
        body.curve(to: CGPoint(x: center.x + 92, y: center.y + 28), controlPoint1: CGPoint(x: center.x + 92, y: center.y + 86), controlPoint2: CGPoint(x: center.x + 100, y: center.y + 62))
        body.curve(to: CGPoint(x: center.x, y: center.y - 62), controlPoint1: CGPoint(x: center.x + 94, y: center.y - 20), controlPoint2: CGPoint(x: center.x + 56, y: center.y - 64))
        body.close()
        NSGradient(starting: NSColor(calibratedRed: 0.78, green: 0.98, blue: 0.86, alpha: 1), ending: NSColor(calibratedRed: 0.40, green: 0.73, blue: 0.56, alpha: 1))?.draw(in: body, angle: -68)
        NSColor(calibratedRed: 0.30, green: 0.61, blue: 0.47, alpha: 1).setStroke()
        body.lineWidth = 4
        body.stroke()

        NSColor(calibratedRed: 0.95, green: 1.0, blue: 0.9, alpha: 0.20).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 48, y: center.y - 26, width: 96, height: 40)).fill()
    }

    private func drawBridgeAndFace(center: CGPoint) {
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
    }

    private func drawMouth(center: CGPoint) {
        NSColor(calibratedRed: 0.28, green: 0.55, blue: 0.42, alpha: 1).setStroke()
        switch stage {
        case .readyToEat, .snapping:
            NSColor(calibratedRed: 0.36, green: 0.38, blue: 0.30, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - 25, y: center.y + 32, width: 50, height: 23)).fill()
            NSColor(calibratedRed: 0.96, green: 0.43, blue: 0.55, alpha: 0.55).setFill()
            NSBezierPath(ovalIn: CGRect(x: center.x - 15, y: center.y + 42, width: 30, height: 10)).fill()
        case .chewing:
            let chew = CGFloat(sin(Date().timeIntervalSince(animationStart) * 13.0))
            let mouth = NSBezierPath()
            mouth.move(to: CGPoint(x: center.x - 26, y: center.y + 44 + chew * 2))
            mouth.curve(to: CGPoint(x: center.x + 26, y: center.y + 44 - chew * 2), controlPoint1: CGPoint(x: center.x - 10, y: center.y + 54), controlPoint2: CGPoint(x: center.x + 10, y: center.y + 34))
            mouth.lineWidth = 4
            mouth.lineCapStyle = .round
            mouth.stroke()
        case .unsupported, .failed:
            let frown = NSBezierPath()
            frown.move(to: CGPoint(x: center.x - 28, y: center.y + 54))
            frown.curve(to: CGPoint(x: center.x + 28, y: center.y + 54), controlPoint1: CGPoint(x: center.x - 10, y: center.y + 40), controlPoint2: CGPoint(x: center.x + 10, y: center.y + 40))
            frown.lineWidth = 4
            frown.lineCapStyle = .round
            frown.stroke()
        default:
            let smile = NSBezierPath()
            smile.move(to: CGPoint(x: center.x - 35, y: center.y + 42))
            smile.curve(to: CGPoint(x: center.x + 35, y: center.y + 42), controlPoint1: CGPoint(x: center.x - 14, y: center.y + 58), controlPoint2: CGPoint(x: center.x + 14, y: center.y + 58))
            smile.lineWidth = 4
            smile.lineCapStyle = .round
            smile.stroke()
        }
    }

    private func drawEye(center: CGPoint) {
        NSColor(calibratedRed: 0.67, green: 0.93, blue: 0.78, alpha: 1).setFill()
        let outer = NSBezierPath(ovalIn: CGRect(x: center.x - 30, y: center.y - 30, width: 60, height: 60))
        outer.fill()
        NSColor(calibratedRed: 0.30, green: 0.61, blue: 0.47, alpha: 1).setStroke()
        outer.lineWidth = 5
        outer.stroke()

        let blink = blinkScale()
        let innerRect = CGRect(x: center.x - 18, y: center.y - 18 + (1 - blink) * 16, width: 36, height: max(3, 36 * blink))
        NSColor(calibratedRed: 0.94, green: 1, blue: 0.92, alpha: 1).setFill()
        NSBezierPath(ovalIn: innerRect).fill()
        guard blink > 0.18 else { return }

        let thinkingOffset: CGPoint
        if stage == .summarizing || stage == .findingRisks {
            thinkingOffset = CGPoint(x: CGFloat(sin(Date().timeIntervalSince(animationStart) * 2.3)) * 2, y: -5)
        } else if stage == .unsupported || stage == .failed {
            thinkingOffset = CGPoint(x: -2, y: 2)
        } else {
            thinkingOffset = eyeOffset
        }
        NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.17, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 10 + thinkingOffset.x, y: center.y - 10 + thinkingOffset.y + (1 - blink) * 10, width: 20, height: max(3, 20 * blink))).fill()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: center.x - 8 + thinkingOffset.x, y: center.y - 11 + thinkingOffset.y, width: 8, height: max(2, 8 * blink))).fill()
        NSBezierPath(ovalIn: CGRect(x: center.x + 3 + thinkingOffset.x, y: center.y + 4 + thinkingOffset.y, width: 4, height: max(1, 4 * blink))).fill()
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
        let reach = easeOutCubic(min(1, CGFloat(stageElapsed / 0.18)))
        let retract = max(0, CGFloat((stageElapsed - 0.18) / 0.18))
        let visible = max(0, 1 - retract * 0.7)
        let tongueTarget = CGPoint(
            x: frogCenter.x + (target.x - frogCenter.x) * reach,
            y: frogCenter.y + 37 + (target.y - (frogCenter.y + 37)) * reach
        )
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.cgContext.setAlpha(visible)
        NSColor(calibratedRed: 0.96, green: 0.43, blue: 0.55, alpha: 1).setStroke()
        let tongue = NSBezierPath()
        tongue.move(to: CGPoint(x: frogCenter.x - 4, y: frogCenter.y + 37))
        tongue.curve(to: tongueTarget, controlPoint1: CGPoint(x: frogCenter.x - 44, y: frogCenter.y + 26), controlPoint2: CGPoint(x: (frogCenter.x + tongueTarget.x) / 2, y: tongueTarget.y + 18))
        tongue.lineWidth = 12 + reach * 4
        tongue.lineCapStyle = .round
        tongue.stroke()
        NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.68, alpha: 1).setFill()
        NSBezierPath(ovalIn: CGRect(x: tongueTarget.x - 8, y: tongueTarget.y - 6, width: 16, height: 12)).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    private func blinkScale() -> CGFloat {
        if stage == .snapping || stage == .chewing {
            return 1
        }

        let cycle = Date().timeIntervalSince(animationStart).truncatingRemainder(dividingBy: 4.8)
        let blinkWindow = 0.18
        if cycle < blinkWindow {
            return max(0.08, abs(CGFloat(cycle / blinkWindow) - 0.5) * 2)
        }
        return 1
    }

    private func easeOutCubic(_ value: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, value))
        return 1 - pow(1 - clamped, 3)
    }

    private func easeOutBack(_ value: CGFloat) -> CGFloat {
        let clamped = max(0, min(1, value))
        let c1: CGFloat = 1.70158
        let c3 = c1 + 1
        return 1 + c3 * pow(clamped - 1, 3) + c1 * pow(clamped - 1, 2)
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
