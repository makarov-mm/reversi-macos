/// The panel beside the board: the side to move, the score, the moves, the buttons and the settings.
extension GameController {
    /// The widgets, by the ids that tell which one the pointer pressed.
    enum Widget {
        static let help = 1
        static let undo = 2
        static let redo = 3
        static let hint = 4
        static let newGame = 5
        static let flip = 6
        static let mode = 7 // a selector takes two ids, one for each arrow
        static let level = 9
        static let moves = 11
        static let theme = 13
        static let sound = 15
        static let language = 16
        static let about = 17
        static let modal = 100 // the widgets of the cards over the game come after this
        static let helpClose = 101
        static let aboutClose = 102
        static let aboutLinks = 110
    }

    var panelRect: ScreenRect {
        let width = Self.panelWidth * scale
        let margin = Self.panelMargin * scale
        return ScreenRect(x: Float(self.width) - (width + margin) * panelSlide, y: margin, width: width, height: Float(height) - 2 * margin)
    }

    /// The part of the window not under the panel.
    var freeArea: ScreenRect {
        ScreenRect(x: 0, y: 0, width: min(panelRect.x, Float(width)), height: Float(height))
    }

    func drawInterface() {
        drawPanel()
        drawBanner()
        drawToasts()
        switch dialog {
        case .help: drawHelp()
        case .about: drawAbout()
        case .none: break
        }
    }

    // MARK: - Widgets

    /// Hovering, pressing and clicking; a click sounds.
    func interact(_ id: Int, _ rect: ScreenRect, enabled: Bool) -> Interaction {
        // While a card is open, only its own widgets answer, from the frame after the one that opened it.
        let interactive = enabled && (dialog == .none || (id > Widget.modal && !dialogOpening))
        var result = Interaction()
        result.hover = interactive && rect.contains(pointer.x, pointer.y)
        if result.hover {
            cursorHand = true
        }
        if result.hover && pointer.leftPressed {
            activeWidget = id
            pointer.consumed = true
        }
        if pointer.leftReleased && activeWidget == id {
            result.clicked = result.hover
            activeWidget = 0
            pointer.consumed = true
        }
        result.pressed = result.hover && activeWidget == id && pointer.leftDown
        if result.clicked {
            sound.play(.click)
        }
        return result
    }

    @discardableResult
    func button(_ id: Int, _ rect: ScreenRect, _ label: String, enabled: Bool = true, accent: Bool = false) -> Bool {
        let state = interact(id, rect, enabled: enabled)
        var fill = !enabled ? RGBA(255, 255, 255, 7) : state.pressed ? RGBA(255, 255, 255, 52) : state.hover ? RGBA(255, 255, 255, 34) : RGBA(255, 255, 255, 17)
        if accent && enabled {
            fill = fill.mixed(with: RGBA(linear: theme.accent, alpha: Float(fill.a) / 255 * 2.2), 0.6)
        }
        painter.fill(rect, radius: 9 * scale, color: fill)
        painter.textCentered(.body, in: rect, label, color: enabled ? Self.textColor : Self.textColor.faded(0.35))
        return state.clicked
    }

    /// A label with a value stepped by two arrows, past the width of the longest label of the column; returns -1 or 1
    /// when an arrow is clicked, else 0.
    func selector(_ id: Int, _ rect: ScreenRect, label: String, value: String, labelWidth: Float) -> Int {
        painter.text(.body, x: rect.x, y: rect.y + (rect.height - painter.lineHeight(.body)) / 2, label, color: Self.mutedColor)
        let arrow = rect.height
        let right = ScreenRect(x: rect.right - arrow, y: rect.y, width: arrow, height: rect.height)
        // The value from 42% of the row, or further where a label is longer: fonts differ in width.
        let left = ScreenRect(x: max(rect.x + rect.width * 0.42 - arrow - 4 * scale, rect.x + labelWidth + 8 * scale), y: rect.y, width: arrow,
                              height: rect.height)
        painter.fill(ScreenRect(x: left.right + 2 * scale, y: rect.y, width: right.x - left.right - 4 * scale, height: rect.height), radius: 9 * scale,
                     color: RGBA(255, 255, 255, 9))
        painter.textCentered(.body, in: ScreenRect(x: left.right, y: rect.y, width: right.x - left.right, height: rect.height), value, color: Self.textColor)
        var change = 0
        if button(id, left, "") {
            change = -1
        }
        if button(id + 1, right, "") {
            change = 1
        }
        let size = 5 * scale
        painter.arrow(x: left.x + left.width / 2, y: left.y + left.height / 2, halfWidth: size * 0.8, halfHeight: size, direction: -1, color: Self.textColor)
        painter.arrow(x: right.x + right.width / 2, y: right.y + right.height / 2, halfWidth: size * 0.8, halfHeight: size, direction: 1, color: Self.textColor)
        return change
    }

