import Foundation

/// A color of the interface: eight bits a channel, as it shows on the screen, with straight alpha.
struct RGBA: Equatable {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8

    init(_ r: Int, _ g: Int, _ b: Int, _ a: Int = 255) {
        self.r = UInt8(clamping: r)
        self.g = UInt8(clamping: g)
        self.b = UInt8(clamping: b)
        self.a = UInt8(clamping: a)
    }

    /// A linear color of the scene, as it shows on the screen.
    init(linear color: SIMD3<Float>, alpha: Float = 1) {
        func encode(_ c: Float) -> Int { Int((pow(min(max(c, 0), 1), 1 / 2.2) * 255).rounded()) }
        self.init(encode(color.x), encode(color.y), encode(color.z), Int((min(max(alpha, 0), 1) * 255).rounded()))
    }

    /// The color with its alpha scaled.
    func faded(_ opacity: Float) -> RGBA {
        var color = self
        color.a = UInt8(min(max(Float(a) * opacity, 0), 255))
        return color
    }

    /// Part of the way to another color, every channel alpha included.
    func mixed(with other: RGBA, _ t: Float) -> RGBA {
        let t = min(max(t, 0), 1)
        func mix(_ x: UInt8, _ y: UInt8) -> Int { Int((Float(x) + (Float(y) - Float(x)) * t).rounded()) }
        return RGBA(mix(r, other.r), mix(g, other.g), mix(b, other.b), mix(a, other.a))
    }
}
