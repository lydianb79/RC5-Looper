# Looper — a native macOS phrase looper modeled on the BOSS RC-5

A native SwiftUI + AVAudioEngine app for macOS 13+ (Apple silicon and Intel). It works like the RC-5: one stereo track, one pedal, rhythm guide, 99 phrase memories.

## Build & run

Requirements: macOS 13 Ventura or later, plus Xcode 15+ (or the Xcode Command Line Tools with Swift 5.9+).

```bash
cd Looper
./build_app.sh release --open      # builds build/Looper.app and launches it
```

Copy `build/Looper.app` to /Applications if you like. On first launch, macOS asks for microphone access. Pick the input and output device (built-in, a USB/Thunderbolt audio interface, or an aggregate device), the input channels and the buffer size on the **Audio** tab (also the AUDIO button on the panel, or ⌘,).

You can also run `open Package.swift` to work in Xcode. For recording, run the bundled app from the build script: a bare executable has no `NSMicrophoneUsageDescription`, so macOS won't grant it microphone access.

## RC-5 feature mapping

| RC-5 | Looper |
|---|---|
| 1 stereo track, 32-bit float | Stereo 32-bit float engine at the device sample rate. Max loop length is set in Setup (default 10 min; memory is only used for what you record). |
| Pedal: REC → DUB → PLAY | Big pedal / **Space**. Rec action can be REC→DUB→PLAY or REC→PLAY→DUB. |
| Double press = STOP | Double-press the pedal (or **Esc**, the STOP footswitch). |
| Hold pedal = UNDO/REDO, hold when stopped = CLEAR | Same (2 s hold). UNDO/REDO and CLEAR footswitches too. |
| Overdub / Replace dub mode | Both modes. Replace is also undoable. |
| Loop quantize | Loop length snaps to whole bars when the rhythm is on. |
| Auto rec, count-in | Both, with an adjustable auto-rec threshold. |
| Start: immediate / fade in · Stop: immediate / fade out / loop end | All of them, with adjustable fade time. A second stop press stops right away. |
| One shot, reverse | Both. |
| Tempo: tap / derived from loop, change loop tempo | Tap tempo (**T**). Without rhythm, the tempo is worked out from the loop length. After recording, the tempo stays live: changing it (slider, tap, ±) speeds the loop up or down from 50 % to 200 % and the rhythm follows. **Keep pitch** uses a granular time-stretch; **Varispeed** works like tape, so the pitch follows the speed. You can overdub at any tempo. **Original tempo** returns to the recorded speed. |
| — | Audio device selection (input/output), input channel selection for multichannel interfaces, and buffer size from 32 to 2048 frames. |
| 57 rhythm patterns × 2 variations, 7 kits, rhythm reverb | 57 synthesized patterns (Rock, Pop, Funk, Blues, Jazz, Latin, Reggae, Metal, Electronic, Country, odd meters, metronome), each with variations A and B. The 7 kits are Studio, Live, Light, Heavy, Rock, Metal and Electronic. Rhythm reverb included. |
| Loop level / rhythm level | LOOP LEVEL knob (0–200) and rhythm level. |
| 99 phrase memories (audio + rhythm/kit/settings) | 99 memories in `~/Library/Application Support/Looper/Memories/NN/` (`loop.wav` + `settings.json`). Switching memories with unsaved changes asks first. |
| USB WAV import / export | Import any audio file (WAV/AIFF/CAF/MP3/M4A; it is resampled) and export as 32-bit float WAV. |
| MIDI I/O, sync | MIDI remote control from all MIDI inputs. MIDI clock + start/stop go out on a virtual port called "Looper". |

### MIDI map
CC80 pedal (≥64 press / <64 release) · CC81 stop · CC82 undo/redo · CC83 clear · CC84 rhythm on/off · CC85 variation A/B · CC86 loop level · Note 60 pedal, 61 stop, 62 undo, 63 clear, 64 rhythm, 65 tap, 66 variation · Program change 0–98 selects memory 1–99.

### Keyboard
Space pedal · Esc/S stop · U undo/redo · Delete clear · R rhythm · B variation · T tap · ←/→ memory · ⌘S write · ⌘I import · ⌘E export.

## Architecture

```
Sources/Looper
├── App/LooperApp.swift          SwiftUI app, menu commands
├── Audio/
│   ├── LoopCore.swift           realtime looper: state machine, layers, undo, quantize, fades, latency comp, time-stretch
│   ├── AudioDevices.swift       Core Audio device list, channel counts, buffer size, latency
│   ├── RhythmEngine.swift       step sequencer + synthesized drum kit + reverb
│   ├── RhythmLibrary.swift      57 patterns, 7 kits
│   └── AudioEngineManager.swift AVAudioEngine graph (sink node → core → source node)
├── Model/
│   ├── LooperController.swift   pedal logic (tap / double / hold), memories, MIDI, keyboard, UI snapshot
│   ├── MemoryStore.swift        99 memories, WAV read/write
│   └── Settings.swift           enums, per-memory settings
├── MIDI/MIDIManager.swift       CoreMIDI in/out + clock
└── Views/                       pedal panel, LCD, Setup / Rhythm / Memory / Help panels
```

Realtime design: the audio thread never allocates or blocks. UI commands go through a small queue that the audio thread reads with `os_unfair_lock_trylock`. The loop is stored as `base + layerA + layerB`. Each overdub writes to its own layer, so undo/redo just mutes or unmutes it. When the next overdub starts, the previous layer is merged into the base a chunk at a time. Merging waits 2.5 s, so a double-press or a hold can still cancel the overdub that was just started.

## Tips & known limits
- **Themes:** Midnight (default), Crimson (RC-5 red) and Arctic — palette icon in the header or Setup › Appearance.
- **Latency compensation** (Setup › Audio) shifts overdubs so they line up with what you heard. Start from the estimate, then fine-tune by ear.
- Use headphones, or plug a guitar into an audio interface: the built-in mic plus speakers will feed back into the loop.
- The buffer size is a device setting, so it also affects other apps using the same interface.
- Different input and output devices run on separate clocks. If they won't start together or drift, combine them into an Aggregate Device in Audio MIDI Setup.
- Output always goes to outputs 1–2 of the selected device.
- The memory always stores the loop at its recorded tempo, together with the current tempo. Export WAV writes the loop at its original speed.
- Keep pitch stretching is a simple granular method. Very large tempo changes can sound slightly phasey; Varispeed sounds clean but shifts the pitch.
