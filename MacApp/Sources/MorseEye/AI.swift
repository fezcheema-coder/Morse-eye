import Foundation
import Security

struct Provider: Identifiable, Hashable {
    enum Kind { case anthropic, openAICompatible }

    let id: String
    let name: String
    let kind: Kind
    let baseURL: String
    let defaultModel: String
    let suggestedModels: [String]
    let keyURL: String?
    let isLocal: Bool

    var needsKey: Bool { !isLocal && id != "custom" }

    // Model names change often; users can type any model their provider offers.
    static let all: [Provider] = [
        Provider(id: "claude", name: "Claude (Anthropic)", kind: .anthropic,
                 baseURL: "https://api.anthropic.com/v1", defaultModel: "claude-opus-5-5",
                 suggestedModels: ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"],
                 keyURL: "https://console.anthropic.com/settings/keys", isLocal: false),
        Provider(id: "openai", name: "OpenAI", kind: .openAICompatible,
                 baseURL: "https://api.openai.com/v1", defaultModel: "gpt-4o-mini",
                 suggestedModels: ["gpt-4o-mini", "gpt-4o"],
                 keyURL: "https://platform.openai.com/api-keys", isLocal: false),
        Provider(id: "gemini", name: "Google Gemini", kind: .openAICompatible,
                 baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", defaultModel: "gemini-2.5-flash",
                 suggestedModels: ["gemini-2.5-flash", "gemini-2.5-pro"],
                 keyURL: "https://aistudio.google.com/apikey", isLocal: false),
        Provider(id: "groq", name: "Groq", kind: .openAICompatible,
                 baseURL: "https://api.groq.com/openai/v1", defaultModel: "meta-llama/llama-4-scout-17b-16e-instruct",
                 suggestedModels: ["meta-llama/llama-4-scout-17b-16e-instruct",
                                   "meta-llama/llama-4-maverick-17b-128e-instruct",
                                   "qwen/qwen3.6-27b"],
                 keyURL: "https://console.groq.com/keys", isLocal: false),
        Provider(id: "xai", name: "Grok (xAI)", kind: .openAICompatible,
                 baseURL: "https://api.x.ai/v1", defaultModel: "grok-4",
                 suggestedModels: ["grok-4"],
                 keyURL: "https://console.x.ai", isLocal: false),
        Provider(id: "mistral", name: "Mistral", kind: .openAICompatible,
                 baseURL: "https://api.mistral.ai/v1", defaultModel: "mistral-medium-latest",
                 suggestedModels: ["mistral-medium-latest", "pixtral-large-latest"],
                 keyURL: "https://console.mistral.ai/api-keys", isLocal: false),
        Provider(id: "openrouter", name: "OpenRouter", kind: .openAICompatible,
                 baseURL: "https://openrouter.ai/api/v1", defaultModel: "openai/gpt-4o-mini",
                 suggestedModels: ["openai/gpt-4o-mini", "google/gemini-2.5-flash", "anthropic/claude-opus-5-5"],
                 keyURL: "https://openrouter.ai/keys", isLocal: false),
        Provider(id: "together", name: "Together AI", kind: .openAICompatible,
                 baseURL: "https://api.together.xyz/v1", defaultModel: "meta-llama/Llama-4-Scout-17B-16E-Instruct",
                 suggestedModels: ["meta-llama/Llama-4-Scout-17B-16E-Instruct"],
                 keyURL: "https://api.together.ai/settings/api-keys", isLocal: false),
        Provider(id: "ollama", name: "On this Mac (Ollama)", kind: .openAICompatible,
                 baseURL: "http://localhost:11434/v1", defaultModel: "gemma3:4b",
                 suggestedModels: [], keyURL: nil, isLocal: true),
        Provider(id: "lmstudio", name: "On this Mac (LM Studio)", kind: .openAICompatible,
                 baseURL: "http://localhost:1234/v1", defaultModel: "",
                 suggestedModels: [], keyURL: nil, isLocal: true),
        Provider(id: "custom", name: "Other (OpenAI-compatible)", kind: .openAICompatible,
                 baseURL: "", defaultModel: "",
                 suggestedModels: [], keyURL: nil, isLocal: false),
    ]

    static var withKeys: [Provider] { all.filter { $0.needsKey || $0.id == "custom" } }

    static func with(id: String) -> Provider { all.first { $0.id == id } ?? all[0] }
}

