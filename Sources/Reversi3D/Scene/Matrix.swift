import Foundation
import simd

/// Transforms of column vectors, in a right-handed world with y up, and projections to Metal's clip space, whose depth
/// runs from 0 at the near plane to 1 at the far plane.
enum Matrix {
    static var identity: float4x4 {
        float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)))
    }

    static func translation(_ offset: SIMD3<Float>) -> float4x4 {
        float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(offset, 1)))
    }

    static func rotationX(_ angle: Float) -> float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return float4x4(columns: (SIMD4(1, 0, 0, 0), SIMD4(0, c, s, 0), SIMD4(0, -s, c, 0), SIMD4(0, 0, 0, 1)))
    }

    static func rotationY(_ angle: Float) -> float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        return float4x4(columns: (SIMD4(c, 0, -s, 0), SIMD4(0, 1, 0, 0), SIMD4(s, 0, c, 0), SIMD4(0, 0, 0, 1)))
    }

    /// About an axis of unit length, counterclockwise looking down it.
    static func rotation(axis: SIMD3<Float>, angle: Float) -> float4x4 {
        let c = cos(angle)
        let s = sin(angle)
        let t = 1 - c
        let x = axis.x
        let y = axis.y
        let z = axis.z
        return float4x4(columns: (
            SIMD4(c + t * x * x, t * x * y + s * z, t * x * z - s * y, 0),
            SIMD4(t * x * y - s * z, c + t * y * y, t * y * z + s * x, 0),
            SIMD4(t * x * z + s * y, t * y * z - s * x, c + t * z * z, 0),
            SIMD4(0, 0, 0, 1)))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> float4x4 {
        let forward = normalize(target - eye)
        let right = normalize(cross(forward, up))
        let trueUp = cross(right, forward)
        return float4x4(columns: (
            SIMD4(right.x, trueUp.x, -forward.x, 0),
            SIMD4(right.y, trueUp.y, -forward.y, 0),
            SIMD4(right.z, trueUp.z, -forward.z, 0),
            SIMD4(-dot(right, eye), -dot(trueUp, eye), dot(forward, eye), 1)))
    }

    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> float4x4 {
        let f = 1 / tan(fovY / 2)
        return float4x4(columns: (
            SIMD4(f / aspect, 0, 0, 0),
            SIMD4(0, f, 0, 0),
            SIMD4(0, 0, far / (near - far), -1),
            SIMD4(0, 0, near * far / (near - far), 0)))
    }

    static func orthographic(left: Float, right: Float, bottom: Float, top: Float, near: Float, far: Float) -> float4x4 {
        float4x4(columns: (
            SIMD4(2 / (right - left), 0, 0, 0),
            SIMD4(0, 2 / (top - bottom), 0, 0),
            SIMD4(0, 0, -1 / (far - near), 0),
            SIMD4(-(right + left) / (right - left), -(top + bottom) / (top - bottom), -near / (far - near), 1)))
    }

    /// A point carried through a projective transform.
    static func transform(_ point: SIMD3<Float>, by matrix: float4x4) -> SIMD3<Float> {
        let v = matrix * SIMD4(point, 1)
        return SIMD3(v.x, v.y, v.z) / v.w
    }
}
