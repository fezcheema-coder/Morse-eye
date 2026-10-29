import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab().tabItem { Label("General", systemImage: "gearshape") }
            AITab().tabItem { Label("AI & Keys", systemImage: "key") }
            LocalModelsTab().tabItem { Label("Local Models", systemImage: "arrow.down.circle") }
            ShortcutsTab().tabItem { Label("Shortcuts", systemImage: "command") }
            SignalsTab().tabItem { Label("Signals", systemImage: "light.max") }
        }
        .frame(width: 660, height: 620)
    }
}

// MARK: - General

struct GeneralTab: View {
    @EnvironmentObject var state: AppState
    @State private var screenAccess = Screenshot.hasPermission

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Morse Eye").font(.title2.weight(.semibold))
                        Text("Press a shortcut, the AI looks at your screen, and its answer blinks on your keyboard.")
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Getting started") {
                StepRow(done: screenAccess, title: "Allow screen recording",
                        detail: "Needed to take screenshots. macOS may ask you to reopen Morse Eye afterwards.") {
                    Button(screenAccess ? "Granted" : "Allow…") {
                        Screenshot.requestPermission()
                    }
                    .disabled(screenAccess)
                }
                StepRow(done: state.provider.isLocal || !state.apiKey(for: state.provider).isEmpty || state.provider.id == "custom",
                        title: "Choose an AI", detail: "Currently: \(state.provider.name)") {
                    Text("AI & Keys tab").foregroundStyle(.secondary)
                }
                StepRow(done: state.lastError == nil && !state.lastReply.isEmpty, title: "Try it",
                        detail: "Press \(state.settings.prompts.first?.hotKey?.display ?? "a shortcut") anywhere.") {
                    Button("Test blink") { state.testBlink("SOS") }
                }
            }

            MenuIconSection()

            Section("Behaviour") {
                Toggle("Open Morse Eye when I log in", isOn: $state.launchAtLogin)
                LabeledContent("Answer length") {
                    HStack {
                        Slider(value: Binding(get: { Double(state.settings.maxChars) },
                                              set: { state.settings.maxChars = Int($0) }),
                               in: 5...120, step: 5)
                        Text("\(state.settings.maxChars) characters")
                            .monospacedDigit()
                            .frame(width: 100, alignment: .trailing)
                    }
                }
                Text("Morse is slow, so short answers work best. At 12 WPM, 40 characters takes about 40 seconds.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { screenAccess = Screenshot.hasPermission }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            screenAccess = Screenshot.hasPermission
        }
    }
}

struct MenuIconSection: View {
    @EnvironmentObject var state: AppState

    static let symbols = [
        "dot.radiowaves.left.and.right", "antenna.radiowaves.left.and.right", "eye", "eye.fill",
        "light.max", "lightbulb", "lightbulb.fill", "bolt.fill",
        "sparkles", "wand.and.stars", "brain", "brain.head.profile",
        "viewfinder", "camera.viewfinder", "waveform", "circle.dotted",
        "keyboard", "capslock.fill", "ellipsis.circle", "star.fill",
        "heart.fill", "moon.fill", "sun.max.fill", "cat.fill",
    ]

