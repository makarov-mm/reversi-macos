import Foundation

/// The cards over the game: the banner at the end, the toasts, the help and the about card.
extension GameController {
    static let helpLineCount = 21
    static let helpWidth: Float = 680
    static let helpRow: Float = 27
    static let helpPad: Float = 28
    static let aboutWidth: Float = 520
    static let aboutPad: Float = 28
    static let aboutIcon: Float = 76
    static let linkRow: Float = 36
    static let linkGap: Float = 6

    /// The about card is in English, whatever the language of the interface.
    static let aboutDescription = "A 3D Reversi (Othello) game written in Swift on Metal, with a computer opponent of five levels, from Beginner to "
        + "Master. Everything you see and hear is made in code: there is no model, texture or sound file."

    struct Link {
        var name: String
        var address: String // as shown
        var url: String
    }

    static let authorLinks = [
        Link(name: "GitHub", address: "github.com/makarov-mm", url: "https://github.com/makarov-mm"),
        Link(name: "GitHub Sponsors", address: "github.com/sponsors/makarov-mm", url: "https://github.com/sponsors/makarov-mm"),
        Link(name: "LinkedIn", address: "linkedin.com/in/makarov-mm", url: "https://www.linkedin.com/in/makarov-mm/"),
        Link(name: "Threads", address: "threads.net/@m.m.makarov", url: "https://www.threads.net/@m.m.makarov"),
        Link(name: "Instagram", address: "instagram.com/m.m.makarov", url: "https://www.instagram.com/m.m.makarov/"),
    ]

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    // MARK: - Layout

    /// The words in lines no wider than `width`; a word longer than that has a line of its own.
    func wrapText(_ font: FontId, _ words: String, width: Float) -> [String] {
        var lines: [String] = []
        var line = ""
        for word in words.split(separator: " ", omittingEmptySubsequences: false) {
            let longer = line.isEmpty ? String(word) : "\(line) \(word)"
            if !line.isEmpty && painter.measure(font, longer) > width {
                lines.append(line)
                line = String(word)
            } else {
                line = longer
            }
        }
        if !line.isEmpty {
            lines.append(line)
        }
        return lines
    }

    var rulesLines: [String] {
        wrapText(.body, text(.rulesNote), width: (Self.helpWidth - 2 * Self.helpPad) * scale)
    }

    /// The rows of the help close up, down to the height of a line, where the window is too low for them.
    func helpRowHeight(rules: Int) -> Float {
        let rows = Float(Self.helpLineCount + 1 + rules)
        let room = Float(height) - (20 + 2 * Self.helpPad + 44 + 12) * scale
        return max(painter.lineHeight(.body), min(room / rows, Self.helpRow * scale))
    }

    /// A card of the size in the middle of the part of the window beside the panel, or of the window where it is
    /// too wide for that part.
    func centeredCard(width cardWidth: Float, height cardHeight: Float) -> ScreenRect {
        let free = freeArea
        let x = cardWidth <= free.width ? free.x + (free.width - cardWidth) / 2 : max(0, (Float(width) - cardWidth) / 2)
        return ScreenRect(x: x, y: max(10 * scale, (Float(height) - cardHeight) / 2), width: cardWidth, height: cardHeight)
    }

    func helpCard(rules: Int) -> ScreenRect {
        let rows = Float(Self.helpLineCount + 1 + rules)
        return centeredCard(width: Self.helpWidth * scale, height: (2 * Self.helpPad + 44 + 12) * scale + rows * helpRowHeight(rules: rules))
    }

    var aboutCard: ScreenRect {
        let lines = Float(wrapText(.body, Self.aboutDescription, width: (Self.aboutWidth - 2 * Self.aboutPad) * scale).count)
        let links = Float(Self.authorLinks.count)
        let fixed = 2 * Self.aboutPad + Self.aboutIcon + 20 + 16 + 2 + 20 + links * (Self.linkRow + Self.linkGap) - Self.linkGap
        let height = fixed * scale + lines * (painter.lineHeight(.body) + 3 * scale) + painter.lineHeight(.heading) + painter.lineHeight(.body)
        return centeredCard(width: Self.aboutWidth * scale, height: height)
    }

    var bannerCard: ScreenRect {
        let title = text(resultTitle(bannerStatus.result))
        let width = max(painter.measure(.display, title) + 80 * scale, painter.measure(.body, resultDetail(bannerStatus)) + 60 * scale, 320 * scale)
        let free = freeArea
        return ScreenRect(x: free.x + (free.width - width) / 2, y: 26 * scale - (1 - bannerFade) * 20 * scale, width: width, height: 92 * scale)
    }

