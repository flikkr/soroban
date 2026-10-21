import AppKit
import ServiceManagement

final class GeneralSettingsViewController: NSViewController {
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch Soroban at login", target: nil, action: nil)
    private let launchNote = SettingsUI.note("")
    private let intervalPopup = NSPopUpButton()
    private let refreshOnOpen = NSButton(checkboxWithTitle: "Also refresh when the menu opens", target: nil, action: nil)

    override func loadView() {
        launchAtLogin.target = self
        launchAtLogin.action = #selector(toggleLaunchAtLogin)

        for minutes in Settings.refreshOptions {
            intervalPopup.addItem(withTitle: minutes == 1 ? "1 minute" : "\(minutes) minutes")
            intervalPopup.lastItem?.tag = minutes
        }
        intervalPopup.selectItem(withTag: Int(Settings.refreshInterval / 60))
        intervalPopup.target = self
        intervalPopup.action = #selector(changeInterval)

        refreshOnOpen.state = Settings.refreshOnOpen ? .on : .off
        refreshOnOpen.target = self
        refreshOnOpen.action = #selector(toggleRefreshOnOpen)

        let grid = SettingsUI.form([
            ("Startup:", SettingsUI.vstack([launchAtLogin, launchNote])),
            ("Refresh every:", intervalPopup),
            (nil, refreshOnOpen),
            ("Version:", SettingsUI.label(Self.versionString)),
        ])
        let size = NSSize(width: 480, height: 200)
        view = SettingsUI.container(grid, size: size)
        preferredContentSize = size
    }

    /// e.g. "1.0.0 (build 12)", read from the Info.plist that build.sh writes.
    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "dev"
        guard let build = info?["CFBundleVersion"] as? String else { return version }
        return "\(version) (build \(build))"
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        updateLaunchState()
    }

    private func updateLaunchState() {
        let status = SMAppService.mainApp.status
        launchAtLogin.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        if status == .requiresApproval {
            SettingsUI.setStatus(launchNote, "Allow Soroban in System Settings → General → Login Items.")
        } else {
            SettingsUI.setStatus(launchNote, "")
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if launchAtLogin.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            updateLaunchState()
        } catch {
            updateLaunchState()
            SettingsUI.setStatus(launchNote, "Couldn't change this: \(error.localizedDescription)", isError: true)
        }
    }

    @objc private func changeInterval() {
        UserDefaults.standard.set(intervalPopup.selectedTag(), forKey: Settings.Keys.refreshMinutes)
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
    }

    @objc private func toggleRefreshOnOpen() {
        UserDefaults.standard.set(refreshOnOpen.state == .on, forKey: Settings.Keys.refreshOnOpen)
    }
}
