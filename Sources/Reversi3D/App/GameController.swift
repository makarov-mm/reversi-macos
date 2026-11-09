import AppKit
import Metal
import simd

/// The game: it runs the play, the computer players and the interface, and has the renderer draw them into the view.
/// The interface is drawn immediately: each frame lays out the widgets and hears the pointer at once.
@MainActor
final class GameController {
    enum Mode: Int {
        case playBlack, playWhite, twoPlayers, demo
    }

    enum Gesture {
        case none, pressSquare, turnCamera
    }

    /// The card shown over the game, which takes the pointer while it is open.
    enum Dialog {
        case none, help, about
    }

    /// What the pointer does to a widget in this frame.
    struct Interaction {
        var hover = false
        var pressed = false
        var clicked = false
    }

    struct Toast {
        var text: String
        var age: Float = 0
    }

    static let panelWidth: Float = 344
    static let panelMargin: Float = 16
    static let textColor = RGBA(236, 239, 245)
    static let mutedColor = RGBA(150, 158, 176)

    // Collaborators.
    weak var view: GameView?
    let renderer: Renderer
    let painter: Painter
    let sound: SoundBank
    /// Told when the language changes, for the menus.
    var languageChanged: (@MainActor (Language) -> Void)?

    // The window.
    var width = 0 // of the picture, in pixels
    var height = 0
    var scale: Float = 1 // of the interface: pixels for a point
    var fontScale: Float = 0 // that the fonts were made for
    var dirty = true // something to draw since the last frame
    var cursorHand = false
    let clock = ContinuousClock()
    var lastFrame: ContinuousClock.Instant
    var time: Float = 0

    // The game.
    var settings: Settings
    var language: Language
    var game = GameRecord()
    var camera = OrbitCamera()
    var boardView = BoardView()
    var events: [BoardView.Event] = []
    var mode = Mode.playBlack
    var level = 3
    var themeIndex = 0
    var showMoves = true
    let computer = AIPlayer(hashMegabytes: 32, label: "com.makarovmm.reversi3d.computer")
    let hinter = AIPlayer(hashMegabytes: 16, label: "com.makarovmm.reversi3d.hint")
    var computerThinking = false
    var computerClock: Float = 0
    var computerResult: SearchResult?
    var hintThinking = false
    var hint: Square?
    var hintGlow: Float = 0
    var announcedEnd = false

    // The pointer.
    var pointer = Pointer()
    var gesture = Gesture.none
    var pressX: Float = 0
    var pressY: Float = 0
    var dragX: Float = 0 // the pointer when the camera last turned
    var dragY: Float = 0
    var pressSquare = -1
    var hoverSquare = -1 // a legal square under the pointer

    // The interface.
    var activeWidget = 0
    var panelVisible = true
    var panelSlide: Float = 1
    var dialog = Dialog.none
    var dialogOpening = false // opened in this frame
    var moveScroll: Float = 0
    var followMoves = true
    var bannerFade: Float = 0
    var bannerStatus = GameStatus()
    var toasts: [Toast] = []

    init(view: GameView) throws {
        guard let device = view.device else { throw RendererError.noDevice }
        let settings = Settings.load(themeCount: Themes.all.count)
        let labels = BoardLabels.render(size: Renderer.labelSize, extent: BoardGeometry.frameOuter, inner: BoardGeometry.frameInner)
        let renderer = try Renderer(device: device, drawableFormat: view.colorPixelFormat, discShapes: DiscModel.build(), labels: labels)
        try renderer.setTheme(Themes.all[settings.theme])
        self.renderer = renderer
        painter = try Painter(device: device, queue: renderer.queue, icon: IconImage(), framesInFlight: Renderer.framesInFlight)
        sound = SoundBank()
        self.view = view
        self.settings = settings
        language = settings.language
        themeIndex = settings.theme
        level = settings.level
        mode = Mode(rawValue: settings.mode) ?? .playBlack
        showMoves = settings.showMoves
        panelVisible = settings.panel
        panelSlide = settings.panel ? 1 : 0
        lastFrame = clock.now

        sound.isEnabled = settings.sound
        if let saved = GameRecord.deserialize(settings.game) {
            game = saved
        }
        announcedEnd = game.status.isOver
        boardView.rebuild(game, animate: true)
        camera.reset(viewSide)
    }

    var theme: Theme { Themes.all[themeIndex] }

    /// The side the player sees the board from.
    var viewSide: Side { mode == .playWhite ? .white : .black }

    var isFullScreen: Bool { view?.window?.styleMask.contains(.fullScreen) ?? false }

    // MARK: - Frames