    /// The cards behind which the scene is blurred.
    func frostedPanels() -> [FrostedPanel] {
        var panels: [FrostedPanel] = []
        func add(_ rect: ScreenRect, _ radius: Float, _ opacity: Float) {
            panels.append(FrostedPanel(rect: rect, radius: radius * scale, opacity: opacity))
        }
        if panelSlide > 0.001 {
            add(panelRect, 18, 1)
        }
        if bannerFade > 0.001 {
            add(bannerCard, 18, bannerFade)
        }
        switch dialog {
        case .help: add(helpCard(rules: rulesLines.count), 20, 1)
        case .about: add(aboutCard, 20, 1)
        case .none: break
        }
        return panels
    }

    func toggleDialog(_ shown: Dialog) {
        dialog = dialog == shown ? .none : shown
        dialogOpening = dialog != .none
        requestFrame()
    }

    /// Opens a card, from the menus: one that is open stays so.
    func showDialog(_ shown: Dialog) {
        if dialog != shown {
            toggleDialog(shown)
        }
    }

    /// A press beside the card. A quick click, such as a tap on a trackpad, presses and lets go within one frame:
    /// when it opens a card, its press must not then close it.
    func pressedOutside(_ card: ScreenRect) -> Bool {
        pointer.leftPressed && !dialogOpening && !card.contains(pointer.x, pointer.y)
    }

    // MARK: - Drawing

    func drawBanner() {
        guard bannerFade > 0.001 else { return }
        let card = bannerCard
        painter.shadow(card, blur: 24 * scale, color: RGBA(0, 0, 0, 120).faded(bannerFade))
        painter.fill(card, radius: 18 * scale, color: RGBA(14, 16, 24, 150).faded(bannerFade))
        painter.outline(card, radius: 18 * scale, color: RGBA(linear: theme.accent).faded(0.6 * bannerFade))
        painter.textCentered(.display, in: ScreenRect(x: card.x, y: card.y + 8 * scale, width: card.width, height: 48 * scale),
                             text(resultTitle(bannerStatus.result)), color: Self.textColor.faded(bannerFade))
        painter.textCentered(.body, in: ScreenRect(x: card.x, y: card.y + 54 * scale, width: card.width, height: 26 * scale), resultDetail(bannerStatus),
                             color: Self.mutedColor.faded(bannerFade))
    }

    /// The newest toast at the bottom, the older ones above it.
    func drawToasts() {
        let free = freeArea
        var y = Float(height) - 40 * scale
        for toast in toasts.reversed() {
            let fade = min(1, toast.age * 6, (2.8 - toast.age) * 3)
            let width = painter.measure(.body, toast.text) + 40 * scale
            let height = 36 * scale
            let pill = ScreenRect(x: free.x + (free.width - width) / 2, y: y - height, width: width, height: height)
            painter.shadow(pill, blur: 14 * scale, color: RGBA(0, 0, 0, 110).faded(fade))
            painter.fill(pill, radius: height / 2, color: RGBA(20, 22, 30, 225).faded(fade))
            painter.textCentered(.body, in: pill, toast.text, color: Self.textColor.faded(fade))
            y -= height + 8 * scale
        }
    }

    func drawHelp() {
        painter.fill(ScreenRect(x: 0, y: 0, width: Float(width), height: Float(height)), radius: 0, color: RGBA(0, 0, 0, 110))

        let lines: [(keys: String, action: Str)] = [
            (text(.keyClick), .helpClick),
            (text(.keyDrag), .helpRotate),
            (text(.keyWheel), .helpZoom),
            ("⌘Z  ←  ⌫", .helpUndo),
            ("⇧⌘Z  →", .helpRedo),
            ("H", .helpHint),
            ("N", .helpNew),
            ("F", .helpFlip),
            ("V", .helpTopView),
            ("1 – 5", .helpLevel),
            ("M", .helpMode),
            ("D", .helpShowMoves),
            ("T", .helpTheme),
            ("S", .helpSound),
            ("L", .helpLanguage),
            ("Tab", .helpPanel),
            ("⌃⌘F  F11", .helpFullScreen),
            ("⌘C", .helpCopy),
            ("⌘V", .helpPaste),
            ("A", .helpAbout),
            ("Esc  F1", .helpClose),
        ]
        let rules = rulesLines
        let rowHeight = helpRowHeight(rules: rules.count)
        let keysWidth = 200 * scale
        let pad = Self.helpPad * scale
        let card = helpCard(rules: rules.count)
        let accent = RGBA(linear: theme.accent)
        painter.shadow(card, blur: 26 * scale, color: RGBA(0, 0, 0, 140))
        painter.fill(card, radius: 20 * scale, color: RGBA(18, 20, 28, 175))
        painter.outline(card, radius: 20 * scale, color: RGBA(255, 255, 255, 30))
        painter.text(.heading, x: card.x + pad, y: card.y + pad - 4 * scale, text(.controls), color: Self.textColor)
        var y = card.y + pad + 44 * scale
        for line in lines {
            painter.text(.body, x: card.x + pad, y: y, line.keys, color: accent)
            painter.text(.body, x: card.x + pad + keysWidth, y: y, text(line.action), color: Self.textColor)
            y += rowHeight
        }
        // The rules, in a few sentences.
        y += 12 * scale
        painter.text(.body, x: card.x + pad, y: y, text(.rules), color: accent)
        for line in rules {
            y += rowHeight
            painter.text(.body, x: card.x + pad, y: y, line, color: Self.mutedColor)
        }
        let close = ScreenRect(x: card.right - pad - 30 * scale, y: card.y + pad - 8 * scale, width: 30 * scale, height: 30 * scale)
        if button(Widget.helpClose, close, "×") || pressedOutside(card) {
            dialog = .none
        }
        if pointer.leftPressed || pointer.rightPressed {
            pointer.consumed = true
        }
    }

