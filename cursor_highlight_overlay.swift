import Cocoa
import CoreGraphics

struct AppSettings {
    static let ringRadius = "ringRadius"
    static let fillOpacity = "fillOpacity"
    static let strokeOpacity = "strokeOpacity"
    static let colorName = "colorName"
    static let showCenterDot = "showCenterDot"
    static let overlayVisible = "overlayVisible"
    static let fakePointerVisible = "fakePointerVisible"
    static let pointerSize = "pointerSize"
}

// MARK: - Ring View

final class RingView: NSView {
    var ringColor: NSColor = .systemYellow { didSet { needsDisplay = true } }
    var fillOpacity: CGFloat = 0.18 { didSet { needsDisplay = true } }
    var strokeOpacity: CGFloat = 0.95 { didSet { needsDisplay = true } }
    var showCenterDot: Bool = true { didSet { needsDisplay = true } }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        guard bounds.width > 2, bounds.height > 2 else { return }

        let rect = bounds.insetBy(dx: 5, dy: 5)

        let outer = NSBezierPath(ovalIn: rect)
        ringColor.withAlphaComponent(strokeOpacity).setStroke()
        outer.lineWidth = 5
        outer.stroke()

        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5))
        ringColor.withAlphaComponent(fillOpacity).setFill()
        inner.fill()

        if showCenterDot {
            let s: CGFloat = max(4, min(bounds.width, bounds.height) * 0.12)
            let dotRect = NSRect(x: bounds.midX - s / 2, y: bounds.midY - s / 2, width: s, height: s)
            NSColor.systemRed.withAlphaComponent(0.95).setFill()
            NSBezierPath(ovalIn: dotRect).fill()
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

        contentView = RingView(frame: frame)
    }

    var ringView: RingView? { contentView as? RingView }

    func updateDiameter(_ diameter: CGFloat) {
        let size = NSSize(width: diameter, height: diameter)
        setFrame(NSRect(origin: frame.origin, size: size), display: true)
        ringView?.frame = NSRect(origin: .zero, size: size)
        ringView?.needsDisplay = true
    }
}

// MARK: - Fake Pointer

final class PointerWindow: NSWindow {
    private let pointerLayer = CAShapeLayer()

    init(size: CGFloat) {
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        super.init(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)

        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]

