import AppKit

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar

        let pages: [(NSViewController, String, String)] = [
            (GeneralSettingsViewController(), "General", "gearshape"),
            (ConnectionSettingsViewController(), "Connection", "network"),
            (NotificationsSettingsViewController(), "Notifications", "bell.badge"),
            (ModelsSettingsViewController(), "Models", "cpu"),
            (StatsSettingsViewController(), "Stats", "chart.bar.xaxis"),
        ]
        for (controller, label, symbol) in pages {
            controller.title = label
            let item = NSTabViewItem(viewController: controller)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        self.init(window: window)
        window.center()
    }

    func show() {
        // The app has no Dock icon, so it has to be activated for the window to come to the front.
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