    var body: some View {
        Section {
            HStack {
                Picker("Style", selection: $state.settings.iconStyle) {
                    ForEach(IconStyle.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Spacer()
                Text("Preview").foregroundStyle(.secondary)
                MenuIconView(style: state.settings.iconStyle, symbol: state.settings.iconSymbol,
                             text: state.settings.iconText, image: state.customIcon)
                    .frame(minWidth: 28, minHeight: 22)
                    .padding(.horizontal, 6)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
            }

            switch state.settings.iconStyle {
            case .symbol:
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 12), spacing: 6) {
                    ForEach(Self.symbols, id: \.self) { name in
                        Button {
                            state.settings.iconSymbol = name
                        } label: {
                            Image(systemName: name)
                                .frame(width: 30, height: 26)
                                .background(state.settings.iconSymbol == name ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6))
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
                TextField("Or type any SF Symbol name", text: $state.settings.iconSymbol)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            case .text:
                TextField("Icon text", text: Binding(
                    get: { state.settings.iconText },
                    set: { state.settings.iconText = String($0.prefix(6)) }))
                    .textFieldStyle(.roundedBorder)
                Text("Up to 6 characters. Emoji work too, e.g. 👁 or 🔦.")
                    .font(.caption).foregroundStyle(.secondary)
            case .image:
                HStack {
                    Button("Choose image…") { chooseImage() }
                    Toggle("Match menu bar colour", isOn: Binding(
                        get: { state.settings.iconTemplate },
                        set: { state.settings.iconTemplate = $0; state.loadCustomIcon() }))
                }
                Text("A simple black-and-transparent PNG looks best. With “Match menu bar colour” on, it turns white in dark mode.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Toggle("Show activity in the icon (camera while capturing, dots while thinking)",
                   isOn: $state.settings.animateIcon)
        } header: {
            Text("Menu bar icon")
        }
    }

    private func chooseImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a picture for the menu bar icon"
        if panel.runModal() == .OK, let url = panel.url {
            state.setCustomIcon(from: url)
        }
    }
}

struct StepRow<Accessory: View>: View {
    let done: Bool
    let title: String
    let detail: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: done ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(done ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            accessory()
        }
    }
}

// MARK: - AI & Keys

struct AITab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var ollama: OllamaManager
    @State private var testResult: String?
    @State private var testing = false

    private var provider: Provider { state.provider }

    private var modelBinding: Binding<String> {
        Binding(get: { state.model(for: provider) },
                set: { state.settings.models[provider.id] = $0 })
    }

    private var modelSuggestions: [String] {
        provider.id == "ollama" ? ollama.installed.map(\.id) : provider.suggestedModels
    }

