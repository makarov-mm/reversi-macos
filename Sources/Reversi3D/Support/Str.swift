/// The interface's words in English and Russian.
enum Str {
    case title
    case blackToMove, whiteToMove, thinking
    case draw, blackWins, whiteWins, boardFull, noMovesLeft
    case blackPasses, whitePasses, pass
    case you, computer, player, black, white
    case moves, noMovesYet
    case undo, redo, hint, newGame, flip
    case mode, modeBlack, modeWhite, modeTwoPlayers, modeDemo
    case level, level1, level2, level3, level4, level5
    case showMoves, theme, sound, on, off, languageName
    case footer, controls
    case keyClick, keyDrag, keyWheel
    case helpClick, helpRotate, helpZoom, helpUndo, helpRedo, helpHint, helpNew, helpFlip, helpTopView, helpLevel, helpMode
    case helpShowMoves, helpTheme, helpSound, helpLanguage, helpPanel, helpFullScreen, helpCopy, helpPaste, helpAbout, helpClose
    case rules, rulesNote
    case gameCopied, positionCopied, gameLoaded, nothingToPaste, hintToast, nothingToUndo, notLegal, linkCopied
    case menuAbout, menuHide, menuHideOthers, menuShowAll, menuQuit
    case menuView, menuFullScreen, menuExitFullScreen, menuWindow, menuMinimize, menuZoom, menuHelp, menuGameHelp

    /// The name of a computer level, from 1 to 5.
    static func levelName(_ level: Int) -> Str {
        [.level1, .level2, .level3, .level4, .level5][min(max(level, 1), 5) - 1]
    }

    func text(_ language: Language) -> String {
        let (english, russian) = pair
        return language == .russian ? russian : english
    }