    func drawAbout() {
        painter.fill(ScreenRect(x: 0, y: 0, width: Float(self.width), height: Float(self.height)), radius: 0, color: RGBA(0, 0, 0, 110))
        let card = aboutCard
        let pad = Self.aboutPad * scale
        let accent = RGBA(linear: theme.accent)
        painter.shadow(card, blur: 26 * scale, color: RGBA(0, 0, 0, 140))
        painter.fill(card, radius: 20 * scale, color: RGBA(18, 20, 28, 175))
        painter.outline(card, radius: 20 * scale, color: RGBA(255, 255, 255, 30))

        // The icon, and beside it the name and the version.
        let x = card.x + pad
        let width = card.width - 2 * pad
        let icon = Self.aboutIcon * scale
        var y = card.y + pad
        painter.icon(ScreenRect(x: x, y: y, width: icon, height: icon))
        let titleHeight = painter.lineHeight(.display)
        let versionHeight = painter.lineHeight(.body)
        let titleY = y + (icon - titleHeight - versionHeight) / 2
        painter.text(.display, x: x + icon + 18 * scale, y: titleY, "3D Reversi", color: Self.textColor)
        painter.text(.body, x: x + icon + 18 * scale, y: titleY + titleHeight, "Version \(Self.version) for macOS", color: Self.mutedColor)
        y += icon + 20 * scale

        for line in wrapText(.body, Self.aboutDescription, width: width) {
            painter.text(.body, x: x, y: y, line, color: Self.textColor)
            y += painter.lineHeight(.body) + 3 * scale
        }
        y += 16 * scale
        painter.text(.heading, x: x, y: y, "Created by Mykhailo Makarov", color: Self.textColor)
        y += painter.lineHeight(.heading) + 2 * scale
        painter.text(.body, x: x, y: y, "© 2026 · MIT License", color: Self.mutedColor)
        y += painter.lineHeight(.body) + 20 * scale

        // The author's pages, opened in the browser.
        let nameWidth = Self.authorLinks.map { painter.measure(.body, $0.name) }.max() ?? 0
        for (index, link) in Self.authorLinks.enumerated() {
            let row = ScreenRect(x: x, y: y, width: width, height: Self.linkRow * scale)
            let state = interact(Widget.aboutLinks + index, row, enabled: true)
            painter.fill(row, radius: 9 * scale, color: state.pressed ? RGBA(255, 255, 255, 52) : state.hover ? RGBA(255, 255, 255, 34) : RGBA(255, 255, 255, 12))
            let textY = row.y + (row.height - painter.lineHeight(.body)) / 2
            painter.text(.body, x: row.x + 14 * scale, y: textY, link.name, color: Self.textColor)
            painter.text(.body, x: row.x + 32 * scale + nameWidth, y: textY, link.address, color: accent)
            painter.text(.body, x: row.right - 14 * scale - painter.measure(.body, "↗"), y: textY, "↗", color: state.hover ? Self.textColor : Self.mutedColor)
            if state.clicked {
                openLink(link.url)
            }
            y += (Self.linkRow + Self.linkGap) * scale
        }

        let close = ScreenRect(x: card.right - pad - 30 * scale, y: card.y + pad - 8 * scale, width: 30 * scale, height: 30 * scale)
        if button(Widget.aboutClose, close, "×") || pressedOutside(card) {
            dialog = .none
        }
        if pointer.leftPressed || pointer.rightPressed {
            pointer.consumed = true
        }
    }
}