        let view = NSView(frame: frame)
        view.wantsLayer = true
        contentView = view
        view.layer?.addSublayer(pointerLayer)
        redrawPointer()
    }

    func resize(_ size: CGFloat) {
        let newFrame = NSRect(origin: frame.origin, size: NSSize(width: size, height: size))
        setFrame(newFrame, display: true)
        contentView?.frame = NSRect(origin: .zero, size: newFrame.size)
        redrawPointer()
    }

    private func redrawPointer() {
        let w = frame.width
        let h = frame.height

        let p = NSBezierPath()
        p.move(to: NSPoint(x: w * 0.15, y: h * 0.95))
        p.line(to: NSPoint(x: w * 0.15, y: h * 0.05))
        p.line(to: NSPoint(x: w * 0.64, y: h * 0.34))
        p.line(to: NSPoint(x: w * 0.52, y: h * 0.31))
        p.line(to: NSPoint(x: w * 0.76, y: h * 0.05))
        p.line(to: NSPoint(x: w * 0.62, y: h * 0.02))
        p.line(to: NSPoint(x: w * 0.40, y: h * 0.30))
        p.line(to: NSPoint(x: w * 0.35, y: h * 0.45))
        p.close()

        let cg = CGMutablePath()
        for i in 0..<p.elementCount {
            var pts = [NSPoint](repeating: .zero, count: 3)
            let t = p.element(at: i, associatedPoints: &pts)
            switch t {
            case .moveTo:
                cg.move(to: pts[0])
            case .lineTo:
                cg.addLine(to: pts[0])
            case .curveTo:
                cg.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .cubicCurveTo:
                cg.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo:
                cg.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath:
                cg.closeSubpath()
            @unknown default:
                break
            }
        }

        pointerLayer.frame = CGRect(x: 0, y: 0, width: w, height: h)
        pointerLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        pointerLayer.path = cg
        pointerLayer.fillColor = NSColor.black.withAlphaComponent(0.96).cgColor
        pointerLayer.strokeColor = NSColor.white.withAlphaComponent(0.85).cgColor
        pointerLayer.lineWidth = max(1.0, w * 0.03)
        pointerLayer.shadowColor = NSColor.black.cgColor
        pointerLayer.shadowOpacity = 0.22
        pointerLayer.shadowRadius = max(1.0, w * 0.04)
        pointerLayer.shadowOffset = CGSize(width: 0.8, height: -0.8)
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayWindow!
    private var pointer: PointerWindow!
    private var statusItem: NSStatusItem!

    private var localMonitor: Any?
    private var fallbackTimer: Timer?
    private var spaceObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?

    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?

    private let defaults = UserDefaults.standard

    private var ringRadius: CGFloat = 28 { didSet { saveSettings() } }
    private var pointerSize: CGFloat = 36 { didSet { saveSettings() } }
    private var fillOpacity: CGFloat = 0.18 { didSet { saveSettings() } }
    private var strokeOpacity: CGFloat = 0.95 { didSet { saveSettings() } }
    private var currentColorName: String = "yellow" { didSet { saveSettings() } }
    private var showCenterDot = true { didSet { saveSettings() } }
    private var overlayVisible = true { didSet { saveSettings() } }
    private var pointerVisible = false { didSet { saveSettings() } }

    private var lastMouseLocation: CGPoint = .zero
    private var lastMotionTimestamp: CFAbsoluteTime = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        loadSettings()

        overlay = OverlayWindow(diameter: ringRadius * 2)
        pointer = PointerWindow(size: pointerSize)

        applyVisualSettings()
        applyVisibility()
        setupMenu()
        startTracking()
        updatePosition(force: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopTracking()
        saveSettings()
    }

    // MARK: Menu

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "◎"
        statusItem.button?.toolTip = "Cursor Highlight"

        let menu = NSMenu()
        menu.addItem(menuItem("显示/隐藏高亮圈", #selector(toggleOverlay)))
        menu.addItem(menuItem("显示/隐藏附加光标", #selector(togglePointer)))
        menu.addItem(menuItem("显示/隐藏中心点", #selector(toggleCenterDot)))
        menu.addItem(NSMenuItem.separator())

        let colorItem = NSMenuItem(title: "高亮颜色", action: nil, keyEquivalent: "")
        let colorSub = NSMenu()
        colorSub.addItem(menuItem("黄色", #selector(setColorYellow)))
        colorSub.addItem(menuItem("绿色", #selector(setColorGreen)))
        colorSub.addItem(menuItem("蓝色", #selector(setColorBlue)))
        colorSub.addItem(menuItem("红色", #selector(setColorRed)))
        colorSub.addItem(menuItem("紫色", #selector(setColorPurple)))
        colorSub.addItem(menuItem("青色", #selector(setColorCyan)))
        menu.setSubmenu(colorSub, for: colorItem)
        menu.addItem(colorItem)

        let radiusItem = NSMenuItem(title: "高亮半径", action: nil, keyEquivalent: "")
        let radiusSub = NSMenu()
        radiusSub.addItem(menuItem("16", #selector(setRadius16)))
        radiusSub.addItem(menuItem("24", #selector(setRadius24)))
        radiusSub.addItem(menuItem("32", #selector(setRadius32)))
        radiusSub.addItem(menuItem("40", #selector(setRadius40)))
        radiusSub.addItem(menuItem("52", #selector(setRadius52)))
        menu.setSubmenu(radiusSub, for: radiusItem)
        menu.addItem(radiusItem)

        let alphaItem = NSMenuItem(title: "透明度", action: nil, keyEquivalent: "")
        let alphaSub = NSMenu()
        alphaSub.addItem(menuItem("很淡", #selector(setAlphaLow)))
        alphaSub.addItem(menuItem("中等", #selector(setAlphaMedium)))
        alphaSub.addItem(menuItem("较强", #selector(setAlphaHigh)))
        alphaSub.addItem(menuItem("很强", #selector(setAlphaVeryHigh)))
        menu.setSubmenu(alphaSub, for: alphaItem)
        menu.addItem(alphaItem)

        let pointerSizeItem = NSMenuItem(title: "附加光标大小", action: nil, keyEquivalent: "")
        let pointerSizeSub = NSMenu()
        pointerSizeSub.addItem(menuItem("小", #selector(pointerSmall)))
        pointerSizeSub.addItem(menuItem("中", #selector(pointerMedium)))
        pointerSizeSub.addItem(menuItem("大", #selector(pointerLarge)))
        pointerSizeSub.addItem(menuItem("超大", #selector(pointerXL)))
        menu.setSubmenu(pointerSizeSub, for: pointerSizeItem)
        menu.addItem(pointerSizeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(menuItem("退出", #selector(quit)))
        statusItem.menu = menu
    }

    private func menuItem(_ title: String, _ sel: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: sel, keyEquivalent: "")
        item.target = self
        return item
    }

    // MARK: Tracking

    private func startTracking() {
        installEventTap()
        installLocalMonitor()
        installFallbackTimer()
        installWorkspaceObservers()
    }

    private func stopTracking() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        fallbackTimer?.invalidate()
        fallbackTimer = nil

        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            eventTapSource = nil
        }
        if let tap = eventTap {
            CFMachPortInvalidate(tap)
            eventTap = nil
        }

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

    private func installEventTap() {
        let eventTypes: [CGEventType] = [
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
            .scrollWheel
        ]

        var mask: CGEventMask = 0
        for type in eventTypes {
            mask |= (CGEventMask(1) << CGEventMask(type.rawValue))
        }

        let userInfo = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: userInfo
        ) else {
            installFallbackTimer(hz: 30)
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func installLocalMonitor() {
        let mask: NSEvent.EventTypeMask = [
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

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.noteMotionAndUpdatePosition()
            return event
        }
    }

    private func installFallbackTimer(hz: Double = 20) {
        fallbackTimer?.invalidate()
        fallbackTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / hz, repeats: true) { [weak self] _ in
            self?.adaptivePollingTick()
        }
        if let fallbackTimer {
            RunLoop.main.add(fallbackTimer, forMode: .common)
        }
    }

    private func installWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        spaceObserver = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition(force: true)
        }

        wakeObserver = center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updatePosition(force: true)
        }
    }

    private func noteMotionAndUpdatePosition() {
        lastMotionTimestamp = CFAbsoluteTimeGetCurrent()
        updatePosition(force: false)
    }

    private func adaptivePollingTick() {
        let now = CFAbsoluteTimeGetCurrent()
        let elapsed = now - lastMotionTimestamp

        if elapsed < 0.20 {
            updatePosition(force: false)
            return
        }

        if elapsed < 1.20 {
            updatePosition(force: false)
            return
        }

        if overlayVisible || pointerVisible {
            let p = NSEvent.mouseLocation
            if abs(p.x - lastMouseLocation.x) > 0.1 || abs(p.y - lastMouseLocation.y) > 0.1 {
                updatePosition(force: false)
            }
        }
    }

    private func updatePosition(force: Bool) {
        guard overlayVisible || pointerVisible || force else { return }

        let p = NSEvent.mouseLocation
        lastMouseLocation = p

        if overlayVisible {
            overlay.setFrameOrigin(NSPoint(x: p.x - ringRadius, y: p.y - ringRadius))
            overlay.orderFrontRegardless()
        }

        if pointerVisible {
            pointer.setFrameOrigin(NSPoint(x: p.x - pointerSize * 0.20, y: p.y - pointerSize * 0.90))
            pointer.orderFrontRegardless()
        }
    }

    // MARK: Settings / Appearance

    private func applyVisualSettings() {
        overlay.updateDiameter(ringRadius * 2)
        overlay.ringView?.ringColor = colorFromName(currentColorName)
        overlay.ringView?.fillOpacity = fillOpacity
        overlay.ringView?.strokeOpacity = strokeOpacity
        overlay.ringView?.showCenterDot = showCenterDot
        pointer.resize(pointerSize)
    }

    private func applyVisibility() {
        overlayVisible ? overlay.orderFront(nil) : overlay.orderOut(nil)
        pointerVisible ? pointer.orderFront(nil) : pointer.orderOut(nil)
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

    private func setRingColor(_ name: String) {
        currentColorName = name
        overlay.ringView?.ringColor = colorFromName(name)
    }

    private func setRadius(_ radius: CGFloat) {
        ringRadius = radius
        overlay.updateDiameter(radius * 2)
        updatePosition(force: true)
    }

    private func setOpacity(fill: CGFloat, stroke: CGFloat) {
        fillOpacity = fill
        strokeOpacity = stroke
        overlay.ringView?.fillOpacity = fill
        overlay.ringView?.strokeOpacity = stroke
    }

    private func setPointerSize(_ size: CGFloat) {
        pointerSize = size
        pointer.resize(size)
        updatePosition(force: true)
    }

    private func saveSettings() {
        defaults.set(Double(ringRadius), forKey: AppSettings.ringRadius)
        defaults.set(Double(pointerSize), forKey: AppSettings.pointerSize)
        defaults.set(Double(fillOpacity), forKey: AppSettings.fillOpacity)
        defaults.set(Double(strokeOpacity), forKey: AppSettings.strokeOpacity)
        defaults.set(currentColorName, forKey: AppSettings.colorName)
        defaults.set(showCenterDot, forKey: AppSettings.showCenterDot)
        defaults.set(overlayVisible, forKey: AppSettings.overlayVisible)
        defaults.set(pointerVisible, forKey: AppSettings.fakePointerVisible)
    }

    private func loadSettings() {
        if defaults.object(forKey: AppSettings.ringRadius) != nil {
            ringRadius = CGFloat(defaults.double(forKey: AppSettings.ringRadius))
        }
        if defaults.object(forKey: AppSettings.pointerSize) != nil {
            pointerSize = CGFloat(defaults.double(forKey: AppSettings.pointerSize))
        }
        if defaults.object(forKey: AppSettings.fillOpacity) != nil {
            fillOpacity = CGFloat(defaults.double(forKey: AppSettings.fillOpacity))
        }
        if defaults.object(forKey: AppSettings.strokeOpacity) != nil {
            strokeOpacity = CGFloat(defaults.double(forKey: AppSettings.strokeOpacity))
        }
        if let c = defaults.string(forKey: AppSettings.colorName), !c.isEmpty {
            currentColorName = c
        }
        if defaults.object(forKey: AppSettings.showCenterDot) != nil {
            showCenterDot = defaults.bool(forKey: AppSettings.showCenterDot)
        }
        if defaults.object(forKey: AppSettings.overlayVisible) != nil {
            overlayVisible = defaults.bool(forKey: AppSettings.overlayVisible)
        }
        if defaults.object(forKey: AppSettings.fakePointerVisible) != nil {
            pointerVisible = defaults.bool(forKey: AppSettings.fakePointerVisible)
        }

        ringRadius = min(max(ringRadius, 8), 200)
        pointerSize = min(max(pointerSize, 12), 120)
        fillOpacity = min(max(fillOpacity, 0.0), 1.0)
        strokeOpacity = min(max(strokeOpacity, 0.0), 1.0)
    }

    // MARK: Actions

    @objc private func toggleOverlay() {
        overlayVisible.toggle()
        applyVisibility()
        updatePosition(force: true)
    }

    @objc private func togglePointer() {
        pointerVisible.toggle()
        applyVisibility()
        updatePosition(force: true)
    }

    @objc private func toggleCenterDot() {
        showCenterDot.toggle()
        overlay.ringView?.showCenterDot = showCenterDot
    }

    @objc private func setColorYellow() { setRingColor("yellow") }
    @objc private func setColorGreen() { setRingColor("green") }
    @objc private func setColorBlue() { setRingColor("blue") }
    @objc private func setColorRed() { setRingColor("red") }
    @objc private func setColorPurple() { setRingColor("purple") }
    @objc private func setColorCyan() { setRingColor("cyan") }

    @objc private func setRadius16() { setRadius(16) }
    @objc private func setRadius24() { setRadius(24) }
    @objc private func setRadius32() { setRadius(32) }
    @objc private func setRadius40() { setRadius(40) }
    @objc private func setRadius52() { setRadius(52) }

    @objc private func setAlphaLow() { setOpacity(fill: 0.08, stroke: 0.45) }
    @objc private func setAlphaMedium() { setOpacity(fill: 0.16, stroke: 0.75) }
    @objc private func setAlphaHigh() { setOpacity(fill: 0.24, stroke: 0.92) }
    @objc private func setAlphaVeryHigh() { setOpacity(fill: 0.34, stroke: 1.0) }

    @objc private func pointerSmall() { setPointerSize(20) }
    @objc private func pointerMedium() { setPointerSize(32) }
    @objc private func pointerLarge() { setPointerSize(46) }
    @objc private func pointerXL() { setPointerSize(62) }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
