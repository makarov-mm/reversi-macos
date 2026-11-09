import Foundation

/// The sound effects, made up from sine waves and noise: a knock for a disc set down, clicks for discs turning over,
/// a bell for a pass, a chord at the end.
enum SoundSynth {
    static let rate = 44_100.0

    static func place() -> [Float] { normalized(knock(pitch: 1.0, seed: 1), volume: 0.6) }
    static func flip() -> [Float] { normalized(knock(pitch: 2.2, seed: 4, length: 0.45), volume: 0.3) }
    static func stack() -> [Float] { normalized(knock(pitch: 1.6, seed: 6), volume: 0.3) }
    static func pass() -> [Float] { normalized(bell(frequency: 659.25, length: 0.8), volume: 0.22) }

    static func gameOver() -> [Float] {
        var chord = silence(1.8)
        for (index, note) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
            add(bell(frequency: note, length: 1.5), to: &chord, at: Double(index) * 0.11, gain: 0.8)
        }
        return normalized(chord, volume: 0.35)
    }

    static func click() -> [Float] {
        let samples = (0..<Int(0.03 * rate)).map { i -> Float in
            let t = Double(i) / rate
            return Float(sin(2 * Double.pi * 2600 * t) * exp(-t / 0.004))
        }
        return normalized(samples, volume: 0.18)
    }

    private static func silence(_ seconds: Double) -> [Float] { [Float](repeating: 0, count: Int(seconds * rate)) }

    private static func add(_ source: [Float], to target: inout [Float], at seconds: Double, gain: Float) {
        let offset = Int(seconds * rate)
        if target.count < offset + source.count {
            target += [Float](repeating: 0, count: offset + source.count - target.count)
        }
        for (i, sample) in source.enumerated() {
            target[offset + i] += sample * gain
        }
    }

    /// A knock of a disc on wood: a short burst of filtered noise and quickly damped resonances; `length` shortens or
    /// lengthens how it rings.
    private static func knock(pitch: Double, seed: UInt64, length: Double = 1) -> [Float] {
        var random = SplitMix64(seed: seed)
        var filtered: Double = 0
        return (0..<Int(0.16 * length * rate)).map { i -> Float in
            let t = Double(i) / rate
            filtered += (Double.random(in: -1...1, using: &random) - filtered) * 0.35
            let burst = filtered * exp(-t / (0.006 * length))
            let body = 0.55 * sin(2 * Double.pi * 620 * pitch * t) * exp(-t / (0.028 * length))
                + 0.3 * sin(2 * Double.pi * 1480 * pitch * t) * exp(-t / (0.012 * length))
                + 0.45 * sin(2 * Double.pi * 170 * pitch * t) * exp(-t / (0.045 * length))
            let attack = min(1, t / 0.0008)
            return Float((burst * 0.9 + body) * attack)
        }
    }

    /// A small bell: inharmonic partials dying away at their own rates.
    private static func bell(frequency: Double, length: Double) -> [Float] {
        let partials: [(ratio: Double, gain: Double, decay: Double)] = [(1.0, 1.0, 1.0), (2.0, 0.45, 0.6), (2.76, 0.3, 0.4), (5.4, 0.12, 0.25)]
        return (0..<Int(length * rate)).map { i -> Float in
            let t = Double(i) / rate
            var value: Double = 0
            for partial in partials {
                value += partial.gain * sin(2 * Double.pi * frequency * partial.ratio * t) * exp(-t / (length * 0.35 * partial.decay))
            }
            return Float(value * min(1, t / 0.004))
        }
    }

    /// Scaled so that its loudest sample reaches `volume`.
    private static func normalized(_ samples: [Float], volume: Float) -> [Float] {
        let peak = samples.reduce(Float(1e-6)) { max($0, abs($1)) }
        return samples.map { $0 / peak * volume }
    }
}