    private var pair: (String, String) {
        switch self {
        case .title: ("3D Reversi", "Реверси 3D")
        case .blackToMove: ("Black to move", "Ход чёрных")
        case .whiteToMove: ("White to move", "Ход белых")
        case .thinking: ("Computer is thinking…", "Компьютер думает…")
        case .draw: ("Draw", "Ничья")
        case .blackWins: ("Black wins", "Чёрные победили")
        case .whiteWins: ("White wins", "Белые победили")
        case .boardFull: ("the board is full", "доска заполнена")
        case .noMovesLeft: ("neither side can move", "ходов больше нет")
        case .blackPasses: ("Black has no move and passes", "Чёрным некуда ходить — пас")
        case .whitePasses: ("White has no move and passes", "Белым некуда ходить — пас")
        case .pass: ("pass", "пас")
        case .you: ("You", "Вы")
        case .computer: ("Computer", "Компьютер")
        case .player: ("Player", "Игрок")
        case .black: ("Black", "Чёрные")
        case .white: ("White", "Белые")
        case .moves: ("Moves", "Ходы")
        case .noMovesYet: ("No moves yet", "Ходов пока нет")
        case .undo: ("Undo", "Назад")
        case .redo: ("Redo", "Вперёд")
        case .hint: ("Hint", "Подсказка")
        case .newGame: ("New game", "Новая партия")
        case .flip: ("Flip board", "Развернуть")
        case .mode: ("Mode", "Режим")
        case .modeBlack: ("You play Black", "Вы за чёрных")
        case .modeWhite: ("You play White", "Вы за белых")
        case .modeTwoPlayers: ("Two players", "Два игрока")
        case .modeDemo: ("Demo game", "Демонстрация")
        case .level: ("Level", "Уровень")
        case .level1: ("Beginner", "Новичок")
        case .level2: ("Casual", "Любитель")
        case .level3: ("Club player", "Разрядник")
        case .level4: ("Expert", "Сильный")
        case .level5: ("Master", "Мастер")
        case .showMoves: ("Show moves", "Показ ходов")
        case .theme: ("Theme", "Тема")
        case .sound: ("Sound", "Звук")
        case .on: ("On", "Вкл")
        case .off: ("Off", "Выкл")
        case .languageName: ("English", "Русский")
        case .footer: ("F1 help · Tab panel · ⌃⌘F full screen", "F1 справка · Tab панель · ⌃⌘F весь экран")
        case .controls: ("Controls", "Управление")
        case .keyClick: ("Click", "Щелчок")
        case .keyDrag: ("Drag", "Перетаскивание")
        case .keyWheel: ("Scroll or pinch", "Прокрутка или щипок")
        case .helpClick: ("Place a disc on a marked square", "Поставить фишку на отмеченное поле")
        case .helpRotate: ("Turn the view (either mouse button)", "Повернуть вид (любой кнопкой мыши)")
        case .helpZoom: ("Zoom in and out", "Приблизить или отдалить")
        case .helpUndo: ("Take back", "Отменить ход")
        case .helpRedo: ("Replay", "Вернуть ход")
        case .helpHint: ("Suggest a move", "Подсказать ход")
        case .helpNew: ("New game", "Новая партия")
        case .helpFlip: ("Flip the board", "Развернуть доску")
        case .helpTopView: ("View from above", "Вид сверху")
        case .helpLevel: ("Computer level", "Уровень компьютера")
        case .helpMode: ("Who plays whom", "Кто с кем играет")
        case .helpShowMoves: ("Show or hide the legal moves", "Показать/скрыть возможные ходы")
        case .helpTheme: ("Next theme", "Следующая тема")
        case .helpSound: ("Sound on or off", "Звук вкл/выкл")
        case .helpLanguage: ("English / Russian", "Русский / английский")
        case .helpPanel: ("Show or hide the panel", "Показать/скрыть панель")
        case .helpFullScreen: ("Full screen", "Весь экран")
        case .helpCopy: ("Copy the game, Shift: the position", "Копировать партию, Shift: позицию")
        case .helpPaste: ("Paste a game or a position", "Вставить партию или позицию")
        case .helpAbout: ("About the game and its author", "Об игре и её авторе")
        case .helpClose: ("Close this help", "Закрыть справку")
        case .rules: ("Rules", "Правила")
        case .rulesNote:
            ("Place a disc so that a line of your opponent's discs lies between it and one of yours: they all turn to your color. "
                + "Black begins; a side that cannot move passes. The most discs at the end wins.",
             "Поставьте фишку так, чтобы между ней и вашей фишкой оказался ряд фишек соперника, — они перевернутся в ваш цвет. "
                + "Начинают чёрные; кому некуда ходить, пропускает ход. Побеждает тот, у кого в конце больше фишек.")
        case .gameCopied: ("Game copied", "Партия скопирована")
        case .positionCopied: ("Position copied", "Позиция скопирована")
        case .gameLoaded: ("Game loaded", "Партия загружена")
        case .nothingToPaste: ("The clipboard has no game or position", "В буфере нет партии или позиции")
        case .hintToast: ("Hint: ", "Подсказка: ")
        case .nothingToUndo: ("No moves to take back", "Нечего отменять")
        case .notLegal: ("Nothing to turn over there", "Сюда нельзя: нечего переворачивать")
        case .linkCopied: ("No browser opened: the link is copied", "Браузер не открылся: ссылка скопирована")
        case .menuAbout: ("About 3D Reversi", "Об игре «Реверси 3D»")
        case .menuHide: ("Hide 3D Reversi", "Скрыть «Реверси 3D»")
        case .menuHideOthers: ("Hide Others", "Скрыть остальные")
        case .menuShowAll: ("Show All", "Показать все")
        case .menuQuit: ("Quit 3D Reversi", "Завершить «Реверси 3D»")
        case .menuView: ("View", "Вид")
        case .menuFullScreen: ("Enter Full Screen", "Войти в полноэкранный режим")
        case .menuExitFullScreen: ("Exit Full Screen", "Выйти из полноэкранного режима")
        case .menuWindow: ("Window", "Окно")
        case .menuMinimize: ("Minimize", "Свернуть")
        case .menuZoom: ("Zoom", "Изменить масштаб")
        case .menuHelp: ("Help", "Справка")
        case .menuGameHelp: ("3D Reversi Help", "Справка «Реверси 3D»")
        }
    }
}
