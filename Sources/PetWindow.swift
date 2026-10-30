import AppKit

/// Shared geometry for rendering, pixel hit testing and old-position migration.
enum PetGeometry {
    static let size = NSSize(width: 160, height: 164)
    static let sprite = NSRect(x: 16, y: 12, width: 128, height: 128 * 208 / 192)

    static func clampedOrigin(_ origin: NSPoint, screens: [NSRect]) -> NSPoint {
        guard !screens.isEmpty else { return origin }
        let proposed = NSRect(origin: origin, size: size)
        let visible = screens.max { lhs, rhs in
            let a = lhs.intersection(proposed), b = rhs.intersection(proposed)
            let areaA = a.isEmpty ? 0 : a.width * a.height
            let areaB = b.isEmpty ? 0 : b.width * b.height
            if areaA != areaB { return areaA < areaB }
            return hypot(lhs.midX - proposed.midX, lhs.midY - proposed.midY)
                > hypot(rhs.midX - proposed.midX, rhs.midY - proposed.midY)
        }!
        return NSPoint(x: min(max(origin.x, visible.minX), max(visible.minX, visible.maxX - size.width)),
                       y: min(max(origin.y, visible.minY), max(visible.minY, visible.maxY - size.height)))
    }

    static func migratedOrigin(_ saved: NSRect) -> NSPoint {
        // v2 had a 240x310 canvas and feet 8pt above its bottom. Restore the anchor, not its size.
        if abs(saved.width - 240) < 1 && abs(saved.height - 310) < 1 {
            return NSPoint(x: saved.midX - size.width / 2, y: saved.minY + 8 - sprite.minY)
        }
        return saved.origin
    }
}

private struct PetFrame {
    let image: NSImage
    let bitmap: NSBitmapImageRep

    init?(url: URL) {
        guard let image = NSImage(contentsOf: url), let data = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: data) else { return nil }
        self.image = image
        self.bitmap = bitmap
    }

    func contains(_ point: NSPoint, mirrored: Bool) -> Bool {
        let rect = PetGeometry.sprite
        guard rect.contains(point) else { return false }
        var x = (point.x - rect.minX) / rect.width
        if mirrored { x = 1 - x }
        let px = Int(x * CGFloat(bitmap.pixelsWide))
        let py = Int((rect.maxY - point.y) / rect.height * CGFloat(bitmap.pixelsHigh))
        let radius = max(1, Int(CGFloat(bitmap.pixelsWide) / rect.width))
        for yy in max(0, py - radius)...min(bitmap.pixelsHigh - 1, py + radius) {
            for xx in max(0, px - radius)...min(bitmap.pixelsWide - 1, px + radius) {
                if (bitmap.colorAt(x: xx, y: yy)?.alphaComponent ?? 0) > 0.15 { return true }
            }
        }
        return false
    }
}

/// Native image surface. Transparent pixels never become an invisible HTML rectangle.
private final class PetSpriteView: NSView {
    var frameImage: PetFrame? { didSet { needsDisplay = true } }
    var mirrored = false { didSet { needsDisplay = true } }
    var onClick: (() -> Void)?
    var onDrag: ((NSPoint) -> Void)?
    var onRelease: (() -> Void)?
    var menuBuilder: (() -> NSMenu)?
    private(set) var holdingMouse = false
    private var didDrag = false
    private var downPoint = NSPoint.zero
    private var downOrigin = NSPoint.zero

    override var isOpaque: Bool { false }
    override var acceptsFirstResponder: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = superview.map { convert(point, from: $0) } ?? point
        return frameImage?.contains(local, mirrored: mirrored) == true ? self : nil
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)
        if let ctx = NSGraphicsContext.current?.cgContext, mirrored {
            ctx.saveGState()
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        let ground = NSBezierPath(ovalIn: NSRect(x: 31, y: 6, width: 98, height: 8))
        NSGradient(starting: NSColor.black.withAlphaComponent(0.13), ending: .clear)?
            .draw(in: ground, relativeCenterPosition: .zero)
        NSGraphicsContext.current?.imageInterpolation = .high
        frameImage?.image.draw(in: PetGeometry.sprite, from: .zero,
                               operation: .sourceOver, fraction: 1,
                               respectFlipped: true, hints: nil)
        if let ctx = NSGraphicsContext.current?.cgContext, mirrored {
            ctx.restoreGState()
        }
    }

    override func mouseDown(with event: NSEvent) {
        holdingMouse = true
        didDrag = false
        downPoint = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        window?.ignoresMouseEvents = false
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = point.x - downPoint.x, dy = point.y - downPoint.y
        if hypot(dx, dy) > 4 { didDrag = true }
        if didDrag { onDrag?(NSPoint(x: downOrigin.x + dx, y: downOrigin.y + dy)) }
    }

    override func mouseUp(with event: NSEvent) {
        let wasDrag = didDrag
        holdingMouse = false
        didDrag = false
        onRelease?()
        if !wasDrag { onClick?() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuBuilder?() }
}

