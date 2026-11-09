import Foundation
import simd

/// The discs: two halves turned on a lathe, white on one face and black on the other, meeting in a fine groove round
/// the edge. The disc's middle is the origin; the white face looks up the y axis. A square of the board is 1 wide.
enum DiscModel {
    static let radius: Float = 0.42
    static let halfHeight: Float = 0.06

    /// The meshes of a disc.
    struct Shapes {
        /// The halves, for the scene.
        var white: Mesh<DiscVertex>
        var black: Mesh<DiscVertex>
        /// Plainer halves, for the reflections.
        var simpleWhite: Mesh<DiscVertex>
        var simpleBlack: Mesh<DiscVertex>
        /// The whole plain disc, for the shadows.
        var simple: Mesh<DiscVertex>
    }

    static func build() -> Shapes {
        let detailed = profile(detailed: true)
        let simple = profile(detailed: false)
        let simpleWhite = lathe(simple, segments: 32, mirrored: false)
        let simpleBlack = lathe(simple, segments: 32, mirrored: true)
        return Shapes(white: lathe(detailed, segments: 96, mirrored: false), black: lathe(detailed, segments: 96, mirrored: true),
                      simpleWhite: simpleWhite, simpleBlack: simpleBlack, simple: merge(simpleWhite, simpleBlack))
    }

    // MARK: - The outline

    private struct ProfilePoint {
        var r: Float
        var y: Float
        var occlusion: Float = 1
    }

    private static let seamRadius: Float = 0.012 // the rounded edge at the seam, where the halves meet
    private static let edgeRadius: Float = 0.022 // the rounded edge of the face
    private static let faceEdge = radius - edgeRadius
    private static let ring: Float = 0.335 // a fine groove round the face

    /// A smooth dip of width 2 * halfWidth: 1 in the middle, 0 at the edges.
    private static func bump(_ x: Float, center: Float, halfWidth: Float) -> Float {
        let t = (x - center) / halfWidth
        return abs(t) < 1 ? (1 - t * t) * (1 - t * t) : 0
    }

    /// The face: very slightly domed, with the groove near its edge.
    private static func faceHeight(_ r: Float) -> Float {
        halfHeight + 0.003 * (1 - (r / faceEdge) * (r / faceEdge)) - 0.0022 * bump(r, center: ring, halfWidth: 0.006)
    }

    private static func faceOcclusion(_ r: Float) -> Float { 1 - 0.35 * bump(r, center: ring, halfWidth: 0.008) }

    /// The outline of the white half, from the seam round the edge and over the face to its middle. The face is nearly
    /// flat: its points crowd round the groove and thin out towards the middle.
    private static func profile(detailed: Bool) -> [ProfilePoint] {
        var points: [ProfilePoint] = []

        // The rounded edge at the seam, darker deep in the groove.
        let seam = detailed ? 5 : 2
        for i in 0..<seam {
            let t = Float(i) / Float(seam)
            let angle = -Float.pi / 2 + Float.pi / 2 * t
            points.append(ProfilePoint(r: radius - seamRadius + seamRadius * cos(angle), y: seamRadius + seamRadius * sin(angle), occlusion: 0.45 + 0.55 * t))
        }
        // The straight side.
        points.append(ProfilePoint(r: radius, y: seamRadius))

        // The edge of the face.
        let edge = detailed ? 8 : 3
        for i in 0..<edge {
            let angle = Float.pi / 2 * Float(i) / Float(edge)
            points.append(ProfilePoint(r: faceEdge + edgeRadius * cos(angle), y: halfHeight - edgeRadius + edgeRadius * sin(angle)))
        }

        // The face, inwards.
        var radii: [Float]
        if detailed {
            radii = [faceEdge, 0.385, 0.37, 0.355]
            radii += (-4...4).map { ring + 0.003 * Float(-$0) }
            radii += [0.31, 0.28, 0.24, 0.19, 0.13, 0.07, 0.0]
        } else {
            radii = [faceEdge, 0.25, 0.0]
        }
        for r in radii {
            points.append(ProfilePoint(r: r, y: faceHeight(r), occlusion: detailed ? faceOcclusion(r) : 1))
        }
        return points
    }

    // MARK: - The lathe

    /// The profile turned round the y axis; `mirrored` turns it upside down, for the black half. Normals come from the
    /// neighbouring points of the outline.
    private static func lathe(_ profile: [ProfilePoint], segments: Int, mirrored: Bool) -> Mesh<DiscVertex> {
        let count = profile.count
        var normals = (0..<count).map { i -> SIMD2<Float> in
            let before = profile[max(i - 1, 0)]
            let after = profile[min(i + 1, count - 1)]
            let tangent = SIMD2(after.r - before.r, after.y - before.y)
            let size = length(tangent)
            return size > 0 ? SIMD2(tangent.y / size, -tangent.x / size) : SIMD2(0, 1)
        }
        normals[0] = SIMD2(0, -1) // the seam faces the other half
        normals[count - 1] = SIMD2(0, 1) // the middle of the face
        let sign: Float = mirrored ? -1 : 1

        var mesh = Mesh<DiscVertex>()
        for (point, n) in zip(profile, normals) {
            for j in 0...segments {
                let angle = 2 * Float.pi * Float(j) / Float(segments)
                let c = cos(angle)
                let s = sin(angle)
                mesh.vertices.append(DiscVertex(SIMD3(point.r * c, sign * point.y, point.r * s), normalize(SIMD3(n.x * c, sign * n.y, n.x * s)),
                                                occlusion: point.occlusion))
            }
        }

        func index(_ i: Int, _ j: Int) -> UInt32 { UInt32(i * (segments + 1) + j) }
        func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32) {
            // Mirroring turns the winding round; it is turned back so that the outside stays the front.
            mesh.indices += mirrored ? [a, c, b] : [a, b, c]
        }
        for i in 0..<(count - 1) {
            for j in 0..<segments {
                // Next to the axis a quad narrows to a triangle.
                if profile[i].r > 0 {
                    triangle(index(i, j), index(i + 1, j + 1), index(i, j + 1))
                }
                if profile[i + 1].r > 0 {
                    triangle(index(i, j), index(i + 1, j), index(i + 1, j + 1))
                }
            }
        }
        return mesh
    }

    private static func merge(_ a: Mesh<DiscVertex>, _ b: Mesh<DiscVertex>) -> Mesh<DiscVertex> {
        var mesh = a
        let offset = UInt32(a.vertices.count)
        mesh.vertices += b.vertices
        mesh.indices += b.indices.map { $0 + offset }
        return mesh
    }
}
