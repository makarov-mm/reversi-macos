import AVFoundation

/// The sound effects, played on the default output over each other: each of a few players takes the next sound in
/// turn, so that a new sound cuts off only the oldest. Without an output device, there is no sound.
@MainActor
final class SoundBank {
    enum Effect: CaseIterable {
        case place, flip, stack, pass, gameOver, click
    }

    private static let voices = 16

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Effect: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var observer: NSObjectProtocol?

    var isEnabled = true {
        didSet {
            if !isEnabled {
                players.forEach { $0.stop() }
            }
        }
    }

    init() {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.rate, channels: 1) else { return }
        for effect in Effect.allCases {
            let samples = Self.samples(effect)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
                  let channel = buffer.floatChannelData?[0] else { continue }
            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
            buffers[effect] = buffer
        }
        for _ in 0..<Self.voices {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }
        // The engine stops when the output device changes, such as when headphones are plugged in.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.start()
            }
        }
        start()
    }

    func play(_ effect: Effect) {
        guard isEnabled, let buffer = buffers[effect], !players.isEmpty else { return }
        if !engine.isRunning {
            start()
        }
        guard engine.isRunning else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying {
            player.play()
        }
    }

    private func start() {
        guard !players.isEmpty, !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            FileHandle.standardError.write(Data("3D Reversi: no sound: \(error.localizedDescription)\n".utf8))
        }
    }

    private static func samples(_ effect: Effect) -> [Float] {
        switch effect {
        case .place: SoundSynth.place()
        case .flip: SoundSynth.flip()
        case .stack: SoundSynth.stack()
        case .pass: SoundSynth.pass()
        case .gameOver: SoundSynth.gameOver()
        case .click: SoundSynth.click()
        }
    }
}