    /// Something changed: a frame is drawn soon, and the animation clock does not count the time the view rested.
    func requestFrame() {
        dirty = true
        guard let view, view.isPaused else { return }
        lastFrame = clock.now
        view.isPaused = false
    }

    /// Updates the game, lays out the interface and draws a frame; the view rests afterwards while nothing moves.
    func frame() {
        guard let view else { return }
        // Nothing moves while the window cannot be seen: the game goes on from there when it shows again.
        if let window = view.window, !window.occlusionState.contains(.visible) {
            rest(true)
            return
        }
        let now = clock.now
        let elapsed = lastFrame.duration(to: now).components
        let seconds = min(Float(Double(elapsed.seconds) + Double(elapsed.attoseconds) * 1e-18), 0.1)
        lastFrame = now
        time += seconds
        dirty = false

        updateSize()
        guard width > 0, height > 0 else {
            rest(true) // until the view has a size again
            return
        }
        if scale != fontScale {
            buildFonts()
        }
        update(seconds)

        var scene = sceneDescription()
        scene.panels = frostedPanels()
        cursorHand = false
        painter.begin(width: width, height: height)
        drawInterface()
        handleBoardPointer()
        if let drawable = view.currentDrawable {
            renderer.render(scene, to: drawable) { encoder, frameIndex in
                painter.encode(encoder, frameIndex: frameIndex)
            }
        }

        // The widgets are drawn as they were before they heard the click: what it changed shows in the next frame.
        if pointer.leftPressed || pointer.leftReleased || pointer.rightPressed || pointer.rightReleased {
            dirty = true
        }
        dialogOpening = false
        pointer.leftPressed = false
        pointer.leftReleased = false
        pointer.rightPressed = false
        pointer.rightReleased = false
        pointer.zoom = 0
        pointer.scroll = 0
        pointer.consumed = false
        view.setCursor(hand: cursorHand)
        rest(!(dirty || needsAnimation))
    }

    /// Stops the frames, or lets them run, touching the view only when that changes.
    private func rest(_ resting: Bool) {
        if let view, view.isPaused != resting {
            view.isPaused = resting
        }
    }

    private func updateSize() {
        guard let view else { return }
        width = Int(view.drawableSize.width)
        height = Int(view.drawableSize.height)
        let points = Float(view.bounds.width)
        scale = min(max(points > 0 ? Float(width) / points : 1, 0.5), 4)
    }

    private func buildFonts() {
        do {
            let fonts = try FontId.allCases.map { id in
                try FontAtlas(device: renderer.device, queue: renderer.queue, pixelHeight: id.size * scale, semibold: id.isSemibold)
            }
            painter.setFonts(fonts)
            fontScale = scale
        } catch {
            FileHandle.standardError.write(Data("3D Reversi: \(error)\n".utf8))
        }
    }

    private func sceneDescription() -> RenderScene {
        let position = game.current
        let ready = humanToMove && boardView.isSettled
        let lastMove = game.moves.last { !$0.isPass }?.square ?? Squares.pass

        var scene = RenderScene()
        scene.view = camera.view
        scene.projection = camera.projection(aspect: Float(width) / Float(height))
        scene.eye = camera.eye
        scene.time = time
        scene.discs = boardView.draws(lastMove: lastMove, accent: theme.accent, time: time)
        scene.contacts = boardView.contacts()
        if ready && showMoves {
            scene.marks.legal = position.moves
            if hoverSquare >= 0 {
                // The disc that a click would place, seen through.
                scene.marks.hover = Squares.bit(hoverSquare)
                let face = position.sideToMove == .white ? Matrix.identity : Matrix.rotationX(Float.pi)
                var ghost = DiscDraw()
                ghost.model = Matrix.translation(BoardGeometry.squareCenter(hoverSquare) + SIMD3(0, DiscModel.halfHeight + 0.04, 0)) * face
                ghost.opacity = 0.55
                scene.ghost = ghost
            }
        }
        if lastMove != Squares.pass {
            scene.marks.lastMove = Squares.bit(lastMove)
        }
        if let hint, hintGlow > 0.01 {
            scene.marks.hint = Squares.bit(hint)
        }
        return scene
    }

