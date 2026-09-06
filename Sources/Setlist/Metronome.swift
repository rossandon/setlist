import AVFoundation
import Foundation

/// State shared with the audio render callback.
///
/// The callback runs on a real-time thread, so nothing in here may allocate,
/// lock, or call into Swift runtime machinery. Fields written by the UI are
/// plain aligned scalars: a stale read just means a tempo change lands one
/// beat later, which is harmless.
private final class ClickState: @unchecked Sendable {
    let sampleRate: Double

    // Written by the UI thread.
    var samplesPerBeat: Double
    var beatsPerBar: Int = 4
    var accentEnabled: Bool = true
    var gain: Double = 0.5

    // Owned by the audio thread.
    var sampleIndex: Double = 0
    var nextBeatSample: Double = 0
    var beatInBar: Int = 0
    var clickPos: Double = 0
    var clickRemaining: Int = 0
    var clickFreq: Double = 1000

    // Written by the audio thread, read by the UI for the beat indicator.
    var beatCounter: Int = 0
    var displayBeat: Int = 0

    init(sampleRate: Double, bpm: Double) {
        self.sampleRate = sampleRate
        self.samplesPerBeat = 60.0 / bpm * sampleRate
    }

    func rewind() {
        sampleIndex = 0
        nextBeatSample = 0
        beatInBar = beatsPerBar - 1  // so the first beat lands on 1
        clickRemaining = 0
        beatCounter = 0
        displayBeat = 0
    }
}

/// A drift-free metronome.
///
/// Beat times are computed as absolute sample positions against the audio
/// clock rather than scheduled on a run loop, so the click cannot drift
/// relative to what you actually hear, no matter how long it runs.
@MainActor
final class Metronome: ObservableObject {
    @Published var bpm: Double = 120 { didSet { applyTempo() } }
    @Published var beatsPerBar: Int = 4 { didSet { state.beatsPerBar = max(1, beatsPerBar) } }
    @Published var accentFirstBeat: Bool = true { didSet { state.accentEnabled = accentFirstBeat } }
    @Published var volume: Double = 0.5 { didSet { state.gain = volume } }
    @Published private(set) var isRunning = false

    /// Beat within the bar, 0-based. Polled by the UI for the flash indicator.
    @Published private(set) var displayBeat: Int = 0

    private let engine = AVAudioEngine()
    private let state: ClickState
    private var sourceNode: AVAudioSourceNode!
    private var indicatorTimer: Timer?

    private static let accentFreq: Double = 1567.98  // G6
    private static let normalFreq: Double = 987.77   // B5
    private static let clickSeconds: Double = 0.035
    private static let decay: Double = 45

    init() {
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 48_000
        state = ClickState(sampleRate: sampleRate, bpm: 120)

        // Match the hardware rate so the engine never has to resample us.
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let st = state  // captured instead of self, so the node holds no cycle
        let clickLength = Int(sampleRate * Metronome.clickSeconds)
        let accent = Metronome.accentFreq
        let normal = Metronome.normalFreq
        let decay = Metronome.decay

        sourceNode = AVAudioSourceNode(format: format) { _, _, frameCount, audioBufferList in
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)

            for frame in 0..<Int(frameCount) {
                if st.sampleIndex >= st.nextBeatSample {
                    let bar = max(1, st.beatsPerBar)
                    st.beatInBar = (st.beatInBar + 1) % bar
                    st.clickFreq = (st.accentEnabled && st.beatInBar == 0) ? accent : normal
                    st.clickPos = 0
                    st.clickRemaining = clickLength
                    st.beatCounter &+= 1
                    st.displayBeat = st.beatInBar
                    // Accumulate in Double so fractional samples per beat never
                    // round away into drift.
                    st.nextBeatSample += st.samplesPerBeat
                }

                var sample: Float = 0
                if st.clickRemaining > 0 {
                    let t = st.clickPos / st.sampleRate
                    let envelope = exp(-t * decay)
                    sample = Float(sin(2 * Double.pi * st.clickFreq * t) * envelope * st.gain)
                    st.clickPos += 1
                    st.clickRemaining -= 1
                }

                for buffer in buffers {
                    let ptr = buffer.mData!.assumingMemoryBound(to: Float.self)
                    ptr[frame] = sample
                }

                st.sampleIndex += 1
            }
            return noErr
        }

        engine.attach(sourceNode)
        engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
        engine.prepare()
    }

    func start() {
        guard !isRunning else { return }
        state.beatsPerBar = max(1, beatsPerBar)
        state.accentEnabled = accentFirstBeat
        state.gain = volume
        applyTempo()
        state.rewind()
        do {
            try engine.start()
        } catch {
            NSLog("Metronome failed to start: \(error.localizedDescription)")
            return
        }
        isRunning = true
        indicatorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isRunning else { return }
                if self.displayBeat != self.state.displayBeat {
                    self.displayBeat = self.state.displayBeat
                }
            }
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.pause()
        isRunning = false
        indicatorTimer?.invalidate()
        indicatorTimer = nil
        displayBeat = 0
    }

    func toggle() { isRunning ? stop() : start() }

    private func applyTempo() {
        let clamped = min(max(bpm, 20), 400)
        state.samplesPerBeat = 60.0 / clamped * state.sampleRate
    }
}
