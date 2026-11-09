import AppKit

/// What the game asks of the desktop: the clipboard and the browser.
@MainActor
enum Desktop {
    static func copy(_ text: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.setString(text, forType: .string)
    }

    static var clipboardText: String {
        NSPasteboard.general.string(forType: .string) ?? ""
    }

    /// Opens a page in the browser; false when none could be opened.
    static func open(_ address: String) -> Bool {
        guard let url = URL(string: address) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