    /// A little disc for the panel, with a rim and a gleam.
    func drawDisc(x: Float, y: Float, radius: Float, side: Side) {
        painter.disc(x: x, y: y, radius: radius, color: RGBA(120, 125, 140))
        painter.disc(x: x, y: y, radius: radius - max(1, radius * 0.1), color: side == .black ? RGBA(22, 22, 26) : RGBA(238, 236, 230))
        painter.disc(x: x - radius * 0.28, y: y - radius * 0.3, radius: radius * 0.38, color: RGBA(255, 255, 255, side == .black ? 46 : 120))
    }

    func playerName(_ side: Side) -> String {
        if mode == .twoPlayers {
            return text(.player)
        }
        if isHuman(side) {
            return text(.you)
        }
        return "\(text(.computer)) · \(text(Str.levelName(level)))"
    }

    func resultTitle(_ result: GameStatus.Result) -> Str {
        result == .blackWins ? .blackWins : result == .whiteWins ? .whiteWins : .draw
    }

    /// The discs at the end, and why it ended.
    func resultDetail(_ status: GameStatus) -> String {
        let full = status.black + status.white == Squares.count
        return "\(status.black) : \(status.white)  ·  \(text(full ? .boardFull : .noMovesLeft))"
    }

    // MARK: - The panel

    func drawPanel() {
        guard panelSlide > 0.001 else { return }
        let panel = panelRect
        if panel.contains(pointer.x, pointer.y) && (pointer.leftPressed || pointer.rightPressed) {
            pointer.consumed = true
        }
        painter.shadow(panel, blur: 22 * scale, color: RGBA(0, 0, 0, 70))
        painter.fill(panel, radius: 18 * scale, color: RGBA(16, 18, 26, 120))
        painter.outline(panel, radius: 18 * scale, color: RGBA(255, 255, 255, 24))

        let pad = 20 * scale
        let x = panel.x + pad
        let width = panel.width - 2 * pad
        var y = panel.y + pad

        painter.text(.heading, x: x, y: y, text(.title), color: Self.textColor)
        let small = 30 * scale
        if button(Widget.help, ScreenRect(x: panel.right - pad - small, y: y - 2 * scale, width: small, height: small), "?") {
            toggleDialog(.help)
        }
        if button(Widget.about, ScreenRect(x: panel.right - pad - 2 * small - 6 * scale, y: y - 2 * scale, width: small, height: small), "i") {
            toggleDialog(.about)
        }
        y += 44 * scale

        drawStatus(ScreenRect(x: x, y: y, width: width, height: 62 * scale))
        y += 62 * scale + 12 * scale
        drawScore(ScreenRect(x: x, y: y, width: width, height: 68 * scale))
        y += 68 * scale + 14 * scale

        // From the bottom up: the footer, the settings and the buttons; the moves take the space between.
        var bottom = panel.bottom - pad
        let footerHeight = painter.lineHeight(.body)
        painter.textCentered(.body, in: ScreenRect(x: x, y: bottom - footerHeight, width: width, height: footerHeight), text(.footer),
                             color: Self.mutedColor.faded(0.8))
        bottom -= footerHeight + 14 * scale

        let rowHeight = 34 * scale
        let gap = 8 * scale
        let half = (width - gap) / 2
        bottom -= rowHeight
        if button(Widget.sound, ScreenRect(x: x, y: bottom, width: half, height: rowHeight),
                  "\(text(.sound)): \(text(sound.isEnabled ? .on : .off))") {
            toggleSound()
        }
        if button(Widget.language, ScreenRect(x: x + half + gap, y: bottom, width: half, height: rowHeight), text(.languageName)) {
            toggleLanguage()
        }
        bottom -= gap

        let modes: [Str] = [.modeBlack, .modeWhite, .modeTwoPlayers, .modeDemo]
        let choices: [(id: Int, label: Str, value: String)] = [
            (Widget.theme, .theme, theme.name(in: language)),
            (Widget.moves, .showMoves, text(showMoves ? .on : .off)),
            (Widget.level, .level, "\(level) · \(text(Str.levelName(level)))"),
            (Widget.mode, .mode, text(modes[mode.rawValue])),
        ]
        let labelWidth = choices.map { painter.measure(.body, text($0.label)) }.max() ?? 0
        for choice in choices {
            bottom -= rowHeight
            let change = selector(choice.id, ScreenRect(x: x, y: bottom, width: width, height: rowHeight), label: text(choice.label), value: choice.value,
                                  labelWidth: labelWidth)
            if change != 0 {
                switch choice.id {
                case Widget.theme: setTheme(themeIndex + change)
                case Widget.moves: toggleShowMoves()
                case Widget.level: setLevel(level + change)
                default: setMode(mode.rawValue + change)
                }
            }
            bottom -= 6 * scale
        }
        bottom -= 8 * scale

        let buttonHeight = 38 * scale
        bottom -= buttonHeight
        if button(Widget.newGame, ScreenRect(x: x, y: bottom, width: half, height: buttonHeight), text(.newGame)) {
            newGame()
        }
        if button(Widget.flip, ScreenRect(x: x + half + gap, y: bottom, width: half, height: buttonHeight), text(.flip)) {
            camera.flip()
        }
        bottom -= gap + buttonHeight
        let third = (width - 2 * gap) / 3
        if button(Widget.undo, ScreenRect(x: x, y: bottom, width: third, height: buttonHeight), text(.undo), enabled: game.canUndo) {
            undo()
        }
        if button(Widget.redo, ScreenRect(x: x + third + gap, y: bottom, width: third, height: buttonHeight), text(.redo), enabled: game.canRedo) {
            redo()
        }
        if button(Widget.hint, ScreenRect(x: x + 2 * (third + gap), y: bottom, width: third, height: buttonHeight), text(.hint),
                  enabled: humanToMove && !hintThinking, accent: true) {
            requestHint()
        }
        bottom -= 16 * scale

        // The moves, with their heading, where there is room for them.
        let listTop = y + painter.lineHeight(.body) + 6 * scale
        if bottom - listTop > 40 * scale {
            painter.text(.body, x: x, y: y, text(.moves), color: Self.mutedColor)
            drawMoveList(ScreenRect(x: x, y: listTop, width: width, height: bottom - listTop))
        }
    }

