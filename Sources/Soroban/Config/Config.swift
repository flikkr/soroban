import Foundation

struct Config {
    /// Shown as a hint in Settings; there's no default server.
    static let exampleBaseURL = "https://litellm.example.com"

    let baseURL: URL
    let apiKey: String

    /// Values from the environment (or the login shell), before any Settings overrides.
    struct Environment {
        let apiKey: String?
        let baseURL: String?
    }

    private static var cachedEnvironment: Environment?
    private static let lock = NSLock()

    /// Slow on first call (may start a login shell), so call it off the main thread.
    static func environment() -> Environment {
        lock.lock()
        defer { lock.unlock() }
        if let cachedEnvironment { return cachedEnvironment }

        var env = ProcessInfo.processInfo.environment
        if env["LITELLM_API_KEY"]?.isEmpty ?? true {
            // GUI apps don't inherit shell env; ask the user's login shell.
            env.merge(shellEnvironment(), uniquingKeysWith: { _, new in new })
        }
        let base = stripV1(env["LITELLM_API_URL"] ?? "")
        let key = env["LITELLM_API_KEY"] ?? ""
        let result = Environment(apiKey: key.isEmpty ? nil : key, baseURL: base.isEmpty ? nil : base)
        cachedEnvironment = result
        return result
    }

    /// The spend endpoints live at the server root, not under the OpenAI-style `/v1`,
    /// so a URL like `https://host/v1` (often set for other tools) is trimmed to `https://host`.
    static func stripV1(_ url: String) -> String {
        var url = url.trimmingCharacters(in: .whitespaces)
        while url.hasSuffix("/") { url.removeLast() }
        if url.hasSuffix("/v1") { url.removeLast(3) }
        return url
    }

    /// Settings overrides win; otherwise falls back to the environment.
    static func load() -> Config? {
        let env = environment()
        guard let key = Keychain.apiKey() ?? env.apiKey,
              let base = Settings.baseURLOverride ?? env.baseURL,
              let url = URL(string: base) else { return nil }
        return Config(baseURL: url, apiKey: key)
    }

    private static func shellEnvironment() -> [String: String] {
        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let marker = "__LITELLM_ENV__"
        let script = "printf '\(marker)%s\\n%s\\n\(marker)' \"$LITELLM_API_KEY\" \"$LITELLM_API_URL\""
        let p = Process()
        p.executableURL = URL(fileURLWithPath: shell)
        p.arguments = ["-lic", script]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return [:] }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        let parts = text.components(separatedBy: marker)
        guard parts.count >= 3 else { return [:] }
        let lines = parts[1].components(separatedBy: "\n")
        guard lines.count >= 2 else { return [:] }
        return [
            "LITELLM_API_KEY": lines[0],
            "LITELLM_API_URL": lines[1],
        ].filter { !$0.value.isEmpty }
    }
}
