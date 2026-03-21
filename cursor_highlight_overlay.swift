import Cocoa

struct AppSettings {
    static let ringRadius = "ringRadius"
    static let fillOpacity = "fillOpacity"
    static let strokeOpacity = "strokeOpacity"
    static let colorName = "colorName"
    static let showCenterDot = "showCenterDot"
    static let overlayVisible = "overlayVisible"
    static let fakePointerVisible = "fakePointerVisible"
}

final class RingView: NSView {
    var ringColor: NSColor = .systemYellow { didSet { needsDisplay = true } }
    var fillOpacity: CGFloat = 0.18 { didSet { needsDisplay = true } }
    var strokeOpacity: CGFloat = 0.95 { didSet { needsDisplay = true } }
    var showCenterDot: Bool = true { didSet { needsDisplay = true } }
    var centerDotColor: NSColor = .systemRed { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard bounds.width > 2, bounds.height > 2 else { return }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let inset: CGFloat = 5
        let rect = bounds.insetBy(dx: inset, dy: inset)

        let outer = NSBezierPath(ovalIn: rect)
        ringColor.withAlphaComponent(strokeOpacity).setStroke()
        outer.lineWidth = 5
        outer.stroke()

        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5))
        ringColor.withAlphaComponent(fillOpacity).setFill()
        inner.fill()

        if showCenterDot {
            let centerSize: CGFloat = max(4, min(bounds.width, bounds.height) * 0.11)
            let centerRect = NSRect(
                x: bounds.midX - centerSize / 2,
                y: bounds.midY - centerSize / 2,
                width: centerSize,
                height: centerSize
            )
            let centerDot = NSBezierPath(ovalIn: centerRect)
            centerDotColor.withAlphaComponent(0.95).setFill()
            centerDot.fill()
        }
    }
}

final class OverlayWindow: NSWindow {
    init(diameter: CGFloat) {
        let frame = NSRect(x: 0, y: 0, width: diameter, height: diameter)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = RingView(frame: frame)
        contentView = view
    }

    var ringView: RingView? { contentView as? RingView }

    func updateDiameter(_ diameter: CGFloat) {
        let newFrame = NSRect(origin: frame.origin, size: NSSize(width: diameter, height: diameter))
        setFrame(newFrame, display: true)
        ringView?.frame = NSRect(origin: .zero, size: newFrame.size)
        ringView?.needsDisplay = true
    }
}

final class PointerWindow: NSWindow {
    private let pointerLayer = CAShapeLayer()

    init(size: CGFloat = 26) {
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSView(frame: frame)
        view.wantsLayer = true
        contentView = view

        pointerLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        view.layer?.addSublayer(pointerLayer)
        redrawPointer()
    }

    func redrawPointer() {
        let w = contentView?.bounds.width ?? 26
        let h = contentView?.bounds.height ?? 26
        pointerLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)

        let p = NSBezierPath()
        p.move(to: NSPoint(x: 4, y: h - 4))
        p.line(to: NSPoint(x: 4, y: 3))
        p.line(to: NSPoint(x: w * 0.60, y: h * 0.36))
        p.line(to: NSPoint(x: w * 0.46, y: h * 0.31))
        p.line(to: NSPoint(x: w * 0.68, y: 4))
        p.line(to: NSPoint(x: w * 0.56, y: 1))
        p.line(to: NSPoint(x: w * 0.35, y: h * 0.28))
        p.line(to: NSPoint(x: w * 0.30, y: h * 0.42))
        p.close()

        let cgPath = CGMutablePath()
        for i in 0..<p.elementCount {
            var pts = [NSPoint](repeating: .zero, count: 3)
            let type = p.element(at: i, associatedPoints: &pts)
            switch type {
            case .moveTo:
                cgPath.move(to: pts[0])
            case .lineTo:
                cgPath.addLine(to: pts[0])
            case .curveTo:
                cgPath.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .closePath:
                cgPath.closeSubpath()
            @unknown default:
                break
            }
        }

        pointerLayer.path = cgPath
        pointerLayer.fillColor = NSColor.black.withAlphaComponent(0.96).cgColor
        pointerLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        pointerLayer.lineWidth = 1.0
        pointerLayer.shadowColor = NSColor.black.cgColor
        pointerLayer.shadowOpacity = 0.22
        pointerLayer.shadowRadius = 1.5
        pointerLayer.shadowOffset = CGSize(width: 0.8, height: -0.8)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayWindow!
    private var fakePointer: PointerWindow!
    private var statusItem: NSStatusItem!
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var spaceObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var fallbackTimer: Timer?

    private let defaults = UserDefaults.standard

    private var overlayVisible = true { didSet { saveSettings() } }
    private var fakePointerVisible = false { didSet { saveSettings() } }
    private var ringRadius: CGFloat = 28 { didSet { saveSettings() } }
    private var fillOpacity: CGFloat = 0.18 { didSet { saveSettings() } }
    private var strokeOpacity: CGFloat = 0.95 { didSet { saveSettings() } }
    private var currentColorName: String = "yellow" { didSet { saveSettings() } }
    private var centerDotEnabled = true { didSet { saveSettings() } }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        loadSettings()

