import AppKit

/// The menu bar, in the language of the game: the application's menu, View, Window and Help.
@MainActor
final class MainMenu {
    let bar = NSMenu()
    let windowMenu: NSMenu
    let helpMenu: NSMenu
    /// The menus and the items, with their words, to name again when the language changes.
    private var menus: [(item: NSMenuItem, text: Str)] = []
    private var items: [(item: NSMenuItem, text: Str)] = []

    init(target: AppDelegate, language: Language) {
        windowMenu = NSMenu()
        helpMenu = NSMenu()

        let application = NSMenu()
        add(.menuAbout, #selector(AppDelegate.showAbout(_:)), target: target, to: application)
        application.addItem(.separator())
        add(.menuHide, #selector(NSApplication.hide(_:)), key: "h", to: application)
        add(.menuHideOthers, #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], to: application)
        add(.menuShowAll, #selector(NSApplication.unhideAllApplications(_:)), to: application)
        application.addItem(.separator())
        add(.menuQuit, #selector(NSApplication.terminate(_:)), key: "q", to: application)
        attach(application, .title)

        let view = NSMenu()
        add(.menuFullScreen, #selector(AppDelegate.toggleFullScreen(_:)), key: "f", modifiers: [.command, .control], target: target, to: view)
        attach(view, .menuView)

        add(.menuMinimize, #selector(NSWindow.performMiniaturize(_:)), key: "m", to: windowMenu)
        add(.menuZoom, #selector(NSWindow.performZoom(_:)), to: windowMenu)
        attach(windowMenu, .menuWindow)

        add(.menuGameHelp, #selector(AppDelegate.showGameHelp(_:)), key: "?", target: target, to: helpMenu)
        attach(helpMenu, .menuHelp)

        setLanguage(language)
    }

    func setLanguage(_ language: Language) {
        for (item, text) in menus {
            item.title = text.text(language)
            item.submenu?.title = text.text(language)
        }
        for (item, text) in items {
            item.title = text.text(language)
        }
    }

    private func add(_ text: Str, _ action: Selector, key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil,
                     to menu: NSMenu) {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        menu.addItem(item)
        items.append((item, text))
    }

    /// A menu in the bar; the application's own is named by the system.
    private func attach(_ menu: NSMenu, _ text: Str) {
        let item = NSMenuItem()
        item.submenu = menu
        bar.addItem(item)
        menus.append((item, text))
    }
}
