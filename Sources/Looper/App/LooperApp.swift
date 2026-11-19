import AppKit
import SwiftUI

@main
struct LooperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// Not a @StateObject on purpose: the App body (and with it the whole menu bar) would then be
    /// rebuilt every time the controller publishes its transport snapshot, many times a second,
    /// which closes open submenus such as View › Theme. The views observe it via environmentObject.
    private let looper = LooperController.shared

    var body: some Scene {
        WindowGroup("Looper") {
            ContentView()
                .environmentObject(looper)
                .frame(minWidth: 1180, minHeight: 800)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 920)
        .commands { LooperCommands(looper: looper) }

        Settings {
            SettingsView()
                .environmentObject(looper)
        }

        Window("Effects", id: "effects") {
            EffectsWindow()
                .environmentObject(looper)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.topTrailing)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // no window tabs: removes the meaningless tab items from the View menu
        NSWindow.allowsAutomaticWindowTabbing = false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        // SwiftUI builds the menu bar after launch and rebuilds it now and then; put the Theme
        // submenu back whenever it is missing (cheap check, also while the app is in the background).
        let nc = NotificationCenter.default
        for name in [NSApplication.didUpdateNotification, NSApplication.didBecomeActiveNotification,
                     NSMenu.didBeginTrackingNotification, NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification] {
            nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                DispatchQueue.main.async { self?.ensureThemeMenu() }
            }
        }
        menuTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in self?.ensureThemeMenu() }
        ensureThemeMenu()
    }

    // MARK: View › Theme (AppKit, so the submenu always works)

    /// Set by the controller: applies a theme picked in the menu.
    static var onSelectTheme: ((AppTheme) -> Void)?
    private var themeItem: NSMenuItem?
    private var menuTimer: Timer?
    private var inserting = false

    private func makeThemeItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Theme", action: nil, keyEquivalent: "")
        let menu = NSMenu(title: "Theme")
        menu.delegate = self
        for (i, t) in AppTheme.allCases.enumerated() {
            let mi = NSMenuItem(title: t.label, action: #selector(selectTheme(_:)), keyEquivalent: i < 9 ? String(i + 1) : "")
            mi.keyEquivalentModifierMask = [.control, .command]
            mi.target = self
            mi.tag = i
            menu.addItem(mi)
        }
        item.submenu = menu
        return item
    }

    private func ensureThemeMenu() {
        guard !inserting,
              let view = NSApp.mainMenu?.items.first(where: { $0.title == "View" || $0.submenu?.title == "View" })?.submenu
        else { return }
        if let item = themeItem, item.menu === view { return }
        inserting = true
        defer { inserting = false }
        let item = themeItem ?? makeThemeItem()
        item.menu?.removeItem(item)
        themeItem = item
        // after "Show / Hide Rhythm Panel", else at the end
        if let anchor = view.items.firstIndex(where: { $0.title.contains("Rhythm Panel") }) {
            view.insertItem(item, at: anchor + 1)
        } else {
            view.addItem(item)
        }
    }

    @objc private func selectTheme(_ sender: NSMenuItem) {
        let all = AppTheme.allCases
        guard sender.tag >= 0 && sender.tag < all.count else { return }
        AppDelegate.onSelectTheme?(all[sender.tag])
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        let current = UserDefaults.standard.string(forKey: "appTheme") ?? AppTheme.midnight.rawValue
        for item in menu.items {
            let all = AppTheme.allCases
            guard item.tag >= 0 && item.tag < all.count else { continue }
            item.state = all[item.tag].rawValue == current ? .on : .off
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LooperCommands: Commands {
    /// Not observed on purpose: the controller publishes the transport state many times a
    /// second, and observing it would rebuild the menu bar constantly (submenus would close
    /// as soon as they open). The few values the menus show are read from UserDefaults.
    let looper: LooperController
    @AppStorage("appTheme") private var themeName = AppTheme.midnight.rawValue
    @AppStorage("showSidebar") private var sidebarShown = true
    @AppStorage("showRhythm") private var rhythmShown = true
    @Environment(\.openWindow) private var openWindow

    static func showAbout() {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
        #if arch(arm64)
        let arch = "Apple silicon (arm64)"
        #else
        let arch = "Intel (x86_64)"
        #endif
        let credits = NSAttributedString(
            string: "A phrase looper inspired by the BOSS RC-5.\n\(arch)\nDrums: Big Rusty Drums by Karoryfer Samples (CC0).",
            attributes: [.font: NSFont.systemFont(ofSize: 11), .foregroundColor: NSColor.secondaryLabelColor])
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Looper",
            .applicationVersion: LooperController.version,
            .version: "build \(build)",
            .credits: credits,
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Looper") { LooperCommands.showAbout() }
        }
        CommandGroup(replacing: .help) {
            SettingsButton(looper: looper, tab: .help) { Text("Looper Help & Shortcuts") }
                .keyboardShortcut("?", modifiers: .command)
            Divider()
            Button("Release Notes (v\(LooperController.version))") {
                if let url = URL(string: "https://github.com/lydianb79/RC5-Looper/releases/tag/v\(LooperController.version)") { NSWorkspace.shared.open(url) }
            }
            Button("Looper on GitHub") {
                if let url = URL(string: "https://github.com/lydianb79/RC5-Looper") { NSWorkspace.shared.open(url) }
            }
        }
        CommandGroup(replacing: .sidebar) {
            Button(sidebarShown ? "Hide Memories" : "Show Memories") { looper.showSidebar.toggle() }
                .keyboardShortcut("s", modifiers: [.control, .command])
            Button(rhythmShown ? "Hide Rhythm Panel" : "Show Rhythm Panel") { looper.showRhythm.toggle() }
                .keyboardShortcut("r", modifiers: [.control, .command])

            Divider()
            Divider()
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Overdub") { looper.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo Overdub") { looper.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        CommandMenu("Effects") {
            Button("Effects…") { openWindow(id: "effects") }
                .keyboardShortcut("f", modifiers: [.command, .option])
            Divider()
            Button("Input FX On / Off") { looper.toggleFX(input: true) }
            Button("Loop FX On / Off") { looper.toggleFX(input: false) }
        }
        CommandMenu("Looper") {
            Button("Play / Stop  (Space)") { looper.playStop() }
            Button("Record / Overdub  (R)") { looper.pedalTap() }
            Button("Stop  (Esc)") { looper.stop() }
            Button("Clear Loop") { looper.clear() }
                .keyboardShortcut(.delete, modifiers: .command)
            Divider()
            Button("Track 2 Record / Overdub  (2)") { looper.trackPress(0) }
            Button("Track 3 Record / Overdub  (3)") { looper.trackPress(1) }
            Button("Double Loop Length ×2  (D)") { looper.doubleLoop() }
                .keyboardShortcut("d", modifiers: .command)
            Button("Mute / Unmute Loop  (X)") { looper.toggleDrop() }
            Button("Fade Out and Stop  (F)") { looper.fadeOut() }
            Divider()
            Button("Start / Stop Song") { if looper.songActive { looper.stopSong() } else { looper.startSong() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button("Rhythm On / Off") { looper.toggleRhythm() }
                .keyboardShortcut("r", modifiers: .command)
            Button("Rhythm Variation A / B") { looper.toggleVariation() }
                .keyboardShortcut("b", modifiers: .command)
            Button("Tap Tempo") { looper.tapTempo() }
                .keyboardShortcut("t", modifiers: .command)
            Divider()
            Button("Write Memory") { looper.writeMemory() }
                .keyboardShortcut("s", modifiers: .command)
            Button("Next Memory") { looper.memoryUp() }
                .keyboardShortcut("]", modifiers: .command)
            Button("Previous Memory") { looper.memoryDown() }
                .keyboardShortcut("[", modifiers: .command)
            Divider()
            Button("Import Audio File…") { looper.importAudio() }
                .keyboardShortcut("i", modifiers: .command)
            Button("Export Loop as WAV…") { looper.exportAudio() }
                .keyboardShortcut("e", modifiers: .command)
            Button("Export Mix / Rhythm MIDI…") { looper.showExport = true }
                .keyboardShortcut("e", modifiers: [.command, .shift])
        }
    }
}
