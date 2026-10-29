import AppKit

@main
enum Entry {
    @MainActor
    static func main() {
        if CommandLine.arguments.contains("--self-test") {
            SelfTest.start()
            RunLoop.main.run()
        } else {
            MorseEyeApp.main()
        }
    }
}

/// `MorseEye --self-test` exercises the non-UI paths (codes, Test connection, both
/// request formats, blinking) against a mock server. CI runs it on every build.
@MainActor
enum SelfTest {
    private static var failures = 0

    private static func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        print(ok ? "PASS" : "FAIL", name, detail.isEmpty ? "" : "— \(detail)")
        if !ok { failures += 1 }
    }

    static func start() {
        setvbuf(stdout, nil, _IOLBF, 0)  // line-buffered, so output survives a crash
        AppSettings.persist = false
        Task { @MainActor in
            await run()
            print(failures == 0 ? "SELF-TEST OK" : "SELF-TEST FAILED (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
    }

    private static func run() async {
        let base = (ProcessInfo.processInfo.environment["MOCK_URL"] ?? "http://127.0.0.1:8787") + "/v1"
        let state = AppState.shared
        print("codes:", state.codes.map(\.name))
        check("codes loaded", !state.codes.isEmpty, state.codeProblems.joined(separator: "; "))
        for code in state.codes {
            check("timeline \(code.name)", !code.timeline("YES 123").isEmpty, code.pretty("YES 123"))
        }

        print("making blank image…")
        let jpeg = Screenshot.blankJPEG()
        check("blank image", jpeg.count > 100, "\(jpeg.count) bytes")

        print("test connection (OpenAI-compatible)…")
        state.settings.providerID = "custom"
        state.settings.customBaseURL = base
        state.settings.models["custom"] = "mock-model"
        let r1 = await state.testConnection()
        check("test connection, OpenAI-compatible", r1.hasPrefix("✓"), r1)

        print("Claude request format…")
        var req = state.request(prompt: "hi", image: jpeg)
        req.provider = Provider.with(id: "claude")
        req.baseURL = base
        req.apiKey = "test"
        req.model = "claude-opus-5-5"
        do {
            let text = try await AIClient.ask(req)
            check("Claude format", text == "OK", text)
        } catch {
            check("Claude format", false, error.localizedDescription)
        }

        print("missing key…")
        state.settings.providerID = "groq"
        let r2 = await state.testConnection()
        check("missing key gives a message", r2.hasPrefix("✗"), r2)

        print("blinking on menu bar icon…")
        state.settings.output = .menuBar
        state.settings.wpm = 240
        await state.blink("SOS")
        check("blink finished", state.phase == .idle)

        do {
            let led = try CapsLockLED()
            led.begin()
            led.end()
            print("INFO caps lock control available")
        } catch {
            print("INFO caps lock:", error.localizedDescription)
        }
    }
}
