import Cocoa

final class DimView: NSView {
    var hole: NSRect? { didSet { if hole != oldValue { needsDisplay = true } } }
    var dimAlpha: CGFloat = 0.5 { didSet { needsDisplay = true } }
    static let cornerRadius: CGFloat = 10

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill(using: .copy)

        let path = NSBezierPath(rect: bounds)
        if let hole = hole {
            path.append(NSBezierPath(roundedRect: hole,
                                     xRadius: Self.cornerRadius,
                                     yRadius: Self.cornerRadius))
            path.windingRule = .evenOdd
        }
        NSColor.black.withAlphaComponent(dimAlpha).setFill()
        path.fill()
    }
}

final class OverlayWindow: NSWindow {
    let dimView: DimView

    init(screen: NSScreen) {
        dimView = DimView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(contentRect: screen.frame, styleMask: .borderless,
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary,
                              .fullScreenAuxiliary, .ignoresCycle]
        contentView = dimView
        setFrame(screen.frame, display: false)
        alphaValue = 0
        orderFrontRegardless()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var overlays: [(frame: NSRect, window: OverlayWindow)] = []
    private var statusItem: NSStatusItem!
    private var toggleItem: NSMenuItem!
    private var levelItems: [NSMenuItem] = []
    private var timer: Timer?

    private var enabled = true
    private var visible = false
    private var lastHole: NSRect?
    private let myPID = ProcessInfo.processInfo.processIdentifier

    private var dimAlpha: CGFloat {
        get {
            let v = UserDefaults.standard.double(forKey: "dimAlpha")
            return v > 0 ? CGFloat(v) : 0.5
        }
        set { UserDefaults.standard.set(Double(newValue), forKey: "dimAlpha") }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        rebuildOverlays()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let t = Timer(timeInterval: 1.0 / 30.0, target: self,
                      selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func screensChanged() { rebuildOverlays() }

    private func rebuildOverlays() {
        overlays.forEach { $0.window.close() }
        overlays = NSScreen.screens.map { screen in
            let w = OverlayWindow(screen: screen)
            w.dimView.dimAlpha = dimAlpha
            w.alphaValue = visible ? 1 : 0
            return (screen.frame, w)
        }
        lastHole = nil
    }

    private func frontWindowFrame() -> NSRect? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let pid = app.processIdentifier
        if pid == myPID { return lastHole }

        guard let list = CGWindowListCopyWindowInfo(
                [.optionOnScreenOnly, .excludeDesktopElements],
                kCGNullWindowID) as? [[String: Any]] else { return nil }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        for info in list {
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  ((info[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1) > 0,
                  let dict = info[kCGWindowBounds as String] as? NSDictionary,
                  let b = CGRect(dictionaryRepresentation: dict as CFDictionary),
                  b.width > 60, b.height > 60
            else { continue }

            return NSRect(x: b.minX, y: primaryHeight - b.maxY,
                          width: b.width, height: b.height)
        }
        return nil
    }

    @objc private func tick() {
        guard enabled else { return }

        guard let hole = frontWindowFrame() else {
            setVisible(false)
            lastHole = nil
            return
        }

        if hole != lastHole {
            lastHole = hole
            for o in overlays {
                o.window.dimView.hole = hole.offsetBy(dx: -o.frame.minX,
                                                      dy: -o.frame.minY)
            }
        }
        setVisible(true)
    }

    private func setVisible(_ v: Bool) {
        guard v != visible else { return }
        visible = v
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            overlays.forEach { $0.window.animator().alphaValue = v ? 1 : 0 }
        }
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let img = NSImage(systemSymbolName: "circle.lefthalf.filled",
                             accessibilityDescription: "Kasumi") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "◐"
        }

        let menu = NSMenu()

        toggleItem = NSMenuItem(title: "暗くする", action: #selector(toggleEnabled),
                                keyEquivalent: "")
        toggleItem.target = self
        toggleItem.state = .on
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let header = NSMenuItem(title: "暗さ", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        for (title, value) in [("うすめ", 0.3), ("ふつう", 0.5),
                               ("こいめ", 0.7), ("ほぼ真っ暗", 0.88)] {
            let item = NSMenuItem(title: title, action: #selector(setLevel(_:)),
                                  keyEquivalent: "")
            item.target = self
            item.representedObject = value
            item.indentationLevel = 1
            levelItems.append(item)
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "終了",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
        updateLevelChecks()
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        toggleItem.state = enabled ? .on : .off
        if !enabled {
            setVisible(false)
            lastHole = nil
        }
    }

    @objc private func setLevel(_ sender: NSMenuItem) {
        guard let v = sender.representedObject as? Double else { return }
        dimAlpha = CGFloat(v)
        overlays.forEach { $0.window.dimView.dimAlpha = CGFloat(v) }
        updateLevelChecks()
    }

    private func updateLevelChecks() {
        for item in levelItems {
            let v = item.representedObject as? Double ?? 0
            item.state = abs(CGFloat(v) - dimAlpha) < 0.01 ? .on : .off
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
