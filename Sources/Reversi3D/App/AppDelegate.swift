import AppKit
import Metal

/// Starts the game in its window, keeps the menus in its language and stops it when the program ends.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private static let frameName = "MainWindow"

    private var window: NSWindow?
    private var controller: GameController?
    private var mainMenu: MainMenu?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSWindow.allowsAutomaticWindowTabbing = false
        if Bundle.main.bundleURL.pathExtension != "app", let icon = IconImage() {
            // Started outside an application bundle, by `swift run`: the Dock shows the icon all the same.
            NSApp.applicationIconImage = NSImage(cgImage: icon.image, size: NSSize(width: icon.width, height: icon.height))
        }
        do {
            try start()
        } catch {
            fail(error)
        }
    }

    private func start() throws {
        guard let device = MTLCreateSystemDefaultDevice() else { throw RendererError.noDevice }

        // The last frame of the window, or most of the screen's work area, centered in it.
        let work = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let size = NSSize(width: min(1500, (work.width * 0.92).rounded()), height: min(920, (work.height * 0.92).rounded()))
        let view = GameView(frame: NSRect(origin: .zero, size: size), device: device)
        let controller = try GameController(view: view)
        view.controller = controller

        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.contentMinSize = NSSize(width: min(900, work.width), height: min(600, work.height))
        window.backgroundColor = NSColor(srgbRed: 0.016, green: 0.017, blue: 0.022, alpha: 1)
        window.contentView = view
        window.delegate = self
        if !window.setFrameUsingName(Self.frameName) {
            window.setFrameOrigin(NSPoint(x: work.midX - window.frame.width / 2, y: work.midY - window.frame.height / 2))
        }
        window.setFrameAutosaveName(Self.frameName)

        self.window = window
        self.controller = controller
        let menu = MainMenu(target: self, language: controller.language)
        NSApp.mainMenu = menu.bar
        NSApp.windowsMenu = menu.windowMenu
        NSApp.helpMenu = menu.helpMenu
        mainMenu = menu
        window.title = controller.text(.title)
        controller.languageChanged = { [weak self] language in
            self?.mainMenu?.setLanguage(language)
            self?.window?.title = Str.title.text(language)
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(view)
        activate()
        controller.requestFrame()
    }

    private func activate() {
        if #available(macOS 14, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    /// The game cannot start: why, and the end.
    private func fail(_ error: Error) {
        activate()
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "3D Reversi cannot start"
        alert.informativeText = "\(error)"
        alert.runModal()
        NSApp.terminate(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.shutDown()
    }

    // MARK: - The window

    func windowDidResignKey(_ notification: Notification) {
        controller?.releaseButtons()
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        controller?.requestFrame()
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        controller?.requestFrame()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        if window?.occlusionState.contains(.visible) == true {
            controller?.requestFrame()
        }
    }

    // MARK: - The menus

    @objc func showAbout(_ sender: Any?) {
        controller?.showDialog(.about)
    }

    @objc func showGameHelp(_ sender: Any?) {
        controller?.showDialog(.help)
    }

    @objc func toggleFullScreen(_ sender: Any?) {
        window?.toggleFullScreen(sender)
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleFullScreen(_:)), let controller {
            menuItem.title = controller.text(controller.isFullScreen ? .menuExitFullScreen : .menuFullScreen)
        }
        return controller != nil
    }
}
