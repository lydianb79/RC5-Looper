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
                .frame(minWidth: 1020, minHeight: 560)
        }
        .defaultSize(width: 1140, height: 760)
        .commands { LooperCommands(looper: looper) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct LooperCommands: Commands {
    let looper: LooperController

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Audio Devices…") { looper.selectedTab = .audio }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandMenu("Looper") {
            Button("Rec / Play / Dub  (Space)") { looper.pedalTap() }
            Button("Stop  (Esc)") { looper.stop() }
            Button("Undo / Redo Last Overdub") { looper.undoRedo() }
                .keyboardShortcut("u", modifiers: .command)
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
