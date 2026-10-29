import AppKit
import Foundation

/// Downloads and manages open-source models through Ollama, the free engine
/// that runs AI models locally on the Mac.
@MainActor
final class OllamaManager: ObservableObject {
    enum Status: Equatable {
        case checking, notInstalled, notRunning, running(version: String)
    }

    struct CatalogModel: Identifiable {
        let id: String       // Ollama model name, e.g. "gemma3:4b"
        let title: String
        let size: String
        let blurb: String
    }

    struct InstalledModel: Identifiable, Hashable {
        let id: String
        let bytes: Int64
        var sizeText: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
    }

    struct Download {
        var progress: Double?  // nil = indeterminate
        var status: String
        var task: Task<Void, Never>?
    }

    /// Vision models (they can read screenshots). Sizes are approximate download sizes.
    static let catalog: [CatalogModel] = [
        CatalogModel(id: "moondream", title: "Moondream 2", size: "≈1.7 GB",
                     blurb: "Tiny and fast. Fine for simple questions, weak at reading small text."),
        CatalogModel(id: "gemma3:4b", title: "Gemma 3 4B (Google)", size: "≈3.3 GB",
                     blurb: "Good all-rounder for 8 GB Macs. Recommended starting point."),
        CatalogModel(id: "llava:7b", title: "LLaVA 7B", size: "≈4.7 GB",
                     blurb: "Classic open vision model."),
        CatalogModel(id: "minicpm-v", title: "MiniCPM-V 8B", size: "≈5.5 GB",
                     blurb: "Strong at reading text and documents on screen."),
        CatalogModel(id: "qwen2.5vl:7b", title: "Qwen 2.5 VL 7B", size: "≈6 GB",
                     blurb: "Very good at reading screens, charts and UI."),
        CatalogModel(id: "llama3.2-vision", title: "Llama 3.2 Vision 11B (Meta)", size: "≈7.8 GB",
                     blurb: "Detailed answers. Best with 16 GB of memory or more."),
        CatalogModel(id: "gemma3:12b", title: "Gemma 3 12B (Google)", size: "≈8 GB",
                     blurb: "Smarter than 4B. Best with 16 GB of memory or more."),
    ]

    static let base = URL(string: "http://localhost:11434")!
    static let appPath = "/Applications/Ollama.app"

    @Published var status: Status = .checking
    @Published var installed: [InstalledModel] = []
    @Published var downloads: [String: Download] = [:]
    @Published var installingOllama = false
    @Published var message: String?

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var memoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) }

    var isAppInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.appPath)
            || NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama") != nil
    }

    func isInstalled(_ name: String) -> Bool {
        installed.contains { $0.id == name || $0.id == name + ":latest" }
    }

    func refresh() async {
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.base.appendingPathComponent("api/version"))
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            status = .running(version: json?["version"] as? String ?? "")
            let (tagData, _) = try await URLSession.shared.data(from: Self.base.appendingPathComponent("api/tags"))
            let tags = try JSONSerialization.jsonObject(with: tagData) as? [String: Any]
            installed = (tags?["models"] as? [[String: Any]] ?? []).compactMap { m in
                guard let name = m["name"] as? String else { return nil }
                return InstalledModel(id: name, bytes: (m["size"] as? NSNumber)?.int64Value ?? 0)
            }.sorted { $0.id < $1.id }
        } catch {
            status = isAppInstalled ? .notRunning : .notInstalled
            installed = []
        }
    }

    func launch() {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.electron.ollama")
            ?? URL(fileURLWithPath: Self.appPath)
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        Task {
            for _ in 0..<20 {  // wait up to ~10s for the server to come up
                try? await Task.sleep(for: .milliseconds(500))
                await refresh()
                if case .running = status { return }
            }
        }
    }

    /// Download Ollama into /Applications. Falls back to the website if that fails.
    func installOllama() async {
        installingOllama = true
        message = "Downloading Ollama…"
        defer { installingOllama = false }
        do {
            let (zip, response) = try await URLSession.shared.download(
                from: URL(string: "https://ollama.com/download/Ollama-darwin.zip")!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppError("download failed") }
            message = "Installing…"
            let ok = await Task.detached { () -> Bool in
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                p.arguments = ["-x", "-k", zip.path, "/Applications"]
                do { try p.run() } catch { return false }
                p.waitUntilExit()
                return p.terminationStatus == 0
            }.value
            guard ok, FileManager.default.fileExists(atPath: Self.appPath) else { throw AppError("unzip failed") }
            message = "Ollama installed. Starting it…"
            launch()
        } catch {
            message = "Couldn't install automatically. Opening the Ollama website; install it from there, then come back."
            NSWorkspace.shared.open(URL(string: "https://ollama.com/download")!)
        }
    }

    func pull(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, downloads[name] == nil else { return }
        downloads[name] = Download(progress: nil, status: "Starting…")
        let task = Task { [weak self] in
            guard let self else { return }
            await self.runPull(name)
        }
        downloads[name]?.task = task
    }

    func cancel(_ name: String) {
        downloads[name]?.task?.cancel()
        downloads[name] = nil
    }

    private func runPull(_ name: String) async {
        var request = URLRequest(url: Self.base.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.timeoutInterval = 3600
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name, "stream": true])
        do {
            let (bytes, _) = try await URLSession.shared.bytes(for: request)
            for try await line in bytes.lines {
                guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
                if let error = json["error"] as? String { throw AppError(error) }
                let status = json["status"] as? String ?? ""
                var progress: Double?
                if let total = (json["total"] as? NSNumber)?.doubleValue, total > 0,
                   let done = (json["completed"] as? NSNumber)?.doubleValue {
                    progress = done / total
                }
                downloads[name]?.status = status.capitalized
                downloads[name]?.progress = progress
                if status == "success" { break }
            }
            downloads[name] = nil
            message = "\(name) is ready."
            await refresh()
        } catch is CancellationError {
            downloads[name] = nil
        } catch {
            downloads[name] = nil
            if !Task.isCancelled { message = "Couldn't download \(name): \(error.localizedDescription)" }
        }
    }

    func delete(_ name: String) async {
        var request = URLRequest(url: Self.base.appendingPathComponent("api/delete"))
        request.httpMethod = "DELETE"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": name])
        _ = try? await URLSession.shared.data(for: request)
        await refresh()
    }
}
