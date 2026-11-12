// awake: a menu-bar toggle that keeps the Mac awake, like `caffeinate -d`.
//
// While on, it holds a PreventUserIdleDisplaySleep power assertion. That
// stops idle display sleep, idle system sleep, and the idle screen saver, so
// the screen never locks on its own. Locking the screen yourself releases the
// assertion so the display can sleep; unlocking takes it again.
//
// Left-click toggles. Right-click opens a menu with Quit.
//
// Run with a command (`awake on`, `awake off`, `awake status`) it acts as a
// client instead: it saves the setting and tells the running app to apply it.

import AppKit
import IOKit.pwr_mgt

// The launchd label, bundle identifier, and preferences domain.
let bundleID = "dotfiles.awake"
let turnOnNotification = Notification.Name("dotfiles.awake.on")
let turnOffNotification = Notification.Name("dotfiles.awake.off")
// The icon's starting distance from the right edge of the screen, in points.
let preferredPosition = 200

// The on/off setting, shared by the app and the command-line client. It uses
// an explicit domain so both agree however the binary was started.
enum Setting {
    private static let key = "enabled" as CFString

    static var enabled: Bool {
        get { CFPreferencesCopyAppValue(key, bundleID as CFString) as? Bool ?? true }
        set {
            CFPreferencesSetAppValue(key, newValue as CFBoolean, bundleID as CFString)
            CFPreferencesAppSynchronize(bundleID as CFString)
        }
    }
}

final class Awake: NSObject, NSApplicationDelegate {
    private let statusItem: NSStatusItem
    private var assertionID: IOPMAssertionID?
    private var screenLocked = false

    private var enabled: Bool {
        didSet {
            Setting.enabled = enabled
            update()
        }
    }

    override init() {
        // macOS puts a new status item at the far left, which is the first
        // spot it hides when the icons beside the notch run out of room. Ask
        // for a spot near the clock instead. Only write it when unset, because
        // AppKit saves over this key when the user ⌘-drags the icon. Item-0 is
        // AppKit's autosave name for an app's first status item.
        let positionKey = "NSStatusItem Preferred Position Item-0"
        if UserDefaults.standard.object(forKey: positionKey) == nil {
            UserDefaults.standard.set(preferredPosition, forKey: positionKey)
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        enabled = Setting.enabled
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
        center.addObserver(forName: turnOnNotification, object: nil, queue: .main) { [weak self] _ in
            self?.enabled = true
        }
        center.addObserver(forName: turnOffNotification, object: nil, queue: .main) { [weak self] _ in
            self?.enabled = false
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

// MARK: - Command-line client

let usage = """
    usage: awake on|off|status

      on      keep the Mac awake (starts the menu-bar app if it isn't running)
      off     let the Mac sleep normally
      status  print on, off, or not running
    """

func appIsRunning() -> Bool {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        .contains { $0.processIdentifier != getpid() }
}

// Starts the app through its launchd agent so launchd keeps managing it.
func startApp() -> Bool {
    let launchctl = Process()
    launchctl.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    launchctl.arguments = ["kickstart", "gui/\(getuid())/\(bundleID)"]
    do {
        try launchctl.run()
    } catch {
        return false
    }
    launchctl.waitUntilExit()
    return launchctl.terminationStatus == 0
}

func turn(_ on: Bool) -> Int32 {
    Setting.enabled = on
    DistributedNotificationCenter.default().postNotificationName(
        on ? turnOnNotification : turnOffNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    if on && !appIsRunning() && !startApp() {
        FileHandle.standardError.write("awake: could not start the app; is the \(bundleID) agent loaded?\n".data(using: .utf8)!)
        return 1
    }
    return 0
}

func printStatus() -> Int32 {
    if !appIsRunning() {
        print("not running")
    } else {
        print(Setting.enabled ? "on" : "off")
    }
    return 0
}

func runCommand(_ command: String) -> Int32 {
    switch command {
    case "on": return turn(true)
    case "off": return turn(false)
    case "status": return printStatus()
    case "help", "-h", "--help":
        print(usage)
        return 0
    default:
        FileHandle.standardError.write("awake: unknown command '\(command)'\n\(usage)\n".data(using: .utf8)!)
        return 2
    }
}

// MARK: - Entry point

// launchd and Finder start the app with no arguments. Old Launch Services
// versions pass -psn_*, which still means "run the app".
let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") }

if let command = arguments.first {
    exit(runCommand(command))
}

let app = NSApplication.shared
let delegate = Awake()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
