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
    @ObservedObject var looper: LooperController

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
            Button(looper.showSidebar ? "Hide Memories" : "Show Memories") { looper.showSidebar.toggle() }
                .keyboardShortcut("s", modifiers: [.control, .command])
            Button(looper.showRhythm ? "Hide Rhythm Panel" : "Show Rhythm Panel") { looper.showRhythm.toggle() }
                .keyboardShortcut("r", modifiers: [.control, .command])
            Divider()
            Menu("Theme") {
                ForEach(AppTheme.allCases) { t in
                    Toggle(t.label, isOn: Binding(get: { looper.appTheme == t }, set: { if $0 { looper.appTheme = t } }))
                }
            }
            Divider()
        }
        CommandGroup(replacing: .undoRedo) {
            Button("Undo / Redo Last Overdub") { looper.undoRedo() }
                .keyboardShortcut("z", modifiers: .command)
        }
        CommandMenu("Looper") {
            Button("Play / Stop  (Space)") { looper.playStop() }
            Button("Record / Overdub  (R)") { looper.pedalTap() }
            Button("Stop  (Esc)") { looper.stop() }
            Button("Clear Loop") { looper.clear() }
                .keyboardShortcut(.delete, modifiers: .command)
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
        }
    }
}