struct AppError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// API keys live in the macOS Keychain, one item per provider.
enum Keychain {
    private static let service = "Morse Eye API Keys"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    static func get(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        SecItemDelete(query(account) as CFDictionary)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var q = query(account)
        q[kSecValueData as String] = Data(trimmed.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
}

struct AIRequest {
    var provider: Provider
    var model: String
    var baseURL: String
    var apiKey: String
    var system: String
    var prompt: String
    var image: Data
    var effort: String
}

enum AIClient {
    static func systemPrompt(code: SignalCode, maxChars: Int) -> String {
        var parts = [
            "You are looking at a screenshot of the user's screen. Your reply will be blinked out on a keyboard light, so it must be extremely short.",
            "Reply in at most \(maxChars) characters. Plain text only: no markdown, no emoji, no quotes around the answer.",
            "Only use these characters (plus spaces): \(code.allowedCharacters)",
        ]
        if !code.words.isEmpty {
            parts.append("You may also use these whole words: " + code.words.keys.sorted().joined(separator: ", "))
        }
        if !code.aiInstructions.isEmpty { parts.append(code.aiInstructions) }
        return parts.joined(separator: "\n")
    }

    static func ask(_ r: AIRequest) async throws -> String {
        if r.model.isEmpty { throw AppError("Choose a model for \(r.provider.name) in Settings → AI.") }
        if r.baseURL.isEmpty { throw AppError("Enter the server address for \(r.provider.name) in Settings → AI.") }
        if r.provider.needsKey && r.apiKey.isEmpty {
            throw AppError("Add your \(r.provider.name) API key in Settings → AI.")
        }
        switch r.provider.kind {
        case .anthropic: return try await askClaude(r)
        case .openAICompatible: return try await askOpenAICompatible(r)
        }
    }

    // MARK: Claude (Messages API over HTTPS; there is no official Swift SDK)

    private static func askClaude(_ r: AIRequest) async throws -> String {
        let body: [String: Any] = [
            "model": r.model,
            "max_tokens": 16000,
            "system": r.system,
            "output_config": ["effort": r.effort],
            // If a safety classifier declines, re-run on Anthropic's recommended fallback model.
            "fallbacks": "default",
            "messages": [[
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                 "data": r.image.base64EncodedString()]],
                    ["type": "text", "text": r.prompt],
                ],
            ]],
        ]
        let json = try await post(r.baseURL + "/messages", body: body, headers: [
            "x-api-key": r.apiKey,
            "anthropic-version": "2026-10-21",
            "anthropic-beta": "server-side-fallback-2026-07-01",
        ])
        if json["stop_reason"] as? String == "refusal" { return "ERROR" }
        let blocks = json["content"] as? [[String: Any]] ?? []
        return blocks.filter { $0["type"] as? String == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: OpenAI-compatible (OpenAI, Gemini, Groq, Grok, Mistral, OpenRouter, Ollama, ...)

    private static func askOpenAICompatible(_ r: AIRequest) async throws -> String {
        let imageURL = "data:image/jpeg;base64," + r.image.base64EncodedString()
        func body(separateSystem: Bool) -> [String: Any] {
            let text = separateSystem ? r.prompt : r.system + "\n\n" + r.prompt
            var messages: [[String: Any]] = [[
                "role": "user",
                "content": [
                    ["type": "text", "text": text],
                    ["type": "image_url", "image_url": ["url": imageURL]],
                ],
            ]]
            if separateSystem { messages.insert(["role": "system", "content": r.system], at: 0) }
            return ["model": r.model, "messages": messages]
        }
        let url = r.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/chat/completions"
        let headers: [String: String] = r.apiKey.isEmpty ? [:] : ["Authorization": "Bearer \(r.apiKey)"]
        let json: [String: Any]
        do {
            json = try await post(url, body: body(separateSystem: true), headers: headers)
        } catch let error as HTTPError where error.status == 400 {
            // Some vision models (e.g. on Groq) reject a system message next to an image;
            // retry once with the instructions folded into the user message.
            json = try await post(url, body: body(separateSystem: false), headers: headers)
        }
        let message = (json["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any]
        if let text = message?["content"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let parts = message?["content"] as? [[String: Any]] {
            return parts.compactMap { $0["text"] as? String }.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw AppError("The AI sent back an empty answer.")
    }

    // MARK: HTTP

    struct HTTPError: LocalizedError {
        let status: Int
        let message: String
        var errorDescription: String? { "HTTP \(status): \(message)" }
    }

    static func post(_ urlString: String, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw AppError("Invalid address: \(urlString)") }
        var request = URLRequest(url: url, timeoutInterval: 300)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let result: (Data, URLResponse)
        do {
            result = try await URLSession.shared.data(for: request)
        } catch {
            if url.host == "localhost" {
                throw AppError("Couldn't reach the local AI server. Is it running? (\(error.localizedDescription))")
            }
            throw error
        }
        let (data, response) = result
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (200..<300).contains(status) else {
            let err = json["error"]
            let message = (err as? [String: Any])?["message"] as? String
                ?? err as? String
                ?? String(data: data.prefix(300), encoding: .utf8)
                ?? "Unknown error"
            throw HTTPError(status: status, message: message)
        }
        return json
    }
}
