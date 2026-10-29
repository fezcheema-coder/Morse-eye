import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

struct QuickPrompt: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var prompt: String
    var hotKey: HotKey?
}

/// Everything the user can change, saved as one JSON blob in UserDefaults.
struct AppSettings: Codable, Equatable {
    var providerID = "claude"
    var models: [String: String] = [:]   // provider id -> chosen model
    var customBaseURL = ""
    var effort = "low"
    var maxChars = 40

    var output: OutputDevice = .capsLock
    var backlightLevel = 1.0
    var invert = false
    var wpm = 12.0
    var codeName = "International Morse"

    var prompts: [QuickPrompt] = [
        QuickPrompt(title: "What's on screen?", prompt: "Briefly, what is on this screen?",
                    hotKey: .cmdOptShift(kVK_ANSI_M, "M")),
        QuickPrompt(title: "Any errors?", prompt: "Is there an error or warning visible? Say what it is in a few words.",
                    hotKey: .cmdOptShift(kVK_ANSI_E, "E")),
        QuickPrompt(title: "Read the time", prompt: "What time or date is shown on screen?",
                    hotKey: .cmdOptShift(kVK_ANSI_T, "T")),
    ]
    var stopHotKey: HotKey? = .cmdOptShift(kVK_ANSI_X, "X")
    var replayHotKey: HotKey? = .cmdOptShift(kVK_ANSI_R, "R")

    var onboarded = false

    private static let key = "settings.v1"

    /// Saved values are merged over defaults, so new settings added in later versions
    /// get their default instead of wiping everything.
    static func load() -> AppSettings {
        let defaults = AppSettings()
        guard let saved = UserDefaults.standard.data(forKey: key),
              let savedDict = try? JSONSerialization.jsonObject(with: saved) as? [String: Any],
              let defaultData = try? JSONEncoder().encode(defaults),
              var merged = try? JSONSerialization.jsonObject(with: defaultData) as? [String: Any] else {
            return defaults
        }
        merged.merge(savedDict) { _, new in new }
        guard let data = try? JSONSerialization.data(withJSONObject: merged),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else { return defaults }
        return settings
    }

    /// Turned off by the self-test so it never touches the user's real settings.
    static var persist = true