/// Non-activating desktop pet: native frames, hover, roaming, drag inertia.
final class PetWindow: NSPanel {
    enum Mode { case idle, walking, sliding }

    var onClick: (() -> Void)?
    var onMoveEnd: (() -> Void)?
    var menuBuilder: (() -> NSMenu)? { didSet { spriteView.menuBuilder = menuBuilder } }
    private(set) var animationState = "idle"
    private(set) var mode: Mode = .idle
    var roamingEnabled = true
    var soundEnabled = true

    private let spriteView = PetSpriteView(frame: NSRect(origin: .zero, size: PetGeometry.size))
    private var frames: [String: [PetFrame]] = [:]
    private var animationStarted = Date.timeIntervalSinceReferenceDate
    private var displayedFrame = -1
    private var timer: Timer?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var pointerInside = false
    private var bubbleWindow: NSPanel?
    private var bubbleDismiss: DispatchWorkItem?

    // Motion / behavior
    private var velocity: CGFloat = 0
    private var walkTargetX: CGFloat?
    private var walkDirection: CGFloat = -1
    private var ambientAt = Date.timeIntervalSinceReferenceDate + 9
    private var dragSamples: [(TimeInterval, NSPoint)] = []
    private var reactionUntil: TimeInterval = 0
    private var clickSound: NSSound?
    private var lastBubbleAt: TimeInterval = 0