    private func update(_ seconds: Float) {
        let target: Float = panelVisible ? 1 : 0
        panelSlide += (target - panelSlide) * Easing.exponential(seconds, rate: 12)
        if abs(target - panelSlide) < 0.001 {
            panelSlide = target
        }

        let panelSpace = (Self.panelWidth + Self.panelMargin) * scale * panelSlide
        camera.setSpace(1 - panelSpace / Float(max(width, 1)))
        camera.update(seconds)

        // The discs that the move under the pointer would turn over lean, about to go.
        let ready = humanToMove && boardView.isSettled
        boardView.preview(hoverSquare, turning: ready && showMoves && hoverSquare >= 0 ? game.current.flips(hoverSquare) : 0)

        // One sound of each kind a frame: the discs of a wave land together.
        events.removeAll(keepingCapacity: true)
        boardView.update(seconds, events: &events)
        for event in Set(events).sorted() {
            switch event {
            case .place: sound.play(.place)
            case .flip: sound.play(.flip)
            case .stack: sound.play(.stack)
            }
        }

        let over = game.status.isOver && boardView.isSettled
        if over {
            bannerStatus = game.status // kept while the banner fades after a new game
        }
        bannerFade = min(max(bannerFade + (over ? seconds : -seconds) * 3, 0), 1)
        hintGlow = min(max(hintGlow + (hint != nil ? seconds : -seconds) * 4, 0), 1)
        for index in toasts.indices {
            toasts[index].age += seconds
        }
        toasts.removeAll { $0.age > 3.2 }

        updateHint()
        updateComputer(seconds)

        if over && !announcedEnd {
            announcedEnd = true
            sound.play(.gameOver)
        }
        if !game.status.isOver {
            announcedEnd = false
        }
    }

    var needsAnimation: Bool {
        camera.isMoving || boardView.isAnimating || computerThinking || computerResult != nil || hintThinking || !toasts.isEmpty
            || (panelSlide > 0 && panelSlide < 1) || (bannerFade > 0 && bannerFade < 1) || hintGlow > 0 || gesture != .none
            || pointer.leftDown || pointer.rightDown || hoverSquare >= 0 || (!game.status.isOver && !isHuman(game.current.sideToMove))
    }

    // MARK: - The game

    func isHuman(_ side: Side) -> Bool {
        switch mode {
        case .playBlack: side == .black
        case .playWhite: side == .white
        case .twoPlayers: true
        case .demo: false
        }
    }

    var humanToMove: Bool { !game.status.isOver && isHuman(game.current.sideToMove) }

    /// Depth, time, the depth of the exact ending, and the randomness of each level.
    static func levelLimits(_ level: Int, ply: Int, seed: UInt64) -> SearchLimits {
        var limits = switch level {
        case 1: SearchLimits(maxDepth: 1, milliseconds: 2000, exactEmpties: 0, randomMargin: 900, seed: seed)
        case 2: SearchLimits(maxDepth: 2, milliseconds: 2000, exactEmpties: 8, randomMargin: 300, seed: seed)
        case 3: SearchLimits(maxDepth: 4, milliseconds: 2000, exactEmpties: 12, randomMargin: 80, seed: seed)
        case 4: SearchLimits(maxDepth: 8, milliseconds: 1500, exactEmpties: 16, randomMargin: 0, seed: seed)
        default: SearchLimits(maxDepth: 60, milliseconds: 3500, exactEmpties: 20, randomMargin: 0, seed: seed)
        }
        // The first moves vary a little at every level, so that the games differ.
        if ply < 6 {
            limits.randomMargin = max(limits.randomMargin, 60)
        }
        return limits
    }

    func stopComputer() {
        computer.cancel()
        computerThinking = false
        computerResult = nil
        hinter.cancel()
        hintThinking = false
    }

    private func updateComputer(_ seconds: Float) {
        if game.status.isOver || isHuman(game.current.sideToMove) {
            return
        }
        computerClock += seconds
        if !computerThinking && computerResult == nil {
            computer.start(game.current, limits: Self.levelLimits(level, ply: game.ply, seed: UInt64.random(in: .min ... .max)))
            computerThinking = true
            computerClock = 0
        }
        if computerThinking {
            // Asked before the result: a search that has ended has left its result by then.
            let busy = computer.isBusy
            if let result = computer.takeResult() {
                computerResult = result
                computerThinking = false
            } else if !busy {
                computerThinking = false // cancelled; a new search starts next frame
            }
        }
        // The computer waits for the discs to settle, and a moment more, so that its move can be followed.
        let pause: Float = mode == .demo ? 0.8 : 0.35
        if let result = computerResult, boardView.isSettled, computerClock >= pause, gesture == .none {
            computerResult = nil
            if result.best != Squares.pass {
                playMove(result.best)
            }
        }
    }

    private func updateHint() {
        guard hintThinking else { return }
        let busy = hinter.isBusy
        if let result = hinter.takeResult() {
            hintThinking = false
            if result.best != Squares.pass && humanToMove {
                hint = result.best
                showToast(text(.hintToast) + Squares.name(result.best))
            }
        } else if !busy {
            hintThinking = false
        }
    }

    func newGame() {
        stopComputer()
        computer.newGame()
        game.reset(.start)
        boardView.rebuild(game, animate: true)
        camera.reset(viewSide)
        announcedEnd = false
        afterPositionChange()
    }