    func save() {
        guard Self.persist else { return }
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    enum Phase: Equatable { case idle, capturing, thinking, blinking }

    @Published var settings: AppSettings {
        didSet {
            settings.save()
            if oldValue.prompts != settings.prompts || oldValue.stopHotKey != settings.stopHotKey
                || oldValue.replayHotKey != settings.replayHotKey {
                registerHotKeys()
            }
        }
    }

    @Published var phase: Phase = .idle
    @Published var iconLit = false
    @Published var lastPrompt = ""
    @Published var lastReply = ""
    @Published var lastError: String?
    @Published var hotKeyConflicts: [String] = []
    @Published var codes: [SignalCode] = []
    @Published var codeProblems: [String] = []
    /// Bumped when keys change so views re-read the Keychain.
    @Published var keysVersion = 0

    let ollama: OllamaManager
    private var work: Task<Void, Never>?
    private var playback: Task<Void, Never>?

    init() {
        settings = AppSettings.load()
        ollama = OllamaManager()
        reloadCodes()
        registerHotKeys()
    }

    // MARK: Derived

    var provider: Provider { Provider.with(id: settings.providerID) }

    func model(for provider: Provider) -> String {
        let chosen = settings.models[provider.id]?.trimmingCharacters(in: .whitespaces) ?? ""
        return chosen.isEmpty ? provider.defaultModel : chosen
    }

    var code: SignalCode {
        codes.first(where: { $0.name == settings.codeName }) ?? codes.first
            ?? (try! JSONDecoder().decode(SignalCode.self, from: Data(BuiltInCodes.morse.utf8)))
    }

    var menuIcon: String {
        switch phase {
        case .idle: "dot.radiowaves.left.and.right"
        case .capturing: "camera.viewfinder"
        case .thinking: "ellipsis.circle"
        case .blinking: iconLit ? "circle.fill" : "circle"
        }
    }

    var statusText: String {
        switch phase {
        case .idle: lastError == nil ? "Ready" : "Something went wrong"
        case .capturing: "Taking screenshot…"
        case .thinking: "Asking \(provider.name)…"
        case .blinking: "Blinking answer…"
        }
    }

    // MARK: Keys

    func apiKey(for provider: Provider) -> String { Keychain.get(provider.id) ?? "" }

    func setAPIKey(_ key: String, for provider: Provider) {
        Keychain.set(key, for: provider.id)
        keysVersion += 1
    }

    // MARK: Codes

    func reloadCodes() {
        let result = CodeLibrary.loadAll()
        codes = result.codes
        codeProblems = result.problems
    }

    // MARK: Hotkeys

    func registerHotKeys() {
        let center = HotKeyCenter.shared
        center.unregisterAll()
        var conflicts: [String] = []
        for prompt in settings.prompts {
            guard let key = prompt.hotKey else { continue }
            let id = prompt.id
            if !center.register(key, handler: { [weak self] in self?.run(promptID: id) }) {
                conflicts.append(key.display)
            }
        }
        if let key = settings.stopHotKey, !center.register(key, handler: { [weak self] in self?.stop() }) {
            conflicts.append(key.display)
        }
        if let key = settings.replayHotKey, !center.register(key, handler: { [weak self] in self?.replay() }) {
            conflicts.append(key.display)
        }
        hotKeyConflicts = conflicts
    }

    // MARK: Main flow: screenshot -> AI -> blink

    func run(promptID: UUID) {
        guard let prompt = settings.prompts.first(where: { $0.id == promptID }) else { return }
        run(prompt.prompt)
    }

    func run(_ prompt: String) {
        guard phase == .idle || phase == .blinking else { return }  // already working
        stop()
        work = Task { await perform(prompt) }
    }

    private func perform(_ prompt: String) async {
        lastPrompt = prompt
        lastError = nil
        phase = .capturing
        do {
            let image = try await Screenshot.captureJPEG()
            phase = .thinking
            let raw = try await AIClient.ask(request(prompt: prompt, image: image))
            try Task.checkCancellation()
            let reply = code.sanitize(raw)
            lastReply = reply.isEmpty ? code.sanitize("ERROR") : reply
            if reply.isEmpty { lastError = "The AI's answer had no characters this code can show: \"\(raw)\"" }
            await blink(lastReply)
        } catch {
            if Task.isCancelled { phase = .idle; return }  // stopped by the user
            lastError = error.localizedDescription
            phase = .idle
            await blink(code.sanitize("ERROR"))
        }
    }

    func request(prompt: String, image: Data) -> AIRequest {
        let p = provider
        return AIRequest(
            provider: p,
            model: model(for: p),
            baseURL: p.id == "custom" ? settings.customBaseURL : p.baseURL,
            apiKey: apiKey(for: p),
            system: AIClient.systemPrompt(code: code, maxChars: settings.maxChars),
            prompt: prompt,
            image: image,
            effort: settings.effort
        )
    }

    /// Sends a blank image to check the provider, model and key work.
    func testConnection() async -> String {
        do {
            var r = request(prompt: "This is a connection test. Reply with just: OK", image: Screenshot.blankJPEG())
            r.system = "Reply with just the word OK."
            let reply = try await AIClient.ask(r)
            return "✓ Connected. \(provider.name) replied: \(reply.prefix(60))"
        } catch {
            return "✗ \(error.localizedDescription)"
        }
    }

    // MARK: Playback

    func makeLED() throws -> LEDOutput {
        switch settings.output {
        case .capsLock: return try CapsLockLED()
        case .backlight: return try BacklightLED(level: settings.backlightLevel)
        case .menuBar: return MenuBarLED { [weak self] lit in self?.iconLit = lit }
        }
    }

    func blink(_ text: String) async {
        playback?.cancel()
        let steps = code.timeline(text)
        guard !steps.isEmpty else { phase = .idle; return }
        let led: LEDOutput
        do { led = try makeLED() } catch {
            lastError = error.localizedDescription
            phase = .idle
            return
        }
        let unit = SignalCode.unitSeconds(wpm: settings.wpm)
        let invert = settings.invert
        phase = .blinking
        let task = Task { @MainActor in
            led.begin()
            for step in steps {
                if Task.isCancelled { break }
                led.set(step.on != invert)
                try? await Task.sleep(for: .seconds(Double(step.units) * unit))
            }
            led.set(invert)
            led.end()
        }
        playback = task
        await task.value
        if playback == task { phase = .idle }
    }

    func replay() {
        guard !lastReply.isEmpty, phase == .idle || phase == .blinking else { return }
        let text = lastReply
        work = Task { await blink(text) }
    }

    func testBlink(_ text: String) {
        stop()
        let clean = code.sanitize(text)
        work = Task { await blink(clean) }
    }

    func stop() {
        work?.cancel()
        playback?.cancel()
        if phase != .blinking { phase = .idle }
    }

    // MARK: Launch at login

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                lastError = "Couldn't change Launch at Login: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }
}
