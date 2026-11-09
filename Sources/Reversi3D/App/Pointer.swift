/// What the mouse did since the last frame, in pixels from the top left of the view.
struct Pointer {
    var x: Float = -1
    var y: Float = -1
    var leftDown = false
    var rightDown = false
    var leftPressed = false
    var leftReleased = false
    var rightPressed = false
    var rightReleased = false
    /// Steps of zoom, in notches of a wheel: away from the user, or pinching out, is positive.
    var zoom: Float = 0
    /// Steps of scrolling a list, in notches, as the content moves: positive moves it down, to what comes before.
    var scroll: Float = 0
    /// Taken by the interface.
    var consumed = false
}
