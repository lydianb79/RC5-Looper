import AppKit
import SwiftUI

@main
struct LooperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var looper = LooperController()

    var body: some Scene {
        WindowGroup("Looper") {
            ContentView()
                .environmentObject(looper)
                .frame(minWidth: 1120, minHeight: 720)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1440, height: 920)
        .commands { LooperCommands(looper: looper) }

        Settings {
            SettingsView()
                .environmentObject(looper)
        }
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
    @AppStorage("showTracks") private var tracksShown = true
    @AppStorage("showEffects") private var fxShown = true

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
            Button(tracksShown ? "Hide Tracks" : "Show Tracks") { looper.showTracks.toggle() }
                .keyboardShortcut("t", modifiers: [.control, .command])
            Button(fxShown ? "Hide Effects" : "Show Effects") { looper.showEffects.toggle() }
                .keyboardShortcut("e", modifiers: [.control, .command])
            Divider()
            // The menu bar no longer observes the controller (see above), so it is only rebuilt
            // when one of the values it shows changes and the submenu stays open.
            Menu("Theme") {
                ForEach(Array(AppTheme.allCases.enumerated()), id: \.element) { i, t in
                    if i < 9 {
                        Button((themeName == t.rawValue ? "✓  " : "     ") + t.label) { looper.appTheme = t }
                            .keyboardShortcut(KeyEquivalent(Character(String(i + 1))), modifiers: [.control, .command])
                    } else {
                        Button((themeName == t.rawValue ? "✓  " : "     ") + t.label) { looper.appTheme = t }
                    }
                }
            }
            Divider()
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo Overdub") { looper.undo() }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo Overdub") { looper.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
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