    private let walkSpeed: CGFloat = 42

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: PetGeometry.size),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = false
        acceptsMouseMovedEvents = true
        ignoresMouseEvents = true
        animationBehavior = .none
        title = "大肥鱼桌宠"
        contentView = spriteView
        spriteView.setAccessibilityElement(true)
        spriteView.setAccessibilityRole(.button)
        spriteView.setAccessibilityLabel("大肥鱼，打开或收起提示词工坊")
        spriteView.setAccessibilityHelp("拖动可以移动，右键打开桌宠菜单。")
        spriteView.onClick = { [weak self] in self?.handleClick() }
        spriteView.onDrag = { [weak self] origin in self?.handleDrag(to: origin) }
        spriteView.onRelease = { [weak self] in self?.handleRelease() }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: events) { [weak self] _ in
            self?.updatePointer()
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { [weak self] event in
            self?.updatePointer()
            return event
        }
    }

    deinit {
        timer?.invalidate()
        bubbleDismiss?.cancel()
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func loadUI() {
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("pet") else { return }
        for (name, count) in [("idle", 6), ("hover", 5), ("working", 6), ("success", 6), ("walk", 8)] {
            frames[name] = (0..<count).compactMap {
                PetFrame(url: directory.appendingPathComponent("fatfish-\(name)-\($0).webp"))
            }
        }
        clickSound = NSSound(named: "Tink")
        clickSound?.volume = 0.12
        setState("idle")
        let tick = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.advance(dt: 1.0 / 30.0)
        }
        RunLoop.main.add(tick, forMode: .common)
        timer = tick
    }

    func setState(_ state: String) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.setState(state) }
            return
        }
        guard frames[state]?.isEmpty == false else { return }
        if state != "walk" && mode != .idle { mode = .idle; velocity = 0; walkTargetX = nil }
        animationState = state
        animationStarted = Date.timeIntervalSinceReferenceDate
        displayedFrame = -1
        updateAnimation()
    }

    // MARK: - 交互

    private func handleClick() {
        playClickSound()
        react()
        onClick?()
    }

    private func react() {
        guard animationState == "idle" || animationState == "hover" else { return }
        reactionUntil = Date.timeIntervalSinceReferenceDate + 0.7
        setState("hover")
        if Date.timeIntervalSinceReferenceDate - lastBubbleAt > 25, Bool.random() {
            bubble(["戳我写提示词 ✨", "在呢在呢", "今天想写点什么？"].randomElement()!, seconds: 2.4)
        }
    }

    private func playClickSound() {
        guard soundEnabled else { return }
        clickSound?.stop()
        clickSound?.play()
    }

    private func handleDrag(to origin: NSPoint) {
        mode = .idle
        walkTargetX = nil
        velocity = 0
        place(at: origin)
        let now = Date.timeIntervalSinceReferenceDate
        dragSamples.append((now, frame.origin))
        if dragSamples.count > 8 { dragSamples.removeFirst() }
    }

    private func handleRelease() {
        updatePointer()
        let now = Date.timeIntervalSinceReferenceDate
        dragSamples.append((now, frame.origin))
        defer { dragSamples.removeAll() }
        guard let first = dragSamples.first, let last = dragSamples.last, last.0 - first.0 > 0.02 else {
            onMoveEnd?()
            return
        }
        let dt = CGFloat(last.0 - first.0)
        let vx = (last.1.x - first.1.x) / dt
        if abs(vx) > 90 {
            velocity = max(-1600, min(1600, vx))
            mode = .sliding
            if abs(velocity) > 160 { setState("walk") }
            spriteView.mirrored = velocity > 0
        }
        onMoveEnd?()
    }

    // MARK: - 运动

    private func advance(dt: Double) {
        let now = Date.timeIntervalSinceReferenceDate
        switch mode {
        case .walking:
            stepWalk(dt: CGFloat(dt))
        case .sliding:
            stepSlide(dt: CGFloat(dt), now: now)
        case .idle:
            break
        }
        updateAnimation()
        updatePointer()
        if animationState == "hover", !pointerInside, mode == .idle, now > reactionUntil {
            setState("idle")
        }
        if mode == .idle, roamingEnabled, !pointerInside,
           now > ambientAt, now > reactionUntil,
           animationState == "idle", frames["walk"]?.isEmpty == false {
            ambientAction(now: now)
        }
    }

    private func ambientAction(now: TimeInterval) {
        if CommandLine.arguments.contains("--debug") {
            print("AMBIENT state=\(animationState) mode=\(mode) inside=\(pointerInside)")
            fflush(stdout)
        }
        ambientAt = now + Double.random(in: 16...34)
        let canWalk = visibleFrame().width > 220
        if canWalk && Bool.random() {
            startWalk()
        } else if Bool.random() {
            wanderReaction(now: now)
        }
    }

    private func wanderReaction(now: TimeInterval) {
        setState("hover")
        reactionUntil = now + 1.1
        if now - lastBubbleAt > 120, Bool.random() {
            bubble(["好想被喂一口白饭…", "我在旁边待着，随时叫我", "写提示词记得说清「不要什么」"].randomElement()!,
                   seconds: 3.2)
        }
    }

    private func startWalk() {
        if CommandLine.arguments.contains("--debug") {
            print("STARTWALK")
            fflush(stdout)
        }
        guard let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let margin: CGFloat = 12
        let minX = visible.minX + margin
        let maxX = visible.maxX - frame.width - margin
        guard maxX > minX else { return }
        let distance = CGFloat.random(in: 52...150)
        var direction: CGFloat = Bool.random() ? 1 : -1
        if frame.minX <= minX + 16 { direction = 1 }
        if frame.minX >= maxX - 16 { direction = -1 }
        var target = frame.minX + direction * distance
        if target < minX { target = minX + distance * 0.4; direction = 1 }
        if target > maxX { target = maxX - distance * 0.4; direction = -1 }
        guard abs(target - frame.minX) > 24 else { return }
        walkDirection = direction
        walkTargetX = min(max(target, minX), maxX)
        spriteView.mirrored = direction > 0
        setState("walk")
        mode = .walking
    }

    private func stepWalk(dt: CGFloat) {
        guard let target = walkTargetX else { mode = .idle; return }
        let step = walkSpeed * dt * walkDirection
        let next = frame.minX + step
        if (walkDirection > 0 && next >= target) || (walkDirection < 0 && next <= target) {
            place(at: NSPoint(x: target, y: frame.minY))
            walkTargetX = nil
            mode = .idle
            setState("idle")
            onMoveEnd?()
        } else {
            place(at: NSPoint(x: next, y: frame.minY))
            if next <= visibleFrame().minX + 2 || next >= visibleFrame().maxX - frame.width - 2 {
                walkTargetX = nil
                mode = .idle
                setState("idle")
            }
        }
    }

    private func stepSlide(dt: CGFloat, now: TimeInterval) {
        let next = frame.minX + velocity * dt
        let visible = visibleFrame()
        let minX = visible.minX + 2
        let maxX = visible.maxX - frame.width - 2
        if next < minX {
            place(at: NSPoint(x: minX, y: frame.minY))
            velocity = abs(velocity) * 0.42
            spriteView.mirrored = true
        } else if next > maxX {
            place(at: NSPoint(x: maxX, y: frame.minY))
            velocity = -abs(velocity) * 0.42
            spriteView.mirrored = false
        } else {
            place(at: NSPoint(x: next, y: frame.minY))
            velocity *= pow(0.04, CGFloat(dt))
        }
        if abs(velocity) < 26 {
            velocity = 0
            mode = .idle
            setState("idle")
            onMoveEnd?()
        }
    }

    private func visibleFrame() -> NSRect {
        (screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    // MARK: - 动画

    private func updateAnimation() {
        guard let images = frames[animationState], !images.isEmpty else { return }
        let elapsed = Date.timeIntervalSinceReferenceDate - animationStarted
        let index: Int
        switch animationState {
        case "idle":
            let phase = elapsed.truncatingRemainder(dividingBy: 4.8)
            index = phase < 4.05 ? 0 : min(images.count - 1, Int((phase - 4.05) * 8))
        case "walk":
            index = Int(elapsed * 11) % images.count
        case "hover":
            index = Int(elapsed * 10) % images.count
        case "working":
            index = Int(elapsed * 8) % images.count
        default:
            let step = Int(elapsed * 9)
            if step >= images.count {
                setState("idle")
                return
            }
            index = step
        }
        if index != displayedFrame {
            spriteView.frameImage = images[index]
            displayedFrame = index
        }
    }

    private func updatePointer() {
        guard isVisible else { return }
        if spriteView.holdingMouse { ignoresMouseEvents = false; return }
        let point = spriteView.convert(convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let inside = spriteView.frameImage?.contains(point, mirrored: spriteView.mirrored) == true
        // hitTest(nil) only changes view dispatch; ignore at the window level to reach other apps.
        ignoresMouseEvents = !inside
        guard inside != pointerInside else { return }
        pointerInside = inside
        guard mode == .idle else { return }
        if inside && animationState == "idle" {
            setState("hover")
        } else if !inside && animationState == "hover" {
            setState("idle")
        }
    }

    /// 让桌宠立刻走两步（菜单 / 自测用）。
    func walkNow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.walkNow() }
            return
        }
        guard mode == .idle else { return }
        ambientAt = Date.timeIntervalSinceReferenceDate + 18
        startWalk()
    }

    /// 播放一次点击反应（不触发面板）。
    func reactNow() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.reactNow() }
            return
        }
        react()
    }

    // MARK: - 位置与气泡

    func place(at origin: NSPoint) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.place(at: origin) }
            return
        }
        let point = PetGeometry.clampedOrigin(origin, screens: NSScreen.screens.map(\.visibleFrame))
        setFrameOrigin(point)
        positionBubble()
    }

    func bubble(_ text: String, seconds: Double = 3.0) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.bubble(text, seconds: seconds) }
            return
        }
        bubbleDismiss?.cancel()
        bubbleWindow?.orderOut(nil)
        guard !text.isEmpty, isVisible else { return }
        lastBubbleAt = Date.timeIntervalSinceReferenceDate
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 11.5)
        label.textColor = .labelColor
        label.alignment = .center
        label.maximumNumberOfLines = 4
        let maxWidth: CGFloat = 268
        let attrs: [NSAttributedString.Key: Any] = [.font: label.font!]
        let oneLine = (text as NSString).size(withAttributes: attrs)
        let width: CGFloat = min(maxWidth, max(96, ceil(oneLine.width) + 24))
        let measured = (text as NSString).boundingRect(
            with: NSSize(width: width - 24, height: 120),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attrs)
        let height = min(84, max(17, measured.height))
        let size = NSSize(width: width, height: ceil(height) + 18)
        let effect = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effect.material = .popover
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.wantsLayer = true
        effect.layer?.cornerRadius = 11
        effect.layer?.masksToBounds = true
        label.frame = NSRect(x: 12, y: 9, width: width - 24, height: height)
        effect.addSubview(label)
        let bubble = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        bubble.isOpaque = false
        bubble.backgroundColor = .clear
        bubble.hasShadow = true
        bubble.level = NSWindow.Level(rawValue: level.rawValue + 1)
        bubble.collectionBehavior = collectionBehavior
        bubble.hidesOnDeactivate = false
        bubble.isReleasedWhenClosed = false
        bubble.ignoresMouseEvents = true
        bubble.contentView = effect
        bubbleWindow = bubble
        positionBubble()
        bubble.orderFrontRegardless()
        let dismiss = DispatchWorkItem { [weak self] in self?.bubbleWindow?.orderOut(nil) }
        bubbleDismiss = dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.2, seconds), execute: dismiss)
    }

    private func positionBubble() {
        guard let bubble = bubbleWindow, let visible = (screen ?? NSScreen.main)?.visibleFrame else { return }
        let x = min(max(frame.midX - bubble.frame.width / 2, visible.minX + 8), visible.maxX - bubble.frame.width - 8)
        let above = frame.maxY + 5
        let y = above + bubble.frame.height <= visible.maxY - 8 ? above : frame.minY - bubble.frame.height - 5
        bubble.setFrameOrigin(NSPoint(x: x, y: max(visible.minY + 8, y)))
    }

    override func orderOut(_ sender: Any?) {
        bubbleDismiss?.cancel()
        bubbleWindow?.orderOut(nil)
        pointerInside = false
        mode = .idle
        velocity = 0
        super.orderOut(sender)
    }
}
