/// The mouse and the keys: the view hands the events over, the frame acts on them.
extension GameController {
    enum PointerButton {
        case left, right
    }

    // MARK: - Pointer events

    func pointerMoved(x: Float, y: Float) {
        pointer.x = x
        pointer.y = y
        requestFrame()
    }

    func pointerButton(_ button: PointerButton, down: Bool, x: Float, y: Float) {
        pointerMoved(x: x, y: y)
        switch button {
        case .left:
            pointer.leftDown = down
            if down {
                pointer.leftPressed = true
            } else {
                pointer.leftReleased = true
            }
        case .right:
            pointer.rightDown = down
            if down {
                pointer.rightPressed = true
            } else {
                pointer.rightReleased = true
            }
        }
    }

    /// The pointer left the view: nothing stays highlighted under it, unless a button is held.
    func pointerLeft() {
        if !pointer.leftDown && !pointer.rightDown {
            pointer.x = -1
            pointer.y = -1
        }
        requestFrame()
    }

    /// The window lost the keyboard: a button let go of in another window is not heard here.
    func releaseButtons() {
        if pointer.leftDown {
            pointer.leftReleased = true
        }
        if pointer.rightDown {
            pointer.rightReleased = true
        }
        pointer.leftDown = false
        pointer.rightDown = false
        requestFrame()
    }

    /// Scrolling by a wheel or a trackpad, in notches as the content moves; `invertedByDevice` when the system turns
    /// the direction round ("natural" scrolling), which the zoom undoes, so that a push away zooms in either way.
    func scrolled(_ steps: Float, invertedByDevice: Bool) {
        pointer.scroll += steps
        pointer.zoom += invertedByDevice ? -steps : steps
        requestFrame()
    }

    /// A pinch on a trackpad, in notches of the wheel.
    func zoomed(_ steps: Float) {
        pointer.zoom += steps
        requestFrame()
    }

    // MARK: - The board

    /// The square under the pointer, or -1: where the ray through it meets the playing surface.
    func squareUnderPointer() -> Square {
        let ray = camera.ray(x: pointer.x, y: pointer.y, width: Float(width), height: Float(height))
        guard abs(ray.direction.y) >= 1e-5 else { return BoardGeometry.square(at: ray.origin) }
        let t = -ray.origin.y / ray.direction.y
        return BoardGeometry.square(at: ray.origin + ray.direction * max(t, 0))
    }

    /// A click on a marked square plays there; a drag with either button turns the view, the wheel zooms.
    func handleBoardPointer() {
        let blocked = pointer.consumed || dialog != .none
        let ready = humanToMove && boardView.isSettled
        let inside = pointer.x >= 0 && pointer.y >= 0 && pointer.x < Float(width) && pointer.y < Float(height)
        let square = inside && !blocked ? squareUnderPointer() : -1

        // The legal square under the pointer, previewed while the legal moves are shown.
        hoverSquare = ready && game.current.isLegal(square) && (gesture == .none || gesture == .pressSquare) ? square : -1
        if hoverSquare >= 0 && showMoves {
            cursorHand = true
        }

        if !blocked && pointer.leftPressed {
            pressX = pointer.x
            pressY = pointer.y
            dragX = pointer.x
            dragY = pointer.y
            pressSquare = square
            gesture = hoverSquare >= 0 ? .pressSquare : .turnCamera
        }
        if !pointer.consumed && pointer.rightPressed && gesture == .none {
            gesture = .turnCamera
            pressSquare = -1
            pressX = pointer.x
            pressY = pointer.y
            dragX = pointer.x
            dragY = pointer.y
        }

        // A press on a square that moves on turns the view instead.
        let travel = abs(pointer.x - pressX) + abs(pointer.y - pressY)
        if gesture == .pressSquare && travel > 6 * scale && pointer.leftDown {
            gesture = .turnCamera
        }
        if gesture == .turnCamera {
            camera.rotate(yaw: -(pointer.x - dragX) * 0.0055 / scale, pitch: (pointer.y - dragY) * 0.0045 / scale)
            dragX = pointer.x
            dragY = pointer.y
        }

        if pointer.leftReleased || pointer.rightReleased {
            if gesture == .pressSquare && pointer.leftReleased {
                if square == pressSquare && ready && game.current.isLegal(square) {
                    playMove(square)
                }
            } else if gesture == .turnCamera && pointer.leftReleased && travel < 4 * scale && ready && square >= 0
                && game.current.occupant(square) == nil {
                showToast(text(.notLegal)) // a click on an empty square where nothing would turn
            }
            if (pointer.leftReleased && gesture != .none && !(gesture == .turnCamera && pointer.rightDown))
                || (pointer.rightReleased && gesture == .turnCamera && !pointer.leftDown) {
                gesture = .none
            }
        }

        if !pointer.consumed && pointer.zoom != 0 {
            camera.zoom(pointer.zoom)
        }
    }

    // MARK: - Keys

    /// A key pressed; true when the game took it. Command and Control both serve for the shortcuts with a modifier.
    @discardableResult
    func keyDown(_ key: KeyPress) -> Bool {
        requestFrame()
        if key.option {
            if (key.code == KeyPress.Code.returnKey || key.code == KeyPress.Code.keypadEnter) && !key.isRepeat {
                toggleFullScreen()
                return true
            }
            return false // the rest of Option is the system's
        }
        if dialog != .none && key.code == KeyPress.Code.escape {
            if !key.isRepeat {
                dialog = .none
            }
            return true
        }

        // Taking back and replaying go on while the key is held; the other keys act once.
        if key.command || key.control {
            switch key.letter {
            case "z"?:
                if key.shift {
                    redo()
                } else {
                    undo()
                }
            case "y"?:
                redo()
            case "c"? where !key.isRepeat:
                copyGame(position: key.shift)
            case "v"? where !key.isRepeat:
                pasteGame()
            case "n"? where !key.isRepeat:
                newGame()
            case "c"?, "v"?, "n"?:
                break
            default:
                return false
            }
            return true
        }

        switch key.code {
        case KeyPress.Code.delete, KeyPress.Code.leftArrow:
            undo()
            return true
        case KeyPress.Code.rightArrow:
            redo()
            return true
        default:
            break
        }
        if key.isRepeat {
            return true
        }

        switch key.code {
        case KeyPress.Code.home:
            camera.reset(viewSide)
        case KeyPress.Code.tab:
            togglePanel()
        case KeyPress.Code.f1, KeyPress.Code.help:
            toggleDialog(.help)
        case KeyPress.Code.f11:
            toggleFullScreen()
        case KeyPress.Code.escape:
            if isFullScreen {
                toggleFullScreen()
            }
        default:
            return letterKey(key)
        }
        return true
    }

    private func letterKey(_ key: KeyPress) -> Bool {
        switch key.letter {
        case "a"?: toggleDialog(.about)
        case "n"?: newGame()
        case "h"?: requestHint()
        case "f"?: camera.flip()
        case "v"?: camera.toggleTopView()
        case "m"?: setMode(mode.rawValue + (key.shift ? -1 : 1))
        case "d"?: toggleShowMoves()
        case "t"?: setTheme(themeIndex + (key.shift ? -1 : 1))
        case "s"?: toggleSound()
        case "l"?: toggleLanguage()
        default:
            guard let level = key.level else { return false }
            setLevel(level)
        }
        return true
    }
}
