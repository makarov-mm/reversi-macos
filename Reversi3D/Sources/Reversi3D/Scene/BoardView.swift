import Foundation
import simd

/// The discs as they lie and move: flying from the piles beside the board to their squares, turning over in a wave
/// that runs out from the disc placed, flying back when a move is taken back, and dissolving in when a game is set out.
struct BoardView {
    /// What happened in a frame, for the sounds.
    enum Event: Comparable {
        case place
        case flip
        case stack
    }

    private struct Disc {
        var square = -1 // on the board; -1 in a pile; -2 leaving
        var pile = -1 // in a pile, Black's (0) or White's (1); on the board, the pile it came from
        var level = 0 // its place in the pile, counted from the bottom
        var whiteUp = false // the face up when it lies still
        var yaw: Float = 0 // each disc turned its own way, so that the grain differs
        var seed: Float = 0
        var position = SIMD3<Float>(repeating: 0) // the middle of its underside
        // A flight from one place to another, in an arc.
        var from = SIMD3<Float>(repeating: 0)
        var to = SIMD3<Float>(repeating: 0)
        var flightTime: Float = 0
        var flightDuration: Float = 0
        var flightDelay: Float = 0
        var arc: Float = 0
        var flying = false
        var landing = Event.place
        // Turning over about a level axis, lifted off the board for the turn.
        var turnAxis = SIMD3<Float>(1, 0, 0)
        var turnTime: Float = 0
        var turnDuration: Float = 0
        var turnDelay: Float = 0
        var turnLift: Float = 0
        var turning = false
        var dissolve: Float = 0
        var dissolveTarget: Float = 0
        var dissolveDelay: Float = 0
        var removeWhenGone = false
        // Leaning in the preview of a move that would turn it.
        var leanAxis = SIMD3<Float>(1, 0, 0)
        var lean: Float = 0
        var leanTarget: Float = 0
    }

    private static let fadeTime: Float = 0.45
    private static let flightTime: Float = 0.55
    private static let turnTime: Float = 0.36
    private static let turnLift: Float = 0.42 // enough for a disc on its edge to clear the board
    private static let waveStep: Float = 0.075 // between the discs one square further from the one placed
    private static let stackHeight = 10 // discs in a stack beside the board
    private static let thickness = 2 * DiscModel.halfHeight

    private var discs: [Disc] = []
    private var pileCounts = [0, 0]
    private var seed: UInt32 = 1

    /// Sets out the game's position, and beside the board the discs not yet played.
    mutating func rebuild(_ game: GameRecord, animate: Bool) {
        if animate {
            for i in discs.indices {
                discs[i].dissolveTarget = 1
                discs[i].dissolveDelay = 0
                discs[i].removeWhenGone = true
                discs[i].square = -2
                discs[i].pile = -1
            }
        } else {
            discs.removeAll()
        }

        // The discs off the board at the start, shared out between the players, and then the pile each disc played
        // came from: a player whose own pile is used up takes from the other's.
        let start = game.start
        let total = Squares.count - (~start.empty).nonzeroBitCount
        pileCounts[0] = (total + (start.sideToMove == .black ? 1 : 0)) / 2
        pileCounts[1] = total - pileCounts[0]
        var origin = [Int](repeating: -1, count: Squares.count)
        for record in game.moves where !record.isPass {
            var pile = Self.pile(of: record.side)
            if pileCounts[pile] == 0 {
                pile = 1 - pile
            }
            pileCounts[pile] -= 1
            origin[record.square] = pile
        }

        let position = game.current
        for square in 0..<Squares.count {
            if let side = position.occupant(square) {
                let index = add(whiteUp: side == .white, at: BoardGeometry.squareCenter(square), appear: animate, delay: 0.3 + 0.01 * Float(square))
                discs[index].square = square
                discs[index].pile = origin[square]
            }
        }
        for pile in 0..<2 {
            for level in 0..<pileCounts[pile] {
                let index = add(whiteUp: pile == 1, at: Self.pilePosition(pile, level: level), appear: animate, delay: 0.5 + 0.012 * Float(level))
                discs[index].pile = pile
                discs[index].level = level
            }
        }
    }