        overlay = OverlayWindow(diameter: ringRadius * 2)
        fakePointer = PointerWindow()

        applySettingsToViews()
        applyVisibility()
        setupMenuBar()
        startHybridTracking()
        updateOverlayPosition(force: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopHybridTracking()
        saveSettings()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "◎"
            button.toolTip = "Cursor Highlight"
        }

        let menu = NSMenu()

        let toggleHighlight = NSMenuItem(title: "显示/隐藏高亮圈", action: #selector(toggleOverlay), keyEquivalent: "h")
        toggleHighlight.target = self
        menu.addItem(toggleHighlight)

        let togglePointer = NSMenuItem(title: "显示/隐藏附加光标", action: #selector(toggleFakePointer), keyEquivalent: "p")
        togglePointer.target = self
        menu.addItem(togglePointer)

        let toggleDot = NSMenuItem(title: "显示/隐藏中心点", action: #selector(toggleCenterDot), keyEquivalent: "d")
        toggleDot.target = self
        menu.addItem(toggleDot)

        menu.addItem(NSMenuItem.separator())

        let colorMenu = NSMenuItem(title: "高亮颜色", action: nil, keyEquivalent: "")
        let colorSub = NSMenu()
        colorSub.addItem(menuItem(title: "黄色", action: #selector(setColorYellow)))
        colorSub.addItem(menuItem(title: "绿色", action: #selector(setColorGreen)))
        colorSub.addItem(menuItem(title: "蓝色", action: #selector(setColorBlue)))
        colorSub.addItem(menuItem(title: "红色", action: #selector(setColorRed)))
        colorSub.addItem(menuItem(title: "紫色", action: #selector(setColorPurple)))
        colorSub.addItem(menuItem(title: "青色", action: #selector(setColorCyan)))
        menu.setSubmenu(colorSub, for: colorMenu)
        menu.addItem(colorMenu)

        let radiusMenu = NSMenuItem(title: "半径", action: nil, keyEquivalent: "")
        let radiusSub = NSMenu()
        radiusSub.addItem(menuItem(title: "16", action: #selector(setRadius16)))
        radiusSub.addItem(menuItem(title: "24", action: #selector(setRadius24)))
        radiusSub.addItem(menuItem(title: "32", action: #selector(setRadius32)))
        radiusSub.addItem(menuItem(title: "40", action: #selector(setRadius40)))
        radiusSub.addItem(menuItem(title: "52", action: #selector(setRadius52)))
        menu.setSubmenu(radiusSub, for: radiusMenu)
        menu.addItem(radiusMenu)

        let alphaMenu = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let alphaSub = NSMenu()
        alphaSub.addItem(menuItem(title: "很淡", action: #selector(setAlphaLow)))
        alphaSub.addItem(menuItem(title: "中等", action: #selector(setAlphaMedium)))
        alphaSub.addItem(menuItem(title: "较强", action: #selector(setAlphaHigh)))
        alphaSub.addItem(menuItem(title: "很强", action: #selector(setAlphaVeryHigh)))
        menu.setSubmenu(alphaSub, for: alphaMenu)
        menu.addItem(alphaMenu)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func menuItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func startHybridTracking() {
        let mouseEvents: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDragged,
            .rightMouseDragged,
            .otherMouseDragged,
            .leftMouseDown,
            .rightMouseDown,
            .otherMouseDown,
            .leftMouseUp,
            .rightMouseUp,
            .otherMouseUp,
            .scrollWheel,
            .cursorUpdate
        ]

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents) { [weak self] _ in
            self?.updateOverlayPosition(force: false)
        }

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mouseEvents) { [weak self] event in
            self?.updateOverlayPosition(force: false)
            return event
        }

        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 12.0, repeats: true) { [weak self] _ in
            self?.updateOverlayPosition(force: false)
        }
        if let fallbackTimer {
            RunLoop.main.add(fallbackTimer, forMode: .common)
        }

        let center = NSWorkspace.shared.notificationCenter
        spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOverlayPosition(force: true)
        }

        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateOverlayPosition(force: true)
        }
    }

    private func stopHybridTracking() {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        fallbackTimer?.invalidate()
        fallbackTimer = nil
        let center = NSWorkspace.shared.notificationCenter
        if let spaceObserver {
            center.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let wakeObserver {
            center.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    private func applySettingsToViews() {
        overlay.updateDiameter(ringRadius * 2)
        overlay.ringView?.ringColor = colorFromName(currentColorName)
        overlay.ringView?.fillOpacity = fillOpacity
        overlay.ringView?.strokeOpacity = strokeOpacity
        overlay.ringView?.showCenterDot = centerDotEnabled
    }

    private func applyVisibility() {
        if overlayVisible {
            overlay.orderFrontRegardless()
        } else {
            overlay.orderOut(nil)
        }

        if fakePointerVisible {
            fakePointer.orderFrontRegardless()
        } else {
            fakePointer.orderOut(nil)
        }
    }

    private func updateOverlayPosition(force: Bool) {
        guard overlayVisible || fakePointerVisible || force else { return }
        let mouse = NSEvent.mouseLocation

        if overlayVisible {
            let newOrigin = NSPoint(x: mouse.x - ringRadius, y: mouse.y - ringRadius)
            overlay.setFrameOrigin(newOrigin)
            overlay.orderFrontRegardless()
        }

        if fakePointerVisible {
            let pointerOrigin = NSPoint(x: mouse.x - 4, y: mouse.y - (fakePointer.frame.height - 4))
            fakePointer.setFrameOrigin(pointerOrigin)
            fakePointer.orderFrontRegardless()
        }
    }

    private func setRadius(_ radius: CGFloat) {
        ringRadius = radius
        applySettingsToViews()
        updateOverlayPosition(force: true)
    }

    private func setOpacity(fill: CGFloat, stroke: CGFloat) {
        fillOpacity = fill
        strokeOpacity = stroke
        applySettingsToViews()
    }

    private func setRingColor(name: String) {
        currentColorName = name
        applySettingsToViews()
    }

    private func colorFromName(_ name: String) -> NSColor {
        switch name {
        case "green": return .systemGreen
        case "blue": return .systemBlue
        case "red": return .systemRed
        case "purple": return .systemPurple
        case "cyan": return .systemTeal
        default: return .systemYellow
        }
    }

    private func saveSettings() {
        defaults.set(Double(ringRadius), forKey: AppSettings.ringRadius)
        defaults.set(Double(fillOpacity), forKey: AppSettings.fillOpacity)
        defaults.set(Double(strokeOpacity), forKey: AppSettings.strokeOpacity)
        defaults.set(currentColorName, forKey: AppSettings.colorName)
        defaults.set(centerDotEnabled, forKey: AppSettings.showCenterDot)
        defaults.set(overlayVisible, forKey: AppSettings.overlayVisible)
        defaults.set(fakePointerVisible, forKey: AppSettings.fakePointerVisible)
    }

    private func loadSettings() {
        if defaults.object(forKey: AppSettings.ringRadius) != nil {
            ringRadius = CGFloat(defaults.double(forKey: AppSettings.ringRadius))
        }
        if defaults.object(forKey: AppSettings.fillOpacity) != nil {
            fillOpacity = CGFloat(defaults.double(forKey: AppSettings.fillOpacity))
        }
        if defaults.object(forKey: AppSettings.strokeOpacity) != nil {
            strokeOpacity = CGFloat(defaults.double(forKey: AppSettings.strokeOpacity))
        }
        if let colorName = defaults.string(forKey: AppSettings.colorName), !colorName.isEmpty {
            currentColorName = colorName
        }
        if defaults.object(forKey: AppSettings.showCenterDot) != nil {
            centerDotEnabled = defaults.bool(forKey: AppSettings.showCenterDot)
        }
        if defaults.object(forKey: AppSettings.overlayVisible) != nil {
            overlayVisible = defaults.bool(forKey: AppSettings.overlayVisible)
        }
        if defaults.object(forKey: AppSettings.fakePointerVisible) != nil {
            fakePointerVisible = defaults.bool(forKey: AppSettings.fakePointerVisible)
        }

        if ringRadius < 8 { ringRadius = 8 }
        if ringRadius > 200 { ringRadius = 200 }
        fillOpacity = min(max(fillOpacity, 0.0), 1.0)
        strokeOpacity = min(max(strokeOpacity, 0.0), 1.0)
    }

    @objc private func toggleOverlay() {
        overlayVisible.toggle()
        applyVisibility()
        updateOverlayPosition(force: true)
    }

    @objc private func toggleFakePointer() {
        fakePointerVisible.toggle()
        applyVisibility()
        updateOverlayPosition(force: true)
    }

    @objc private func toggleCenterDot() {
        centerDotEnabled.toggle()
        applySettingsToViews()
    }

    @objc private func setColorYellow() { setRingColor(name: "yellow") }
    @objc private func setColorGreen() { setRingColor(name: "green") }
    @objc private func setColorBlue() { setRingColor(name: "blue") }
    @objc private func setColorRed() { setRingColor(name: "red") }
    @objc private func setColorPurple() { setRingColor(name: "purple") }
    @objc private func setColorCyan() { setRingColor(name: "cyan") }

    @objc private func setRadius16() { setRadius(16) }
    @objc private func setRadius24() { setRadius(24) }
    @objc private func setRadius32() { setRadius(32) }
    @objc private func setRadius40() { setRadius(40) }
    @objc private func setRadius52() { setRadius(52) }

    @objc private func setAlphaLow() { setOpacity(fill: 0.08, stroke: 0.45) }
    @objc private func setAlphaMedium() { setOpacity(fill: 0.16, stroke: 0.75) }
    @objc private func setAlphaHigh() { setOpacity(fill: 0.24, stroke: 0.92) }
    @objc private func setAlphaVeryHigh() { setOpacity(fill: 0.34, stroke: 1.0) }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
