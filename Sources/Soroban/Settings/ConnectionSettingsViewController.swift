import AppKit

final class ConnectionSettingsViewController: NSViewController {
    private let urlField = NSTextField()
    private let keyField = NSSecureTextField()
    private let urlNote = SettingsUI.note("Leave empty to use LITELLM_API_URL from your shell.")
    private let keyNote = SettingsUI.note("Leave empty to use LITELLM_API_KEY from your shell. Saved in your Keychain.")
    private let statusField = SettingsUI.note("")
    private var environment: Config.Environment?

    override func loadView() {
        urlField.placeholderString = Config.exampleBaseURL
        urlField.stringValue = Settings.baseURLOverride ?? ""
        keyField.placeholderString = "sk-…"
        keyField.stringValue = Keychain.apiKey() ?? ""
        for field in [urlField, keyField] {
            field.widthAnchor.constraint(equalToConstant: 320).isActive = true
        }

        let testButton = NSButton(title: "Test Connection", target: self, action: #selector(testConnection))
        let saveButton = NSButton(title: "Save", target: self, action: #selector(save))
        saveButton.keyEquivalent = "\r"
        let buttons = NSStackView(views: [testButton, saveButton])
        SettingsUI.setStatus(statusField, "")

        let grid = SettingsUI.form([
            ("Server URL:", SettingsUI.vstack([urlField, urlNote])),
            ("API key:", SettingsUI.vstack([keyField, keyNote])),
            (nil, SettingsUI.vstack([buttons, statusField], spacing: 10)),
        ])
        let size = NSSize(width: 480, height: 250)
        view = SettingsUI.container(grid, size: size)
        preferredContentSize = size
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // May start a login shell the first time, so keep it off the main thread.
        DispatchQueue.global().async {
            let env = Config.environment()
            DispatchQueue.main.async {
                self.environment = env
                self.urlField.placeholderString = env.baseURL ?? Config.exampleBaseURL
                self.keyField.placeholderString = env.apiKey != nil ? "Using LITELLM_API_KEY" : "sk-…"
            }
        }
    }

    private var enteredURL: String? {
        let value = Config.stripV1(urlField.stringValue)
        return value.isEmpty ? nil : value
    }

    private var enteredKey: String? {
        let value = keyField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func isValidURL(_ string: String) -> Bool {
        guard let url = URL(string: string), let scheme = url.scheme else { return false }
        return (scheme == "https" || scheme == "http") && url.host != nil
    }

    /// The config the fields describe, falling back to the environment like the app does.
    private func configFromFields() -> Result<Config, ConfigProblem> {
        guard let base = enteredURL ?? environment?.baseURL else { return .failure(.missingURL) }
        guard isValidURL(base), let url = URL(string: base) else { return .failure(.invalidURL) }
        guard let key = enteredKey ?? environment?.apiKey else { return .failure(.missingKey) }
        return .success(Config(baseURL: url, apiKey: key))
    }

    private enum ConfigProblem: Error {
        case missingURL, invalidURL, missingKey

        var message: String {
            switch self {
            case .missingURL: return "Enter a server URL, or set LITELLM_API_URL in your shell."
            case .invalidURL: return "The server URL should look like \(Config.exampleBaseURL)"
            case .missingKey: return "Enter an API key, or set LITELLM_API_KEY in your shell."
            }
        }
    }

    @objc private func save() {
        if let url = enteredURL, !isValidURL(url) {
            SettingsUI.setStatus(statusField, ConfigProblem.invalidURL.message, isError: true)
            return
        }
        UserDefaults.standard.set(enteredURL, forKey: Settings.Keys.baseURLOverride)
        guard Keychain.setAPIKey(enteredKey) else {
            SettingsUI.setStatus(statusField, "Couldn't save the API key to your Keychain.", isError: true)
            return
        }
        NotificationCenter.default.post(name: Settings.didChange, object: nil)
        runTest(savedPrefix: "Saved. ")
    }

    @objc private func testConnection() {
        runTest(savedPrefix: "")
    }

    private func runTest(savedPrefix: String) {
        let config: Config
        switch configFromFields() {
        case .success(let value): config = value
        case .failure(let problem):
            SettingsUI.setStatus(statusField, savedPrefix + problem.message, isError: true)
            return
        }
        SettingsUI.setStatus(statusField, savedPrefix + "Testing…")
        LiteLLMClient(config: config).fetchKeyInfo { result in
            switch result {
            case .success(let info):
                var text = "✓ Connected"
                if let name = info.key_alias ?? info.key_name { text += " as \(name)" }
                SettingsUI.setStatus(self.statusField, savedPrefix + text)
            case .failure(let error):
                var message = error.localizedDescription
                if case LiteLLMError.http(401) = error { message = "The API key was rejected (HTTP 401)." }
                if case LiteLLMError.http(0) = error { message = "Couldn't reach the server. Check the URL and your network." }
                SettingsUI.setStatus(self.statusField, savedPrefix + "✗ " + message, isError: true)
            }
        }
    }
}