    func playMove(_ square: Square) {
        guard game.play(square) else { return }
        // The disc, and the pass it may have forced.
        let played = game.moves.last?.isPass == true ? 2 : 1
        for record in game.moves.suffix(played) {
            boardView.play(record, forward: true)
        }
        announcePass()
        afterPositionChange()
    }

    /// A toast for the pass, if the side to move just passed.
    private func announcePass() {
        guard let last = game.moves.last, last.isPass, !game.status.isOver else { return }
        showToast(text(last.side == .black ? .blackPasses : .whitePasses))
        sound.play(.pass)
    }

    func undo() {
        stopComputer()
        guard game.canUndo else {
            showToast(text(.nothingToUndo))
            return
        }
        func undoOne() {
            let before = game.moves
            game.undo()
            for index in stride(from: before.count, to: game.ply, by: -1) {
                boardView.play(before[index - 1], forward: false)
            }
        }
        undoOne()
        // Against the computer, back to the player's own turn.
        while (mode == .playBlack || mode == .playWhite) && !isHuman(game.current.sideToMove) && game.canUndo {
            undoOne()
        }
        afterPositionChange()
    }

    func redo() {
        stopComputer()
        guard game.canRedo else { return }
        func redoOne() {
            let before = game.ply
            game.redo()
            for ply in before..<game.ply {
                boardView.play(game.moves[ply], forward: true)
            }
        }
        redoOne()
        while (mode == .playBlack || mode == .playWhite) && !isHuman(game.current.sideToMove) && game.canRedo {
            redoOne()
        }
        afterPositionChange()
    }

    func setMode(_ index: Int) {
        stopComputer()
        mode = Mode(rawValue: (index % 4 + 4) % 4) ?? .playBlack
        if mode == .playBlack || mode == .playWhite {
            camera.face(viewSide)
        }
        hint = nil
        save()
    }

    func setLevel(_ newLevel: Int) {
        level = min(max(newLevel, 1), 5)
        if computerThinking {
            stopComputer() // starts again at the new level
        }
        save()
    }

    func setTheme(_ index: Int) {
        let count = Themes.all.count
        themeIndex = (index % count + count) % count
        do {
            try renderer.setTheme(theme)
        } catch {
            FileHandle.standardError.write(Data("3D Reversi: \(error)\n".utf8))
        }
        save()
    }

    func toggleShowMoves() {
        showMoves.toggle()
        save()
    }

    func toggleSound() {
        sound.isEnabled.toggle()
        save()
    }

    func toggleLanguage() {
        language = language.other
        languageChanged?(language)
        save()
    }

    func togglePanel() {
        panelVisible.toggle()
        save()
    }

    func requestHint() {
        guard humanToMove, !hintThinking else { return }
        hint = nil
        hinter.start(game.current, limits: SearchLimits(maxDepth: 60, milliseconds: 1500, exactEmpties: 18, randomMargin: 0, seed: 0))
        hintThinking = true
    }

    private func afterPositionChange() {
        hint = nil
        hoverSquare = -1
        followMoves = true
        save()
    }

    func copyGame(position: Bool) {
        guard Desktop.copy(position ? game.current.text : game.text) else { return }
        showToast(text(position ? .positionCopied : .gameCopied))
    }

    func pasteGame() {
        guard let pasted = GameRecord.parse(Desktop.clipboardText) else {
            showToast(text(.nothingToPaste))
            return
        }
        stopComputer()
        computer.newGame()
        game = pasted
        boardView.rebuild(game, animate: true)
        announcedEnd = game.status.isOver
        afterPositionChange()
        showToast(text(.gameLoaded))
    }

    func openLink(_ address: String) {
        if Desktop.open(address) {
            return
        }
        // Where no browser could be started, the link goes to the clipboard instead.
        _ = Desktop.copy(address)
        showToast(text(.linkCopied))
    }

    func toggleFullScreen() {
        view?.window?.toggleFullScreen(nil)
    }

    func save() {
        settings.theme = themeIndex
        settings.level = level
        settings.mode = mode.rawValue
        settings.showMoves = showMoves
        settings.sound = sound.isEnabled
        settings.panel = panelVisible
        settings.language = language
        settings.game = game.serialized
        settings.save()
    }

    /// Stops the searches, before the program ends.
    func shutDown() {
        save()
        computer.cancel()
        hinter.cancel()
    }

    func text(_ id: Str) -> String { id.text(language) }

    func showToast(_ text: String) {
        if toasts.count >= 3 {
            toasts.removeFirst()
        }
        toasts.append(Toast(text: text))
        requestFrame()
    }
}
