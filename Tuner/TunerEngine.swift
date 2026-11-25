import AVFoundation
import SwiftUI
import UIKit

/// Listens to the microphone, finds the pitch, and decides what the beginner should do.
@MainActor
final class TunerEngine: ObservableObject {
    enum Mic { case unknown, granted, denied }

    @Published var mic: Mic = .unknown
    @Published var hearing = false            // a clear note is coming in
    @Published var frequency: Double = 0
    @Published var cents: Double = 0          // smoothed, clamped to +-50
    @Published var target: GuitarString = GuitarString.standard[0]
    @Published var lockedString: GuitarString?  // nil = auto-detect
    @Published var tuned: Set<Int> = []       // strings that have been held in tune
    @Published var isPlayingTone = false
    @Published var tuning: Tuning = .standard {
        didSet {
            guard tuning != oldValue else { return }
            tuned = []
            lockedString = nil
            target = tuning.strings[0]
            recent.removeAll()
        }
    }

    static let inTuneCents = 5.0

    private let engine = AVAudioEngine()
    private let tone = ToneSource()
    private var toneNode: AVAudioSourceNode?
    private var samples: [Float] = []
    private var recent: [Double] = []
    private var lastHeard = Date.distantPast
    private var inTuneSince: Date?
    private var silenceTimer: Timer?
    private let haptic = UINotificationFeedbackGenerator()

    var isInTune: Bool { hearing && abs(cents) <= Self.inTuneCents }

    func start() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil { return }  // unit tests: no mic
        AVAudioApplication.requestRecordPermission { ok in
            Task { @MainActor in
                self.mic = ok ? .granted : .denied
                if ok { self.startEngine() }
            }
        }
    }

    func stop() {
        engine.stop()
    }

    private var didSetUp = false

    func select(_ string: GuitarString?) {
        lockedString = string
        if let string {
            target = string
            playTone(string)
        }
    }

    func resetProgress() { tuned = [] }

    // MARK: Audio

    private func startEngine() {
        guard !engine.isRunning else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement,
                                    options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
        } catch { print("session:", error) }

        if didSetUp {   // coming back from the background: nodes are already wired
            do { try engine.start() } catch { print("engine:", error) }
            return
        }
        didSetUp = true

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let rate = format.sampleRate
        guard rate > 0 else { return }

        // Reference tone player
        let outFormat = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1)!
        let src = tone
        src.sampleRate = rate
        let node = AVAudioSourceNode(format: outFormat) { _, _, frames, abl in
            src.render(frames: Int(frames), into: abl)
            return noErr
        }
        toneNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: outFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
            guard let ch = buffer.floatChannelData?[0] else { return }
            let chunk = Array(UnsafeBufferPointer(start: ch, count: Int(buffer.frameLength)))
            Task { @MainActor in self?.ingest(chunk, rate: rate) }
        }

        do { try engine.start() } catch { print("engine:", error) }

        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSilence() }
        }
    }

    private let windowSize = 4096

    private func ingest(_ chunk: [Float], rate: Double) {
        samples.append(contentsOf: chunk)
        guard samples.count >= windowSize else { return }
        let window = Array(samples.suffix(windowSize))
        samples.removeFirst(samples.count - windowSize / 2)   // 50% overlap

        // Ignore our own reference tone and anything too quiet to be a plucked string
        guard !tone.isSounding, YIN.rms(window) > 0.004 else { return }

        Task.detached(priority: .userInitiated) {
            let f = YIN.pitch(window, sampleRate: rate)
            await MainActor.run { if let f { self.heard(f) } }
        }
    }

    private func heard(_ f: Double) {
        let string = lockedString ?? GuitarString.nearest(to: f, in: tuning)
        // Guitar strings ring with strong overtones; fold an octave error back toward the target.
        var f = f
        while centsOff(f, string.frequency) > 700 { f /= 2 }
        while centsOff(f, string.frequency) < -700 { f *= 2 }

        if string != target { recent.removeAll() }
        target = string

        recent.append(f)
        if recent.count > 5 { recent.removeFirst() }
        let median = recent.sorted()[recent.count / 2]

        frequency = median
        let c = max(-50, min(50, centsOff(median, string.frequency)))
        withAnimation(.easeOut(duration: 0.15)) {
            cents = c
            hearing = true
        }
        lastHeard = Date()

        if abs(c) <= Self.inTuneCents {
            if inTuneSince == nil { inTuneSince = Date() }
            if let t = inTuneSince, Date().timeIntervalSince(t) > 0.6, !tuned.contains(string.number) {
                tuned.insert(string.number)
                haptic.notificationOccurred(.success)
            }
        } else {
            inTuneSince = nil
        }
    }

    private func checkSilence() {
        if hearing && Date().timeIntervalSince(lastHeard) > 1.5 {
            withAnimation(.easeOut(duration: 0.3)) { hearing = false }
            recent.removeAll()
            inTuneSince = nil
        }
        isPlayingTone = tone.isSounding
    }

    private func playTone(_ string: GuitarString) {
        if !engine.isRunning { startEngine() }
        tone.play(frequency: string.frequency)
        isPlayingTone = true
    }
}

/// A soft plucked-string sound so beginners can hear the note they are aiming for.
/// Written from the main thread, read from the audio thread; small races here are harmless.
final class ToneSource {
    var sampleRate: Double = 48000
    private var frequency: Double = 110
    private var phase: Double = 0
    private var age: Double = 10
    private let length: Double = 2.0

    var isSounding: Bool { age < length + 0.3 }   // +0.3 s so the room echo is ignored too

    func play(frequency: Double) {
        self.frequency = frequency
        phase = 0
        age = 0
    }

    func render(frames: Int, into abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        let step = 1.0 / sampleRate
        for i in 0..<frames {
            var v: Float = 0
            if age < length {
                let attack = min(1, age / 0.01)
                let env = attack * exp(-age * 2.2)
                let p = phase * 2 * .pi
                v = Float(env * (0.6 * sin(p) + 0.25 * sin(2 * p) + 0.12 * sin(3 * p)) * 0.5)
                phase += frequency * step
                if phase > 1 { phase -= 1 }
            }
            age += step
            for b in buffers {
                b.mData?.assumingMemoryBound(to: Float.self)[i] = v
            }
        }
    }
}