    /// A disc of the side to move, or of the winner, and what is going on.
    func drawStatus(_ area: ScreenRect) {
        let status = game.status
        let side = game.current.sideToMove
        let accent = RGBA(linear: theme.accent)
        painter.fill(area, radius: 12 * scale, color: RGBA(255, 255, 255, 14))

        let shown: Side = status.result == .whiteWins ? .white : status.result == .blackWins ? .black : side
        drawDisc(x: area.x + 22 * scale, y: area.y + area.height / 2, radius: 10 * scale, side: shown)

        let title: String
        let detail: String
        var titleColor = Self.textColor
        if status.isOver {
            title = text(resultTitle(status.result))
            detail = resultDetail(status)
            titleColor = accent
        } else {
            title = text(side == .black ? .blackToMove : .whiteToMove)
            detail = computerThinking || computerResult != nil ? text(.thinking) : playerName(side)
        }
        let textX = area.x + 44 * scale
        let lineHeight = painter.lineHeight(.heading)
        painter.text(.heading, x: textX, y: area.y + area.height / 2 - lineHeight + 3 * scale, title, color: titleColor)
        painter.text(.body, x: textX, y: area.y + area.height / 2 + 2 * scale, detail, color: Self.mutedColor)
        if computerThinking || computerResult != nil || hintThinking {
            painter.spinner(x: area.right - 22 * scale, y: area.y + area.height / 2, radius: 8 * scale, thickness: 2.2 * scale, angle: time * 5,
                            color: accent)
        }
    }

