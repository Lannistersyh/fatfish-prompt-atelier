import AppKit
import WebKit

/// 卡片尺寸与外观的统一定义（Swift 侧只镜像 CSS 变量，不另造一套数值）。
enum PanelMetrics {
    static let minSize = NSSize(width: 380, height: 480)
    static let maxSize = NSSize(width: 1000, height: 1000)
    static let defaultSize = NSSize(width: 470, height: 726)
    static let defaultOpacity: CGFloat = 0.8
    static let cardInset: CGFloat = 16
    static let cardRadius: CGFloat = 28
    static let sizeKey = "panel.size"
    static let opacityKey = "panel.opacity"

    static func clamp(_ size: NSSize) -> NSSize {
        NSSize(width: min(maxSize.width, max(minSize.width, size.width.rounded())),
               height: min(maxSize.height, max(minSize.height, size.height.rounded())))
    }

    /// 再把尺寸夹到当前屏幕可见区域内，避免窗口跑到屏幕外。
    static func clampToScreen(_ size: NSSize, screen: NSScreen?) -> NSSize {
        let visible = (screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let cap = NSSize(width: min(maxSize.width, visible.width - 24),
                         height: min(maxSize.height, visible.height - 24))
        return clamp(NSSize(width: min(size.width, cap.width), height: min(size.height, cap.height)))
    }

    static func savedSize() -> NSSize {
        guard let raw = UserDefaults.standard.string(forKey: sizeKey) else { return defaultSize }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return defaultSize }
        return clamp(NSSize(width: parts[0], height: parts[1]))
    }

    static func savedOpacity() -> CGFloat {
        guard UserDefaults.standard.object(forKey: opacityKey) != nil else { return defaultOpacity }
        return min(1, max(0, CGFloat(UserDefaults.standard.double(forKey: opacityKey))))
    }
}

/// 提示词工坊面板：磨砂卡片 + WKWebView。
final class PanelWindow: NSPanel, WKNavigationDelegate {
    let webView: WKWebView

    private let effectView: NSVisualEffectView
    private let dragHandle: NSView
    private let resizeGrip: ResizeGripView
    private let cardInset = PanelMetrics.cardInset
    private(set) var cardOpacity = PanelMetrics.savedOpacity()
    private var resizeAnchor: NSPoint = .zero

