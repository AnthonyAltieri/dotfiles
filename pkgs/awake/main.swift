// awake: a menu-bar toggle that keeps the Mac awake, like `caffeinate -d`.
//
// While on, it holds a PreventUserIdleDisplaySleep power assertion. That
// stops idle display sleep, idle system sleep, and the idle screen saver, so
// the screen never locks on its own. Locking the screen yourself releases the
// assertion so the display can sleep; unlocking takes it again.
//
// Left-click toggles. Right-click opens a menu with Quit.

import AppKit
import IOKit.pwr_mgt

final class Awake: NSObject, NSApplicationDelegate {
    private static let enabledKey = "enabled"

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var assertionID: IOPMAssertionID?
    private var screenLocked = false

    private var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            update()
        }
    }

    override init() {
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        let center = DistributedNotificationCenter.default()
        center.addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
            self?.update()
        }
        center.addObserver(forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
            self?.update()
        }

        update()
    }

    func applicationWillTerminate(_ notification: Notification) {
        release()
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Quit awake", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            enabled.toggle()
        }
    }

    // Single place that reconciles the held assertion and the icon with state.
    private func update() {
        if enabled && !screenLocked {
            hold()
        } else {
            release()
        }

        let symbol = enabled ? "cup.and.saucer.fill" : "cup.and.saucer"
        let label = enabled ? "awake: on" : "awake: off"
        statusItem.button?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        statusItem.button?.toolTip = label
    }

    private func hold() {
        guard assertionID == nil else { return }
        var id = IOPMAssertionID(0)
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "awake menu-bar toggle" as CFString,
            &id
        )
        if result == kIOReturnSuccess {
            assertionID = id
        } else {
            NSLog("awake: IOPMAssertionCreateWithName failed: \(result)")
        }
    }

    private func release() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }
}

let app = NSApplication.shared
let delegate = Awake()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