    /// The players with their discs, and a bar shared out between the colors.
    func drawScore(_ area: ScreenRect) {
        let status = game.status
        let rowHeight = 28 * scale
        var y = area.y
        for side in [Side.black, Side.white] {
            let textY = y + (rowHeight - painter.lineHeight(.body)) / 2
            let toMove = !status.isOver && game.current.sideToMove == side
            let count = String(side == .black ? status.black : status.white)
            let countWidth = painter.measure(.heading, count)
            let nameX = area.x + 26 * scale
            let name = "\(text(side == .black ? .black : .white))  ·  \(playerName(side))"
            drawDisc(x: area.x + 9 * scale, y: y + rowHeight / 2, radius: 7 * scale, side: side)
            painter.text(.body, x: nameX, y: textY, painter.elided(.body, name, width: area.right - countWidth - 8 * scale - nameX),
                         color: toMove ? Self.textColor : Self.textColor.faded(0.75))
            painter.text(.heading, x: area.right - countWidth, y: y + (rowHeight - painter.lineHeight(.heading)) / 2, count, color: Self.textColor)
            y += rowHeight
        }
        y += 6 * scale
        let bar = ScreenRect(x: area.x, y: y, width: area.width, height: 6 * scale)
        let share = Float(status.black) / Float(max(1, status.black + status.white))
        painter.fill(bar, radius: 3 * scale, color: RGBA(238, 236, 230, 220))
        painter.fill(ScreenRect(x: bar.x, y: bar.y, width: max(bar.height, bar.width * share), height: bar.height), radius: 3 * scale,
                     color: RGBA(10, 10, 12, 235))
        painter.fill(ScreenRect(x: bar.x + bar.width / 2 - 0.5 * scale, y: bar.y - 2 * scale, width: 1 * scale, height: bar.height + 4 * scale), radius: 0,
                     color: RGBA(255, 255, 255, 90))
    }

    /// The moves in pairs, Black's first, each with how many discs it turned; the last one marked. The list follows
    /// the game unless scrolled back.
    func drawMoveList(_ area: ScreenRect) {
        painter.fill(area, radius: 12 * scale, color: RGBA(0, 0, 0, 40))
        let moves = game.moves
        if moves.isEmpty {
            painter.textCentered(.body, in: area, text(.noMovesYet), color: Self.mutedColor)
            return
        }

        let rowHeight = (25 * scale).rounded()
        let inner = area.inset(by: 8 * scale)
        let visible = max(1, Int(inner.height / rowHeight))
        // Each row starts with Black's move.
        let offset = game.start.sideToMove == .white ? 1 : 0
        let rows = (moves.count + offset + 1) / 2
        let maxScroll = Float(max(0, rows - visible))

        if area.contains(pointer.x, pointer.y) && pointer.scroll != 0 && dialog == .none {
            moveScroll = min(max(moveScroll - pointer.scroll * 3, 0), maxScroll)
            followMoves = moveScroll >= maxScroll
            pointer.scroll = 0
            pointer.zoom = 0
        }
        if followMoves {
            moveScroll = maxScroll
        }
        moveScroll = min(max(moveScroll, 0), maxScroll)

        let first = Int(moveScroll)
        let numberWidth = 40 * scale
        let columnWidth = (inner.width - numberWidth) / 2
        let accent = RGBA(linear: theme.accent)
        for row in first..<min(rows, first + visible) {
            let y = inner.y + Float(row - first) * rowHeight
            let number = "\(row + 1)."
            painter.text(.body, x: inner.x + numberWidth - 10 * scale - painter.measure(.body, number), y: y + 3 * scale, number, color: Self.mutedColor)
            for column in 0..<2 {
                let ply = row * 2 + column - offset
                guard moves.indices.contains(ply) else { continue }
                let x = inner.x + numberWidth + Float(column) * columnWidth
                if ply == moves.count - 1 {
                    painter.fill(ScreenRect(x: x - 6 * scale, y: y + 1 * scale, width: columnWidth - 6 * scale, height: rowHeight - 2 * scale), radius: 7 * scale,
                                 color: accent.faded(0.28))
                }
                let record = moves[ply]
                if record.isPass {
                    painter.text(.body, x: x, y: y + 3 * scale, text(.pass), color: Self.mutedColor)
                } else {
                    // The square, and how many discs it turned.
                    let squareWidth = painter.text(.body, x: x, y: y + 3 * scale, Squares.name(record.square), color: Self.textColor)
                    painter.text(.body, x: x + squareWidth + 8 * scale, y: y + 3 * scale, "+\(record.flipped.nonzeroBitCount)",
                                 color: Self.mutedColor.faded(0.75))
                }
            }
        }
        if maxScroll > 0 {
            // A thin scroll bar.
            let barHeight = inner.height * Float(visible) / Float(rows)
            let barY = inner.y + (inner.height - barHeight) * (moveScroll / maxScroll)
            painter.fill(ScreenRect(x: area.right - 5 * scale, y: barY, width: 3 * scale, height: barHeight), radius: 1.5 * scale, color: RGBA(255, 255, 255, 50))
        }
    }
}
