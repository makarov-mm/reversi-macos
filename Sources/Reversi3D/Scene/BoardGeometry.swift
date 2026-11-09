import Foundation
import simd

/// The board, its frame and the table. A square is one unit; the playing surface is the plane y = 0. Row 1 is at the
/// far side seen from the default view, from +z, as at the top of a printed board: a1 is the far left corner.
enum BoardGeometry {
    static let frameInner: Float = 4.0
    static let frameOuter: Float = 4.62
    static let frameTop: Float = 0.03
    static let tableHeight: Float = -0.32

    static func squareCenter(_ square: Square) -> SIMD3<Float> {
        SIMD3(Float(Squares.file(square)) - 3.5, 0, Float(Squares.row(square)) - 3.5)
    }

    /// The square under a point of the playing surface, or -1.
    static func square(at point: SIMD3<Float>) -> Square {
        // Far away, or nowhere at all when the ray runs along the board.
        guard abs(point.x) < 100, abs(point.z) < 100 else { return -1 }
        return Squares.at(file: Int((point.x + 4).rounded(.down)), row: Int((point.z + 4).rounded(.down)))
    }

    static func squares() -> Mesh<SurfaceVertex> {
        var mesh = Mesh<SurfaceVertex>()
        let up = SIMD3<Float>(0, 1, 0)
        addQuad(&mesh, SurfaceVertex([-4, 0, 4], up, [0, 0]), SurfaceVertex([4, 0, 4], up, [1, 0]),
                SurfaceVertex([4, 0, -4], up, [1, 1]), SurfaceVertex([-4, 0, -4], up, [0, 1]))
        return mesh
    }

    /// The frame's cross-section, swept round the board with mitred corners: a rounded inner edge rising from the
    /// squares, a flat top with an eased outer edge, and the side down to the table. The inner edge is a quarter
    /// circle rather than a step, so that it does not shrink to a flickering sliver when seen from afar.
    static func frame() -> Mesh<SurfaceVertex> {
        // Outward from the playing area's edge and height, and the normal in those two directions.
        let profile: [(out: Float, y: Float, normalOut: Float, normalY: Float)] = [
            (0.000, -0.002, -1, 0),
            (0.000, 0.000, -1, 0),
            (0.0023, 0.0115, -0.924, 0.383),
            (0.0088, 0.0212, -0.707, 0.707),
            (0.0185, 0.0277, -0.383, 0.924),
            (0.030, frameTop, 0, 1),
            (0.585, frameTop, 0, 1),
            (0.607, 0.022, 0.62, 0.78),
            (0.618, 0.006, 0.96, 0.28),
            (0.62, -0.012, 1, 0),
            (0.62, tableHeight, 1, 0),
        ]
        let outward: [SIMD3<Float>] = [[0, 0, 1], [1, 0, 0], [0, 0, -1], [-1, 0, 0]]
        var mesh = Mesh<SurfaceVertex>()
        for o in outward {
            let along = SIMD3<Float>(-o.z, 0, o.x)
            for (p, q) in zip(profile, profile.dropFirst()) where p.out != q.out || p.y != q.y {
                let pExtent = frameInner + p.out
                let qExtent = frameInner + q.out
                func vertex(_ point: (out: Float, y: Float, normalOut: Float, normalY: Float), _ extent: Float, _ s: Float) -> SurfaceVertex {
                    SurfaceVertex(o * extent + along * s + SIMD3(0, point.y, 0), normalize(o * point.normalOut + SIMD3(0, point.normalY, 0)), SIMD2(s, point.out))
                }
                addQuad(&mesh, vertex(p, pExtent, -pExtent), vertex(p, pExtent, pExtent), vertex(q, qExtent, qExtent), vertex(q, qExtent, -qExtent))
            }
        }
        return mesh
    }

    /// A round table under the board.
    static func table(radius: Float) -> Mesh<SurfaceVertex> {
        let segments = 96
        let up = SIMD3<Float>(0, 1, 0)
        var mesh = Mesh<SurfaceVertex>()
        mesh.vertices.append(SurfaceVertex([0, tableHeight, 0], up, [0.5, 0.5]))
        for i in 0..<segments {
            let angle = 2 * Float.pi * Float(i) / Float(segments)
            let x = cos(angle) * radius
            let z = sin(angle) * radius
            mesh.vertices.append(SurfaceVertex([x, tableHeight, z], up, [x / radius * 0.5 + 0.5, z / radius * 0.5 + 0.5]))
        }
        for i in 0..<UInt32(segments) {
            // Counterclockwise from above: from +x toward -z.
            mesh.indices += [0, 1 + (i + 1) % UInt32(segments), 1 + i]
        }
        return mesh
    }

    /// Adds a quad, wound counterclockwise as seen from the side its normal faces.
    private static func addQuad(_ mesh: inout Mesh<SurfaceVertex>, _ a: SurfaceVertex, _ b: SurfaceVertex, _ c: SurfaceVertex, _ d: SurfaceVertex) {
        let base = UInt32(mesh.vertices.count)
        mesh.vertices += [a, b, c, d]
        let facing = cross(b.position - a.position, c.position - a.position)
        let normal = a.normal + b.normal + c.normal + d.normal
        if dot(facing, normal) >= 0 {
            mesh.indices += [base, base + 1, base + 2, base, base + 2, base + 3]
        } else {
            mesh.indices += [base, base + 2, base + 1, base, base + 3, base + 2]
        }
    }
}