    /// A move played (forward) or taken back.
    mutating func play(_ record: MoveRecord, forward: Bool) {
        if record.isPass {
            return
        }
        let center = BoardGeometry.squareCenter(record.square)
        let moverWhite = record.side == .white
        func distance(_ square: Square) -> Int {
            max(abs(Squares.file(square) - Squares.file(record.square)), abs(Squares.row(square) - Squares.row(record.square)))
        }

        if forward {
            // A disc from the player's pile, or the other's when that is used up, flies to the square.
            var pile = Self.pile(of: record.side)
            if pileCounts[pile] == 0 {
                pile = 1 - pile
            }
            var index = topOfPile(pile) ?? -1
            if index < 0 {
                index = add(whiteUp: moverWhite, at: Self.pilePosition(pile, level: 0), appear: false, delay: 0)
            }
            pileCounts[pile] = max(0, pileCounts[pile] - 1)
            discs[index].square = record.square
            discs[index].pile = pile
            Self.fly(&discs[index], to: center, duration: Self.flightTime, arc: 1.1, delay: 0, landing: .place)
            Self.turn(&discs[index], whiteUp: moverWhite, axis: Self.axisAway(from: discs[index].position, to: center),
                      duration: Self.flightTime * 0.8, lift: 0, delay: 0.05)

            // Then the discs it brackets turn over, the nearest first.
            for square in Self.squares(of: record.flipped) {
                if let turned = onSquare(square) {
                    let delay = Self.flightTime + Self.waveStep * Float(distance(square) - 1)
                    Self.turn(&discs[turned], whiteUp: moverWhite, axis: Self.axisAway(from: center, to: BoardGeometry.squareCenter(square)),
                              duration: Self.turnTime, lift: Self.turnLift, delay: delay)
                }
            }
            return
        }

        // Back: the turned discs turn back, the furthest first, and then the disc placed returns to its pile.
        let furthest = Self.squares(of: record.flipped).map(distance).max() ?? 0
        for square in Self.squares(of: record.flipped) {
            if let turned = onSquare(square) {
                let delay = Self.waveStep * Float(furthest - distance(square))
                Self.turn(&discs[turned], whiteUp: !moverWhite, axis: Self.axisAway(from: BoardGeometry.squareCenter(square), to: center),
                          duration: Self.turnTime, lift: Self.turnLift, delay: delay)
            }
        }
        if let index = onSquare(record.square) {
            let pile = discs[index].pile >= 0 ? discs[index].pile : Self.pile(of: record.side)
            discs[index].square = -1
            discs[index].pile = pile
            discs[index].level = pileCounts[pile]
            pileCounts[pile] += 1
            let place = Self.pilePosition(pile, level: discs[index].level)
            let delay = Self.waveStep * Float(furthest) + (record.flipped != 0 ? Self.turnTime * 0.6 : 0)
            Self.fly(&discs[index], to: place, duration: Self.flightTime, arc: 1.1, delay: delay, landing: .stack)
            Self.turn(&discs[index], whiteUp: pile == 1, axis: Self.axisAway(from: center, to: place), duration: Self.flightTime * 0.8, lift: 0,
                      delay: delay + 0.05)
        }
    }

    /// The discs that a disc placed on `square` would turn over lean away from it, about to go, and glow.
    mutating func preview(_ square: Square, turning: UInt64) {
        for i in discs.indices {
            let leaning = square >= 0 && discs[i].square >= 0 && turning & Squares.bit(discs[i].square) != 0
            discs[i].leanTarget = leaning ? 1 : 0
            if leaning {
                discs[i].leanAxis = Self.axisAway(from: BoardGeometry.squareCenter(square), to: BoardGeometry.squareCenter(discs[i].square))
            }
        }
    }