    var body: some View {
        Form {
            Section("Active AI") {
                Picker("Provider", selection: $state.settings.providerID) {
                    Section("Cloud") {
                        ForEach(Provider.all.filter { !$0.isLocal && $0.id != "custom" }) { Text($0.name).tag($0.id) }
                    }
                    Section("On this Mac (free, private)") {
                        ForEach(Provider.all.filter(\.isLocal)) { Text($0.name).tag($0.id) }
                    }
                    Text(Provider.with(id: "custom").name).tag("custom")
                }

                LabeledContent("Model") {
                    HStack {
                        TextField("Model name", text: modelBinding, prompt: Text(provider.defaultModel))
                            .textFieldStyle(.roundedBorder)
                        if !modelSuggestions.isEmpty {
                            Menu {
                                ForEach(modelSuggestions, id: \.self) { m in
                                    Button(m) { state.settings.models[provider.id] = m }
                                }
                            } label: { Image(systemName: "chevron.down") }
                            .menuStyle(.button)
                            .buttonStyle(.borderless)
                            .fixedSize()
                        }
                    }
                }

                if provider.id == "custom" {
                    TextField("Server address", text: $state.settings.customBaseURL,
                              prompt: Text("https://api.example.com/v1"))
                }
                if provider.id == "claude" {
                    Picker("Effort", selection: $state.settings.effort) {
                        Text("Low (fastest)").tag("low")
                        Text("Medium").tag("medium")
                        Text("High (most careful)").tag("high")
                    }
                }
                if provider.id == "ollama" && ollama.installed.isEmpty {
                    Text("No local models yet. Download one in the Local Models tab.")
                        .font(.caption).foregroundStyle(.orange)
                }

                HStack {
                    Button {
                        testing = true
                        testResult = nil
                        Task {
                            testResult = await state.testConnection()
                            testing = false
                        }
                    } label: { Text("Test connection") }
                    .disabled(testing)
                    if testing { ProgressView().controlSize(.small) }
                    if let testResult {
                        Text(testResult)
                            .font(.caption)
                            .foregroundStyle(testResult.hasPrefix("✓") ? .green : .red)
                            .lineLimit(3)
                            .textSelection(.enabled)
                    }
                }
                Text("The model must understand images. If you see “model not found”, pick a current vision model from your provider's model list.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                ForEach(Provider.withKeys) { p in
                    APIKeyRow(provider: p)
                }
            } header: {
                Text("API keys")
            } footer: {
                Text("Keys are stored in your Mac's Keychain and only sent to that provider.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task { await ollama.refresh() }
    }
}

struct APIKeyRow: View {
    @EnvironmentObject var state: AppState
    let provider: Provider
    @State private var draft = ""
    @State private var saved = false
    @State private var editing = false

    var body: some View {
        HStack(spacing: 8) {
            Text(provider.name).frame(width: 170, alignment: .leading)
            if editing || !saved {
                SecureField("Paste key", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(save)
                Button("Save", action: save).disabled(draft.isEmpty)
            } else {
                Label("Saved", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Change") { draft = ""; editing = true }
                Button(role: .destructive) {
                    state.setAPIKey("", for: provider)
                    saved = false
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete key")
            }
            if let url = provider.keyURL.flatMap({ URL(string: $0) }) {
                Link(destination: url) { Image(systemName: "arrow.up.right.square") }
                    .help("Get a \(provider.name) key")
            }
        }
        .onAppear { saved = !state.apiKey(for: provider).isEmpty }
    }

    private func save() {
        guard !draft.isEmpty else { return }
        state.setAPIKey(draft, for: provider)
        draft = ""
        saved = true
        editing = false
    }
}

// MARK: - Local models

struct LocalModelsTab: View {
    @EnvironmentObject var state: AppState
    @EnvironmentObject var ollama: OllamaManager
    @State private var customName = ""

    var body: some View {
        Form {
            Section {
                engineStatus
            } header: {
                Text("Local AI engine")
            } footer: {
                Text("Local models run entirely on your Mac using Ollama (free). Nothing leaves your computer. This Mac has \(ollama.memoryGB) GB of memory.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if ollama.isRunning {
                if !ollama.installed.isEmpty {
                    Section("Downloaded") {
                        ForEach(ollama.installed) { model in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(model.id)
                                    Text(model.sizeText).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isActive(model.id) {
                                    Label("In use", systemImage: "checkmark").foregroundStyle(.green)
                                } else {
                                    Button("Use") { use(model.id) }
                                }
                                Button(role: .destructive) {
                                    Task { await ollama.delete(model.id) }
                                } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .help("Delete from this Mac")
                            }
                        }
                    }
                }

                Section("Download vision models") {
                    ForEach(OllamaManager.catalog) { model in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(model.title).fontWeight(.medium)
                                    Text(model.size).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(model.blurb).font(.caption).foregroundStyle(.secondary)
                                downloadProgress(model.id)
                            }
                            Spacer()
                            downloadButton(model.id)
                        }
                    }
                    HStack {
                        TextField("Any other model, e.g. qwen2.5vl:3b", text: $customName)
                            .textFieldStyle(.roundedBorder)
                        Button("Download") { ollama.pull(customName); customName = "" }
                            .disabled(customName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    // Downloads started from the text field above
                    ForEach(ollama.downloads.keys.filter { name in !OllamaManager.catalog.contains { $0.id == name } }.sorted(),
                            id: \.self) { name in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading) {
                                Text(name)
                                downloadProgress(name)
                            }
                            Spacer()
                            Button("Cancel") { ollama.cancel(name) }
                        }
                    }
                    Link("Browse more vision models on ollama.com",
                         destination: URL(string: "https://ollama.com/search?c=vision")!)
                        .font(.caption)
                }
            }

            if let message = ollama.message {
                Section { Text(message).font(.callout) }
            }
        }
        .formStyle(.grouped)
        .task { await ollama.refresh() }
    }

    @ViewBuilder private var engineStatus: some View {
        switch ollama.status {
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Checking…") }
        case .notInstalled:
            HStack {
                Label("Ollama isn't installed", systemImage: "xmark.circle").foregroundStyle(.secondary)
                Spacer()
                if ollama.installingOllama { ProgressView().controlSize(.small) }
                Button("Install Ollama") { Task { await ollama.installOllama() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(ollama.installingOllama)
            }
        case .notRunning:
            HStack {
                Label("Ollama is installed but not running", systemImage: "pause.circle").foregroundStyle(.orange)
                Spacer()
                Button("Start Ollama") { ollama.launch() }.buttonStyle(.borderedProminent)
            }
        case .running(let version):
            HStack {
                Label("Ollama is running" + (version.isEmpty ? "" : " (v\(version))"),
                      systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button { Task { await ollama.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
            }
        }
    }

    @ViewBuilder private func downloadProgress(_ name: String) -> some View {
        if let d = ollama.downloads[name] {
            VStack(alignment: .leading, spacing: 2) {
                if let p = d.progress { ProgressView(value: p) } else { ProgressView().progressViewStyle(.linear) }
                Text(d.status + (d.progress.map { String(format: " · %.0f%%", $0 * 100) } ?? ""))
                    .font(.caption2).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360)
        }
    }

    @ViewBuilder private func downloadButton(_ name: String) -> some View {
        if ollama.downloads[name] != nil {
            Button("Cancel") { ollama.cancel(name) }
        } else if ollama.isInstalled(name) {
            if isActive(name) {
                Label("In use", systemImage: "checkmark").foregroundStyle(.green)
            } else {
                Button("Use") { use(name) }
            }
        } else {
            Button { ollama.pull(name) } label: { Label("Download", systemImage: "arrow.down.circle") }
        }
    }

    private func isActive(_ name: String) -> Bool {
        state.settings.providerID == "ollama" && {
            let m = state.model(for: Provider.with(id: "ollama"))
            return m == name || m + ":latest" == name || m == name + ":latest"
        }()
    }

    private func use(_ name: String) {
        state.settings.providerID = "ollama"
        state.settings.models["ollama"] = name
    }
}

// MARK: - Shortcuts

struct ShortcutsTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section {
                ForEach(state.settings.prompts) { prompt in
                    PromptEditor(id: prompt.id)
                }
                Button {
                    state.settings.prompts.append(QuickPrompt(title: "New shortcut", prompt: "", hotKey: nil))
                } label: { Label("Add shortcut", systemImage: "plus") }
            } header: {
                Text("Screenshot shortcuts")
            } footer: {
                Text("Each shortcut takes a screenshot and asks the AI its own question. Shortcuts work in any app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Playback") {
                LabeledContent("Stop blinking") { HotKeyRecorder(hotKey: $state.settings.stopHotKey) }
                LabeledContent("Replay last answer") { HotKeyRecorder(hotKey: $state.settings.replayHotKey) }
            }

            if !state.hotKeyConflicts.isEmpty {
                Section {
                    Label("Already used by another app: \(state.hotKeyConflicts.joined(separator: ", ")). Pick a different combination.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Edits one shortcut. Bindings look the prompt up by id, so deleting a row
/// can't leave a text field pointing at an index that no longer exists.
struct PromptEditor: View {
    @EnvironmentObject var state: AppState
    let id: UUID

    private func binding<T>(_ keyPath: WritableKeyPath<QuickPrompt, T>, default value: T) -> Binding<T> {
        Binding(
            get: { state.settings.prompts.first(where: { $0.id == id })?[keyPath: keyPath] ?? value },
            set: { newValue in
                if let i = state.settings.prompts.firstIndex(where: { $0.id == id }) {
                    state.settings.prompts[i][keyPath: keyPath] = newValue
                }
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: binding(\.title, default: ""))
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 220)
                Spacer()
                HotKeyRecorder(hotKey: binding(\.hotKey, default: nil))
                Button(role: .destructive) {
                    state.settings.prompts.removeAll { $0.id == id }
                } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete shortcut")
            }
            TextField("What should the AI do with the screenshot?", text: binding(\.prompt, default: ""), axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Signals

struct SignalsTab: View {
    @EnvironmentObject var state: AppState
    @State private var testText = "SOS"

    var body: some View {
        Form {
            Section("Output") {
                Picker("Blink on", selection: $state.settings.output) {
                    ForEach(OutputDevice.allCases) { Text($0.title).tag($0) }
                }
                Text(state.settings.output.detail).font(.caption).foregroundStyle(.secondary)
                if state.settings.output == .backlight {
                    LabeledContent("Brightness when on") {
                        Slider(value: $state.settings.backlightLevel, in: 0.1...1)
                    }
                }
                Toggle("Invert (light stays on, turns off for each signal)", isOn: $state.settings.invert)
            }

            Section {
                Picker("Code", selection: $state.settings.codeName) {
                    ForEach(state.codes) { Text($0.name).tag($0.name) }
                }
                if !state.code.description.isEmpty {
                    Text(state.code.description).font(.caption).foregroundStyle(.secondary)
                }
                LabeledContent("Speed") {
                    HStack {
                        Slider(value: $state.settings.wpm, in: 4...30, step: 1)
                        Text("\(Int(state.settings.wpm)) WPM").monospacedDigit().frame(width: 64, alignment: .trailing)
                    }
                }
                HStack {
                    Button("Edit this code…") {
                        if let url = state.code.fileURL { NSWorkspace.shared.open(url) }
                    }
                    Button("New code from this one") {
                        if let url = CodeLibrary.duplicate(state.code) {
                            state.reloadCodes()
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Open codes folder") { NSWorkspace.shared.open(CodeLibrary.folder) }
                    Spacer()
                    Button { state.reloadCodes() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Reload codes after editing")
                        .buttonStyle(.borderless)
                }
                DisclosureGroup("Chart") {
                    CodeChart(code: state.code)
                }
                ForEach(state.codeProblems, id: \.self) { problem in
                    Label(problem, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption).foregroundStyle(.orange)
                }
            } header: {
                Text("Code")
            } footer: {
                Text("Codes are JSON files you can edit in any text editor. Each symbol sets how long the light stays on; the gaps set how long it stays off. Click reload after saving.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Try it") {
                HStack {
                    TextField("Text to blink", text: $testText).textFieldStyle(.roundedBorder)
                    Button("Blink") { state.testBlink(testText) }
                    Button("Stop") { state.stop() }
                }
                Text(state.code.pretty(testText).isEmpty ? "(nothing this code can show)" : state.code.pretty(testText))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let error = state.lastError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// Every character (and whole word) in a code with its blink pattern.
struct CodeChart: View {
    let code: SignalCode

    private var rows: [(String, String)] {
        let chars = code.table.sorted { a, b in
            // letters, then digits, then punctuation
            func rank(_ s: String) -> Int { s.first?.isLetter == true ? 0 : s.first?.isNumber == true ? 1 : 2 }
            return (rank(a.key), a.key) < (rank(b.key), b.key)
        }
        return code.words.sorted { $0.key < $1.key } + chars.map { ($0.key, $0.value) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), alignment: .leading)], alignment: .leading, spacing: 4) {
            ForEach(rows, id: \.0) { key, pattern in
                HStack(spacing: 8) {
                    Text(key).font(.system(.body, design: .rounded).weight(.semibold)).frame(minWidth: 22, alignment: .leading)
                    Text(pattern)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
        .padding(.vertical, 4)
        .textSelection(.enabled)
    }
}
