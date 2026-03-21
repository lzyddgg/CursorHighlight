import Cocoa

final class RingView: NSView {
    var ringDiameter: CGFloat = 56 {
        didSet { needsDisplay = true }
    }

    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)

        let inset: CGFloat = 6
        let rect = bounds.insetBy(dx: inset, dy: inset)

        // 外环
        let outer = NSBezierPath(ovalIn: rect)
        NSColor.systemYellow.withAlphaComponent(0.95).setStroke()
        outer.lineWidth = 6
        outer.stroke()

        // 柔和填充
        let inner = NSBezierPath(ovalIn: rect.insetBy(dx: 5, dy: 5))
        NSColor.systemYellow.withAlphaComponent(0.16).setFill()
        inner.fill()

        // 中心点，帮助定位
        let centerSize: CGFloat = 6
        let centerRect = NSRect(
            x: bounds.midX - centerSize / 2,
            y: bounds.midY - centerSize / 2,
            width: centerSize,
            height: centerSize
        )
        let centerDot = NSBezierPath(ovalIn: centerRect)
        NSColor.systemRed.withAlphaComponent(0.9).setFill()
        centerDot.fill()
    }
}

final class OverlayWindow: NSWindow {
    init(size: CGFloat) {
        let frame = NSRect(x: 0, y: 0, width: size, height: size)
        super.init(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        isReleasedWhenClosed = false
        level = .screenSaver
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
            .stationary,
            .ignoresCycle
        ]

        let view = RingView(frame: frame)
        contentView = view
    }

    func updateSize(_ size: CGFloat) {
        let newFrame = NSRect(origin: frame.origin, size: NSSize(width: size, height: size))
        setFrame(newFrame, display: true)
        if let ringView = contentView as? RingView {
            ringView.frame = NSRect(origin: .zero, size: newFrame.size)
            ringView.ringDiameter = size
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlay: OverlayWindow!
    private var timer: Timer?
    private var statusItem: NSStatusItem!
    private var isVisible = true
    private var ringSize: CGFloat = 56

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        overlay = OverlayWindow(size: ringSize)
        overlay.orderFrontRegardless()

        setupMenuBar()
        startTrackingCursor()
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.title = "◎"
            button.toolTip = "Cursor Highlight"
        }

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "隐藏/显示高亮", action: #selector(toggleOverlay), keyEquivalent: "h")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let smallItem = NSMenuItem(title: "小号光圈", action: #selector(setSmallRing), keyEquivalent: "1")
        smallItem.target = self
        menu.addItem(smallItem)

        let mediumItem = NSMenuItem(title: "中号光圈", action: #selector(setMediumRing), keyEquivalent: "2")
        mediumItem.target = self
        menu.addItem(mediumItem)

        let largeItem = NSMenuItem(title: "大号光圈", action: #selector(setLargeRing), keyEquivalent: "3")
        largeItem.target = self
        menu.addItem(largeItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    private func startTrackingCursor() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.updateOverlayPosition()
        }
        RunLoop.main.add(timer!, forMode: .common)
        updateOverlayPosition()
    }

    private func updateOverlayPosition() {
        guard isVisible else { return }

        let mouse = NSEvent.mouseLocation
        let newOrigin = NSPoint(
            x: mouse.x - ringSize / 2,
            y: mouse.y - ringSize / 2
        )
        overlay.setFrameOrigin(newOrigin)
        overlay.orderFrontRegardless()
    }

    @objc private func toggleOverlay() {
        isVisible.toggle()
        if isVisible {
            overlay.orderFrontRegardless()
            updateOverlayPosition()
        } else {
            overlay.orderOut(nil)
        }
    }

    @objc private func setSmallRing() {
        applyRingSize(40)
    }

    @objc private func setMediumRing() {
        applyRingSize(56)
    }

    @objc private func setLargeRing() {
        applyRingSize(76)
    }

    private func applyRingSize(_ size: CGFloat) {
        ringSize = size
        overlay.updateSize(size)
        updateOverlayPosition()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