    init(size: NSSize? = nil) {
        let startSize = PanelMetrics.clamp(size ?? PanelMetrics.savedSize())
        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        webView = WKWebView(frame: .zero, configuration: config)
        effectView = NSVisualEffectView(frame: .zero)
        dragHandle = DragView(frame: .zero)
        resizeGrip = ResizeGripView(frame: .zero)

        super.init(contentRect: NSRect(origin: .zero, size: startSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        let root = NSView(frame: NSRect(origin: .zero, size: startSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = NSColor.clear.cgColor
        contentView = root

        // 毛玻璃只负责「背后模糊」；描边与透明度统一由 CSS 画，避免双层边。
        effectView.frame = root.bounds.insetBy(dx: cardInset, dy: cardInset)
        effectView.autoresizingMask = [.width, .height]
        effectView.material = .popover
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = PanelMetrics.cardRadius
        effectView.layer?.masksToBounds = true
        effectView.layer?.borderWidth = 0
        root.addSubview(effectView)

        webView.frame = root.bounds
        webView.autoresizingMask = [.width, .height]
        webView.wantsLayer = true
        webView.layer?.backgroundColor = NSColor.clear.cgColor
        webView.navigationDelegate = self
        // WKWebView 默认会在页面背后画一层不透明白底，露出「白色直角边框」。
        // 公开 API 的 underPageBackgroundColor 只管滚动越界区域，关不掉这层；
        // 这里走 KVC 到私有 setter（先 responds 守卫，缺该 setter 的系统上安全降级为白底）。
        if webView.responds(to: NSSelectorFromString("_setDrawsBackground:")) {
            webView.setValue(false, forKey: "drawsBackground")
        } else {
            NSLog("WKWebView._setDrawsBackground 不可用，卡片外可能露出白底")
        }
        webView.underPageBackgroundColor = .clear
        root.addSubview(webView)

        dragHandle.frame = NSRect(x: cardInset,
                                  y: startSize.height - cardInset - 58,
                                  width: startSize.width - cardInset * 2 - 116,
                                  height: 58)
        dragHandle.autoresizingMask = [.minYMargin, .width]
        root.addSubview(dragHandle)

        resizeGrip.frame = NSRect(x: startSize.width - cardInset - 20,
                                  y: cardInset,
                                  width: 20,
                                  height: 20)
        resizeGrip.autoresizingMask = [.minXMargin, .maxYMargin]
        resizeGrip.onBeginDrag = { [weak self] in
            guard let self else { return }
            self.resizeAnchor = NSPoint(x: self.frame.minX, y: self.frame.maxY)
        }
        resizeGrip.onDragSize = { [weak self] proposed in
            guard let self else { return }
            let clamped = PanelMetrics.clampToScreen(proposed, screen: self.screen)
            self.setFrame(NSRect(x: self.resizeAnchor.x,
                                 y: self.resizeAnchor.y - clamped.height,
                                 width: clamped.width,
                                 height: clamped.height),
                          display: true)
            self.persistAppearance()
            self.syncAppearanceToWeb()
        }
        root.addSubview(resizeGrip)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func loadUI() {
        guard let dir = Bundle.main.resourceURL else { return }
        let index = dir.appendingPathComponent("panel/index.html")
        webView.loadFileURL(index, allowingReadAccessTo: dir)
    }

    // MARK: - 外观

    /// 透明度 0–1、尺寸以 pt 计；越界会被夹紧并回写给网页。
    func applyAppearance(opacity: CGFloat, size: NSSize) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.applyAppearance(opacity: opacity, size: size) }
            return
        }
        cardOpacity = min(1, max(0, opacity))
        let clamped = PanelMetrics.clampToScreen(size, screen: screen)
        if clamped != frame.size {
            let topLeft = NSPoint(x: frame.minX, y: frame.maxY)
            setFrame(NSRect(x: topLeft.x, y: topLeft.y - clamped.height,
                            width: clamped.width, height: clamped.height), display: true)
        }
        persistAppearance()
        syncAppearanceToWeb()
    }

    private func persistAppearance() {
        UserDefaults.standard.set("\(Int(frame.width))x\(Int(frame.height))", forKey: PanelMetrics.sizeKey)
        UserDefaults.standard.set(Double(cardOpacity), forKey: PanelMetrics.opacityKey)
    }

    private func syncAppearanceToWeb() {
        let payload: [String: Any] = [
            "opacity": Int((cardOpacity * 100).rounded()),
            "width": Int(frame.width),
            "height": Int(frame.height)
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.__fish && window.__fish.appearance && window.__fish.appearance(\(json));",
                                   completionHandler: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        syncAppearanceToWeb()
    }
}

/// 顶部拖拽条
final class DragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

/// 右下角缩放手柄：拖动改变窗口宽高，左上角锚定。
final class ResizeGripView: NSView {
    var onBeginDrag: (() -> Void)?
    var onDragSize: ((NSSize) -> Void)?
    private var startSize = NSSize.zero
    private var startMouse = NSPoint.zero

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func mouseDown(with event: NSEvent) {
        startSize = window?.frame.size ?? .zero
        startMouse = NSEvent.mouseLocation
        onBeginDrag?()
    }

    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let proposed = NSSize(width: startSize.width + (point.x - startMouse.x),
                              height: startSize.height - (point.y - startMouse.y))
        onDragSize?(proposed)
    }

    override func draw(_ dirtyRect: NSRect) {
        let color = NSColor(srgbRed: 0xBF / 255.0, green: 0xDB / 255.0, blue: 0xFE / 255.0, alpha: 0.95)
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = 1.6
        path.lineCapStyle = .round
        for i in 0..<3 {
            let offset = CGFloat(4 + i * 5)
            path.move(to: NSPoint(x: bounds.maxX - offset, y: bounds.minY + 3))
            path.line(to: NSPoint(x: bounds.maxX - 3, y: bounds.minY + offset))
        }
        path.stroke()
    }
}