    /// Moves the animations on; what landed or turned over is added to `events`.
    mutating func update(_ seconds: Float, events: inout [Event]) {
        for i in discs.indices {
            discs[i].lean = Easing.approach(discs[i].lean, discs[i].leanTarget, step: seconds / 0.15)
            if discs[i].dissolveDelay > 0 {
                discs[i].dissolveDelay -= seconds
            } else {
                discs[i].dissolve = Easing.approach(discs[i].dissolve, discs[i].dissolveTarget, step: seconds / Self.fadeTime)
            }

            if discs[i].flying {
                if discs[i].flightDelay > 0 {
                    discs[i].flightDelay -= seconds
                } else {
                    discs[i].flightTime = min(discs[i].flightTime + seconds, discs[i].flightDuration)
                    let t = discs[i].flightTime / discs[i].flightDuration
                    let eased = Easing.smootherStep(t)
                    discs[i].position = discs[i].from + (discs[i].to - discs[i].from) * eased + SIMD3(0, discs[i].arc * sin(Float.pi * t), 0)
                    if t >= 1 {
                        discs[i].position = discs[i].to
                        discs[i].flying = false
                        events.append(discs[i].landing)
                    }
                }
            }

            if discs[i].turning {
                if discs[i].turnDelay > 0 {
                    discs[i].turnDelay -= seconds
                } else {
                    discs[i].turnTime += seconds
                    if discs[i].turnTime >= discs[i].turnDuration {
                        discs[i].whiteUp.toggle()
                        discs[i].turning = false
                        if discs[i].turnLift > 0 {
                            events.append(.flip)
                        }
                    }
                }
            }
        }
        discs.removeAll { $0.removeWhenGone && $0.dissolve >= 1 }
    }

    /// Nothing flying, turning or dissolving: the position shown is the game's.
    var isSettled: Bool {
        !discs.contains { $0.flying || $0.turning || $0.dissolve != $0.dissolveTarget }
    }

    var isAnimating: Bool {
        !isSettled || discs.contains { $0.lean != $0.leanTarget }
    }

    func draws(lastMove: Square, accent: SIMD3<Float>, time: Float) -> [DiscDraw] {
        discs.map { disc in
            var angle: Float = 0
            if disc.turning && disc.turnDelay <= 0 {
                angle = Float.pi * Easing.smootherStep(min(disc.turnTime / disc.turnDuration, 1))
            }
            let lean = Easing.smootherStep(disc.lean) * (0.85 + 0.15 * sin(time * 5))
            let face = disc.whiteUp ? Matrix.identity : Matrix.rotationX(Float.pi)
            let placed = Matrix.translation(disc.position + SIMD3(0, DiscModel.halfHeight + Self.lift(disc) + 0.09 * lean, 0))
            let leaned = Matrix.rotation(axis: disc.leanAxis, angle: 0.28 * lean)
            let turned = Matrix.rotation(axis: disc.turnAxis, angle: angle)
            var draw = DiscDraw()
            draw.model = placed * leaned * turned * face * Matrix.rotationY(disc.yaw)
            draw.ground = Self.ground(at: disc.position)
            draw.dissolve = disc.dissolve
            draw.seed = disc.seed
            draw.glowColor = accent
            draw.glow = 0.7 * lean
            if disc.square >= 0 && disc.square == lastMove && !disc.flying {
                draw.mark = 1
            }
            return draw
        }
    }

    func contacts() -> [ContactShadow] {
        discs.compactMap { disc in
            // In a stack only the lowest disc touches the table.
            if disc.square == -1 && !disc.flying && disc.level % Self.stackHeight != 0 {
                return nil
            }
            let height = disc.position.y - Self.ground(at: disc.position) + Self.lift(disc) + 0.09 * disc.lean
            let strength = 0.72 * (1 - Easing.smoothStep(0, 0.8, height)) * (1 - disc.dissolve)
            guard strength > 0.01 else { return nil }
            return ContactShadow(x: disc.position.x, z: disc.position.z, radius: DiscModel.radius * (1.05 + height * 0.6), strength: strength)
        }
    }

