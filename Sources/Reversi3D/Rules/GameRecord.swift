/// A game: the starting position, the moves played, and the moves taken back that can be replayed. A side left
/// without a move passes at once; the pass is kept as a move of its own.
struct GameRecord: Sendable {
    private(set) var moves: [MoveRecord] = []
    private(set) var status = GameStatus()
    private var positions: [Position] = []
    private var redoMoves: [MoveRecord] = [] // the next to replay at the end

    init(start: Position = .start) {
        reset(start)
    }

    mutating func reset(_ start: Position) {
        positions = [start.mustPass ? start.after(Squares.pass) : start]
        moves = []
        redoMoves = []
        updateStatus()
    }

    var current: Position { positions[positions.count - 1] }
    var start: Position { positions[0] }
    var ply: Int { moves.count }
    var canUndo: Bool { !moves.isEmpty }
    var canRedo: Bool { !redoMoves.isEmpty }

    /// Places a disc on a legal square; a pass that it forces on the other side follows.
    @discardableResult
    mutating func play(_ square: Square) -> Bool {
        guard !status.isOver, current.isLegal(square) else { return false }
        push(square)
        if current.mustPass {
            push(Squares.pass)
        }
        redoMoves.removeAll()
        updateStatus()
        return true
    }

    /// Takes back the last disc placed, with the pass after it.
    @discardableResult
    mutating func undo() -> Bool {
        guard !moves.isEmpty else { return false }
        repeat {
            redoMoves.append(moves.removeLast())
            positions.removeLast()
        } while redoMoves[redoMoves.count - 1].isPass && !moves.isEmpty
        updateStatus()
        return true
    }

    /// Replays the disc taken back last, with the pass that came after it.
    @discardableResult
    mutating func redo() -> Bool {
        guard !redoMoves.isEmpty else { return false }
        repeat {
            push(redoMoves.removeLast().square)
        } while !redoMoves.isEmpty && redoMoves[redoMoves.count - 1].isPass
        updateStatus()
        return true
    }

    /// The moves as Othello transcripts are written, without the passes: "f5d6c3d3".
    var transcript: String {
        moves.filter { !$0.isPass }.map { Squares.name($0.square) }.joined()
    }

    /// For the clipboard: the transcript, after the starting position when it is not the usual one.
    var text: String {
        start == .start ? transcript : start.text + "\n" + transcript
    }

    /// The starting position and the moves, for saving.
    var serialized: String { start.text + "|" + transcript }

    static func deserialize(_ text: String) -> GameRecord? {
        guard let bar = text.firstIndex(of: "|"), let start = Position.parse(text[..<bar]) else { return nil }
        return parse(start.text + " " + String(text[text.index(after: bar)...]))
    }

    /// A transcript ("f5d6c3d3"), a position, or a position and then a transcript.
    static func parse(_ text: String) -> GameRecord? {
        var game = GameRecord()
        let bytes = Array(text.utf8)

        // A board first, if the text begins with 64 squares.
        var begin = 0
        while begin < bytes.count, Notation.isSpace(bytes[begin]) {
            begin += 1
        }
        var squares = 0
        var end = begin
        while end < bytes.count, squares < Squares.count {
            if !Notation.isSpace(bytes[end]) {
                guard Notation.isBoardMark(bytes[end]) else { break }
                squares += 1
            }
            end += 1
        }
        var rest = bytes[...]
        var hasPosition = false
        if squares == Squares.count {
            // The side to move may follow, unless it is the letter of a move such as b3.
            while end < bytes.count, Notation.isSpace(bytes[end]) {
                end += 1
            }
            var sideEnd = end
            if sideEnd < bytes.count, Notation.isSideMark(bytes[sideEnd]),
               sideEnd + 1 >= bytes.count || !Notation.isDigit(bytes[sideEnd + 1]) {
                sideEnd += 1
            }
            guard let position = Position.parse(String(decoding: bytes[begin..<sideEnd], as: UTF8.self)) else { return nil }
            game.reset(position)
            rest = bytes[sideEnd...]
            hasPosition = true
        }

        // Then the moves: every letter a-h followed by a digit 1-8; passes are left out or skipped.
        var count = 0
        var i = rest.startIndex
        while i + 1 < rest.endIndex {
            let letter = rest[i] | 0x20
            let digit = rest[i + 1]
            // Part of a longer word, such as a name, is not a move.
            let partOfWord = i > rest.startIndex && Notation.isLetter(rest[i - 1])
            if (UInt8(ascii: "a")...UInt8(ascii: "h")).contains(letter), (UInt8(ascii: "1")...UInt8(ascii: "8")).contains(digit), !partOfWord {
                count += 1
                let square = Squares.at(file: Int(letter - UInt8(ascii: "a")), row: Int(digit - UInt8(ascii: "1")))
                guard game.play(square) else { return nil }
                i += 1
            }
            i += 1
        }
        if count == 0 && !hasPosition {
            return nil
        }
        return game
    }

    private mutating func push(_ square: Square) {
        let position = current
        moves.append(MoveRecord(square: square, side: position.sideToMove, flipped: square >= 0 ? position.flips(square) : 0))
        positions.append(position.after(square))
    }

    private mutating func updateStatus() {
        let position = current
        status.black = position.count(.black)
        status.white = position.count(.white)
        if !position.isOver {
            status.result = .ongoing
        } else if status.black != status.white {
            status.result = status.black > status.white ? .blackWins : .whiteWins
        } else {
            status.result = .draw
        }
    }
}
