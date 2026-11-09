import Foundation
import simd

/// A camera circling the board. Its moves are eased: dragging, zooming and turning set where it heads.
struct OrbitCamera {
    private static let defaultPitch: Float = 0.84
    private static let defaultDistance: Float = 15.5
    private static let fieldOfView: Float = 0.6
    private static let minAspect: Float = 1.4 // of the space for the board, below which the view widens
    private static let pitchRange: ClosedRange<Float> = 0.22...1.53
    private static let distanceRange: ClosedRange<Float> = 8...26
    private static let target = SIMD3<Float>(0, 0.15, 0)

    private var yaw: Float = 0
    private var pitch = defaultPitch
    private var distance = defaultDistance
    private var shift: Float = 0
    private var space: Float = 1
    private var targetYaw: Float = 0
    private var targetPitch = defaultPitch
    private var targetDistance = defaultDistance
    private var targetShift: Float = 0
    private var targetSpace: Float = 1
    private var topView = false
    private var savedPitch = defaultPitch

    /// Black looks from +z, where row 8 is near; White from the other side.
    mutating func face(_ side: Side) {
        targetYaw = Self.unwrap(side == .black ? 0 : Float.pi, near: targetYaw)
    }

    mutating func flip() {
        targetYaw += Float.pi
    }

    mutating func toggleTopView() {
        topView.toggle()
        if topView {
            savedPitch = targetPitch
            targetPitch = Self.pitchRange.upperBound
        } else {
            targetPitch = savedPitch
        }
    }

    mutating func reset(_ side: Side) {
        face(side)
        targetPitch = Self.defaultPitch
        targetDistance = Self.defaultDistance
        topView = false
    }

    mutating func rotate(yaw yawRadians: Float, pitch pitchRadians: Float) {
        targetYaw += yawRadians
        targetPitch = min(max(targetPitch + pitchRadians, Self.pitchRange.lowerBound), Self.pitchRange.upperBound)
        topView = false
    }

    mutating func zoom(_ steps: Float) {
        targetDistance = min(max(targetDistance * pow(0.9, steps), Self.distanceRange.lowerBound), Self.distanceRange.upperBound)
    }

    /// The share of the window's width left for the board beside the panel: the view centers on it, and widens when it
    /// is narrow, so the board and the discs beside it stay in sight.
    mutating func setSpace(_ share: Float) {
        targetShift = (share - 1) / 2
        targetSpace = share
    }

    mutating func update(_ seconds: Float) {
        let ease = Easing.exponential(seconds, rate: 9)
        yaw += (targetYaw - yaw) * ease
        pitch += (targetPitch - pitch) * ease
        distance += (targetDistance - distance) * ease
        shift += (targetShift - shift) * ease
        space += (targetSpace - space) * ease
    }

    var isMoving: Bool {
        abs(targetYaw - yaw) > 1e-4 || abs(targetPitch - pitch) > 1e-4 || abs(targetDistance - distance) > 1e-3
            || abs(targetShift - shift) > 1e-4 || abs(targetSpace - space) > 1e-4
    }

    var eye: SIMD3<Float> {
        let horizontal = cos(pitch)
        return Self.target + SIMD3(sin(yaw) * horizontal, sin(pitch), cos(yaw) * horizontal) * distance
    }

    var view: float4x4 {
        // Looking straight down, "up" on the screen points away from the player.
        let up = normalize(SIMD3(-sin(yaw) * sin(pitch), cos(pitch), -cos(yaw) * sin(pitch)))
        return Matrix.lookAt(eye: eye, target: Self.target, up: up)
    }

    func projection(aspect: Float) -> float4x4 {
        let widen = max(1, Self.minAspect / (aspect * space))
        var projection = Matrix.perspective(fovY: 2 * atan(tan(Self.fieldOfView / 2) * widen), aspect: aspect, near: 0.2, far: 120)
        projection.columns.2.x = -2 * shift // a shift in normalized coordinates, which span 2
        return projection
    }

    /// The ray through a point of the window, in pixels from the top left.
    func ray(x: Float, y: Float, width: Float, height: Float) -> (origin: SIMD3<Float>, direction: SIMD3<Float>) {
        let inverse = (projection(aspect: width / max(height, 1)) * view).inverse
        let nx = x / width * 2 - 1
        let ny = 1 - y / height * 2
        let nearPoint = Matrix.transform(SIMD3(nx, ny, 0), by: inverse)
        let farPoint = Matrix.transform(SIMD3(nx, ny, 1), by: inverse)
        return (nearPoint, normalize(farPoint - nearPoint))
    }

    /// The angle nearest to `current` that points the same way as `angle`.
    private static func unwrap(_ angle: Float, near current: Float) -> Float {
        var angle = angle
        while angle - current > Float.pi {
            angle -= 2 * Float.pi
        }
        while angle - current < -Float.pi {
            angle += 2 * Float.pi
        }
        return angle
    }
}
