import CoreMIDI
import Foundation

/// MIDI in: remote control from any connected controller / footswitch.
/// MIDI out: a virtual source named "Looper" that sends MIDI clock + start/stop.
final class MIDIManager {
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var source = MIDIEndpointRef()
    private let clockQueue = DispatchQueue(label: "looper.midi.clock", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var clockTempo: Double = 0
    private(set) var clockRunning = false
    private(set) var available = false
    /// (status, data1, data2), delivered on the main queue. Includes realtime Start (FA), Continue (FB), Stop (FC).
    var onMessage: ((UInt8, UInt8, UInt8) -> Void)?
    /// Tempo measured from incoming MIDI clock (24 ticks per quarter note), delivered on the main queue.
    var onClockTempo: ((Double) -> Void)?

    // incoming clock measurement (MIDI thread only)
    private var tickRing = [UInt64](repeating: 0, count: 25)
    private var tickWrite = 0
    private var tickCount = 0
    private var lastTick: UInt64 = 0
    private var smoothedTempo = 0.0
    private var ticksSinceReport = 0
    private let nsPerHostTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(max(1, info.denom))
    }()

    init() {
        var c = MIDIClientRef()
        let status = MIDIClientCreateWithBlock("Looper" as CFString, &c) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async { self?.connectSources() }
            }
        }
        guard status == noErr else { return }
        client = c

        var p = MIDIPortRef()
        let ps = MIDIInputPortCreateWithBlock(client, "Looper In" as CFString, &p) { [weak self] list, _ in
            self?.parse(list)
        }
        if ps == noErr { inPort = p }

        var s = MIDIEndpointRef()
        if MIDISourceCreate(client, "Looper" as CFString, &s) == noErr { source = s }
        available = true
        connectSources()
    }

    func connectSources() {
        guard inPort != 0 else { return }
        let count = MIDIGetNumberOfSources()
        for i in 0..<count {
            let src = MIDIGetSource(i)
            if src != source { MIDIPortConnectSource(inPort, src, nil) }
        }
    }

    var sourceCount: Int { MIDIGetNumberOfSources() }

    private func parse(_ list: UnsafePointer<MIDIPacketList>) {
        var messages: [(UInt8, UInt8, UInt8)] = []
        for packet in list.unsafeSequence() {
            let len = min(Int(packet.pointee.length), 256)
            let bytes: [UInt8] = withUnsafeBytes(of: packet.pointee.data) { Array($0.prefix(len)) }
            var i = 0
            var status: UInt8 = 0
            while i < bytes.count {
                let b = bytes[i]
                if b >= 0xF8 {                                      // realtime
                    if b == 0xF8 {
                        clockTick(packet.pointee.timeStamp)
                    } else if b == 0xFA || b == 0xFB || b == 0xFC {
                        if b == 0xFA || b == 0xFC { resetClock() }
                        messages.append((b, 0, 0))
                    }
                    i += 1
                    continue
                }
                if b & 0x80 != 0 {
                    status = b >= 0xF0 ? 0 : b                       // ignore system common / sysex
                    i += 1
                    continue
                }
                guard status != 0 else { i += 1; continue }
                let type = status & 0xF0
                let needs = (type == 0xC0 || type == 0xD0) ? 1 : 2
                guard i + needs <= bytes.count else { break }
                let d1 = bytes[i]
                let d2: UInt8 = needs == 2 ? bytes[i + 1] : 0
                messages.append((status, d1, d2))
                i += needs
            }
        }
        guard !messages.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            for m in messages { self?.onMessage?(m.0, m.1, m.2) }
        }
    }

    private func resetClock() {
        tickCount = 0
        tickWrite = 0
    }

    /// Measures the tempo over the last 24 clock ticks (one quarter note).
    private func clockTick(_ stamp: MIDITimeStamp) {
        let t = stamp != 0 ? stamp : mach_absolute_time()
        if lastTick != 0, t > lastTick, Double(t - lastTick) * nsPerHostTick > 500_000_000 {
            resetClock()                                    // clock was paused
        }
        lastTick = t
        tickRing[tickWrite] = t
        tickWrite = (tickWrite + 1) % tickRing.count
        tickCount += 1
        guard tickCount >= tickRing.count else { return }
        let oldest = tickRing[tickWrite]
        guard t > oldest else { return }
        let seconds = Double(t - oldest) * nsPerHostTick / 1e9
        guard seconds > 0 else { return }
        let bpm = 60.0 / seconds
        guard bpm > 20 && bpm < 400 else { return }
        smoothedTempo = smoothedTempo == 0 ? bpm : smoothedTempo * 0.85 + bpm * 0.15
        ticksSinceReport += 1
        if ticksSinceReport >= 12 {
            ticksSinceReport = 0
            let rounded = (smoothedTempo * 10).rounded() / 10
            DispatchQueue.main.async { [weak self] in self?.onClockTempo?(rounded) }
        }
    }

    private func send(_ bytes: [UInt8]) {
        guard available, source != 0 else { return }
        var buffer = [UInt8](repeating: 0, count: 128)
        buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            let list = base.assumingMemoryBound(to: MIDIPacketList.self)
            let pkt = MIDIPacketListInit(list)
            _ = MIDIPacketListAdd(list, 128, pkt, 0, bytes.count, bytes)
            MIDIReceived(source, list)
        }
    }

    /// Keeps the outgoing MIDI clock in sync with the looper transport.
    func updateClock(running: Bool, tempo: Double) {
        if running {
            if !clockRunning {
                clockRunning = true
                send([0xFA])
                startTimer(tempo)
            } else if abs(tempo - clockTempo) > 0.01 {
                startTimer(tempo)
            }
        } else if clockRunning {
            clockRunning = false
            timer?.cancel()
            timer = nil
            send([0xFC])
        }
    }

    private func startTimer(_ tempo: Double) {
        timer?.cancel()
        clockTempo = tempo
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: clockQueue)
        let interval = 60.0 / (max(20, tempo) * 24.0)
        t.schedule(deadline: .now(), repeating: interval, leeway: .microseconds(200))
        t.setEventHandler { [weak self] in self?.send([0xF8]) }
        t.resume()
        timer = t
    }
}
