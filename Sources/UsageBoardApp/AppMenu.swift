import AppKit

@MainActor
enum AppMenu {
    static func make(strings: AppLocalization) -> NSMenu {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem(title: "UsageBoard", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "UsageBoard")
        appMenu.addItem(withTitle: strings.text(.quitUsageBoard),
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem(title: strings.text(.editMenu), action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: strings.text(.editMenu))
        // Leave targets nil so AppKit routes commands to the focused field.
        editMenu.addItem(withTitle: strings.text(.undo), action: NSSelectorFromString("undo:"), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: strings.text(.redo), action: NSSelectorFromString("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: strings.text(.cut), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: strings.text(.copy), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: strings.text(.paste), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: strings.text(.selectAll), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        return mainMenu
    }
}
