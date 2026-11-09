import Foundation

/// Curves for animation and blending.
enum Easing {
    static func saturate(_ x: Float) -> Float { min(max(x, 0), 1) }

    static func smoothStep(_ edge0: Float, _ edge1: Float, _ x: Float) -> Float {
        let t = saturate((x - edge0) / (edge1 - edge0))
        return t * t * (3 - 2 * t)
    }

    /// Starts and ends at rest, with no jolt in the acceleration either: 6t^5 - 15t^4 + 10t^3.
    static func smootherStep(_ t: Float) -> Float { t * t * t * (t * (t * 6 - 15) + 10) }

    /// A step of at most `step` from a value towards a target.
    static func approach(_ value: Float, _ target: Float, step: Float) -> Float {
        value < target ? min(value + step, target) : max(value - step, target)
    }

    /// The share of the way to a target covered in `seconds` by a motion that slows as it nears it, `rate` per second.
    static func exponential(_ seconds: Float, rate: Float) -> Float { 1 - exp(-seconds * rate) }
}