    // MARK: - Helpers

    private static func pile(of side: Side) -> Int { side == .black ? 0 : 1 }

    /// Each player's discs stand in stacks beside the board, on the player's right: Black's on the right of the
    /// default view, the stack nearest the player used first.
    private static func pilePosition(_ pile: Int, level: Int) -> SIMD3<Float> {
        let stack = (Float(level / stackHeight) - 1) * 1.05
        let y = BoardGeometry.tableHeight + Float(level % stackHeight) * thickness
        return pile == 0 ? SIMD3(5.35, y, stack) : SIMD3(-5.35, y, -stack)
    }

    private static func ground(at position: SIMD3<Float>) -> Float {
        abs(position.x) < BoardGeometry.frameOuter && abs(position.z) < BoardGeometry.frameOuter ? 0 : BoardGeometry.tableHeight
    }

    private static func lift(_ disc: Disc) -> Float {
        guard disc.turning && disc.turnDelay <= 0 else { return 0 }
        return disc.turnLift * sin(Float.pi * min(disc.turnTime / disc.turnDuration, 1))
    }

    /// The level axis a disc turns about to roll away from a point.
    private static func axisAway(from: SIMD3<Float>, to: SIMD3<Float>) -> SIMD3<Float> {
        var direction = to - from
        direction.y = 0
        guard length(direction) >= 1e-4 else { return SIMD3(1, 0, 0) }
        direction = normalize(direction)
        return SIMD3(direction.z, 0, -direction.x)
    }

    private static func squares(of bits: UInt64) -> [Square] {
        var squares: [Square] = []
        var remaining = bits
        while remaining != 0 {
            squares.append(remaining.trailingZeroBitCount)
            remaining &= remaining - 1
        }
        return squares
    }

    private static func fly(_ disc: inout Disc, to: SIMD3<Float>, duration: Float, arc: Float, delay: Float, landing: Event) {
        disc.from = disc.position
        disc.to = to
        disc.flightTime = 0
        disc.flightDuration = duration
        disc.flightDelay = delay
        disc.arc = arc
        disc.flying = true
        disc.landing = landing
    }

    /// Turns a disc to show a face, unless it shows it already or is about to.
    private static func turn(_ disc: inout Disc, whiteUp: Bool, axis: SIMD3<Float>, duration: Float, lift: Float, delay: Float) {
        let ending = disc.turning ? !disc.whiteUp : disc.whiteUp
        if ending == whiteUp {
            return
        }
        if disc.turning {
            disc.turning = false
            if disc.turnDelay > 0 {
                return // a turn not yet begun is simply called off
            }
            disc.whiteUp.toggle() // one under way is finished at once, and the disc turns back
        }
        disc.turning = true
        disc.turnAxis = axis
        disc.turnTime = 0
        disc.turnDuration = duration
        disc.turnDelay = delay
        disc.turnLift = lift
    }

    private mutating func random() -> Float {
        seed = seed &* 1_664_525 &+ 1_013_904_223
        return Float(seed >> 8) / Float(1 << 24)
    }

    /// A new disc, dissolving in after `delay` when it is to appear; returns its index.
    private mutating func add(whiteUp: Bool, at position: SIMD3<Float>, appear: Bool, delay: Float) -> Int {
        var disc = Disc()
        disc.whiteUp = whiteUp
        disc.position = position
        disc.yaw = random() * 2 * Float.pi
        disc.seed = random()
        if appear {
            disc.dissolve = 1
            disc.dissolveDelay = delay
        }
        discs.append(disc)
        return discs.count - 1
    }

    private func onSquare(_ square: Square) -> Int? {
        discs.firstIndex { $0.square == square }
    }

    private func topOfPile(_ pile: Int) -> Int? {
        discs.indices.filter { discs[$0].square == -1 && discs[$0].pile == pile }.max { discs[$0].level < discs[$1].level }
    }
}
