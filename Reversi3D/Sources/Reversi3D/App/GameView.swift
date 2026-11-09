import AppKit
import MetalKit

/// The view the game draws into. It hands the mouse, the trackpad and the keys to the controller, in pixels from
/// its top left corner, and draws a frame when the controller asks for one; between them it rests.
final class GameView: MTKView {
    var controller: GameController?
    private var trackingArea: NSTrackingArea?
    private var handCursor = false

    init(frame: NSRect, device: MTLDevice) {
        super.init(frame: frame, device: device)
        colorPixelFormat = .bgra8Unorm // the composite pass writes sRGB values itself
        depthStencilPixelFormat = .invalid
        sampleCount = 1
        framebufferOnly = true
        autoResizeDrawable = true
        enableSetNeedsDisplay = false
        isPaused = true
        preferredFramesPerSecond = 120
        colorspace = CGColorSpace(name: CGColorSpace.sRGB)
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("GameView is not loaded from an interface file")
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        controller?.frame()
    }

    // MARK: - Size

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        controller?.requestFrame()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        controller?.requestFrame()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        controller?.requestFrame()
    }

    // MARK: - Mouse and trackpad

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Where the event happened, in pixels of the drawable from the top left.
    private func location(_ event: NSEvent) -> (x: Float, y: Float) {
        let point = convert(event.locationInWindow, from: nil)
        let size = drawableSize
        let scaleX = bounds.width > 0 ? size.width / bounds.width : 1
        let scaleY = bounds.height > 0 ? size.height / bounds.height : 1
        let fromTop = isFlipped ? point.y : bounds.height - point.y
        return (Float(point.x * scaleX), Float(fromTop * scaleY))
    }

    private func button(_ button: GameController.PointerButton, down: Bool, _ event: NSEvent) {
        let point = location(event)
        controller?.pointerButton(button, down: down, x: point.x, y: point.y)
    }

    private func moved(_ event: NSEvent) {
        let point = location(event)
        controller?.pointerMoved(x: point.x, y: point.y)
    }

    override func mouseDown(with event: NSEvent) { button(.left, down: true, event) }
    override func mouseUp(with event: NSEvent) { button(.left, down: false, event) }
    override func rightMouseDown(with event: NSEvent) { button(.right, down: true, event) }
    override func rightMouseUp(with event: NSEvent) { button(.right, down: false, event) }
    override func mouseMoved(with event: NSEvent) { moved(event) }
    override func mouseDragged(with event: NSEvent) { moved(event) }
    override func rightMouseDragged(with event: NSEvent) { moved(event) }

    override func mouseExited(with event: NSEvent) {
        controller?.pointerLeft()
    }

    /// A wheel moves in notches, a trackpad or a Magic Mouse in points, ten of them to a notch.
    override func scrollWheel(with event: NSEvent) {
        let delta = Float(event.scrollingDeltaY)
        let steps = event.hasPreciseScrollingDeltas ? delta * 0.1 : delta
        if steps != 0 {
            controller?.scrolled(steps, invertedByDevice: event.isDirectionInvertedFromDevice)
        }
    }

    /// A pinch on a trackpad zooms as the wheel does.
    override func magnify(with event: NSEvent) {
        controller?.zoomed(Float(event.magnification) * 8)
    }

    // MARK: - Cursor

    private var cursor: NSCursor { handCursor ? NSCursor.pointingHand : NSCursor.arrow }

    /// The pointing hand over what can be clicked, the arrow elsewhere.
    func setCursor(hand: Bool) {
        guard hand != handCursor else { return }
        handCursor = hand
        guard let window, window.isKeyWindow else { return }
        if bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil)) {
            cursor.set()
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        cursor.set()
    }

    // MARK: - Keys

    private func keyPress(_ event: NSEvent) -> KeyPress {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return KeyPress(code: event.keyCode, letter: KeyPress.shortcutLetter(characters: event.charactersIgnoringModifiers, code: event.keyCode),
                        command: flags.contains(.command), shift: flags.contains(.shift), option: flags.contains(.option),
                        control: flags.contains(.control), isRepeat: event.isARepeat)
    }

    /// The keys without Command or Control; those the game does not use are let go of quietly.
    override func keyDown(with event: NSEvent) {
        controller?.keyDown(keyPress(event))
    }

    /// The shortcuts with Command or Control that the game uses, before the menus see them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown, let controller {
            let key = keyPress(event)
            if (key.command || key.control) && controller.keyDown(key) {
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
