import Foundation

/// A user-editable blink code (Morse or anything else), loaded from JSON.
///
///     symbols      {".": 1, "-": 3}   symbol -> how many time units the LED is ON
///     symbol_gap   OFF units between symbols inside one character
///     letter_gap   OFF units between characters
///     word_gap     OFF units between words
///     table        {"A": ".-", ...}   character -> symbols
///     words        {"YES": "l"}       optional whole-word shortcuts (checked first)
///     prefix / suffix                 optional symbols sent before / after every message
///     ai_instructions                 optional extra instruction for the AI
struct SignalCode: Decodable, Identifiable, Hashable {
    var id: String { name }
    var name: String
    var description: String
    var symbols: [String: Int]
    var symbolGap: Int
    var letterGap: Int
    var wordGap: Int
    var prefix: String
    var suffix: String
    var caseSensitive: Bool
    var table: [String: String]
    var words: [String: String]
    var aiInstructions: String
    var fileURL: URL?

    struct Step: Equatable {
        let on: Bool
        let units: Int
    }

    enum CodingKeys: String, CodingKey {
        case name, description, symbols, prefix, suffix, table, words
        case symbolGap = "symbol_gap", letterGap = "letter_gap", wordGap = "word_gap"
        case caseSensitive = "case_sensitive", aiInstructions = "ai_instructions"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        symbols = try c.decode([String: Int].self, forKey: .symbols)
        symbolGap = try c.decodeIfPresent(Int.self, forKey: .symbolGap) ?? 1
        letterGap = try c.decodeIfPresent(Int.self, forKey: .letterGap) ?? 3
        wordGap = try c.decodeIfPresent(Int.self, forKey: .wordGap) ?? 7
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        suffix = try c.decodeIfPresent(String.self, forKey: .suffix) ?? ""
        caseSensitive = try c.decodeIfPresent(Bool.self, forKey: .caseSensitive) ?? false
        table = try c.decodeIfPresent([String: String].self, forKey: .table) ?? [:]
        words = try c.decodeIfPresent([String: String].self, forKey: .words) ?? [:]
        aiInstructions = try c.decodeIfPresent(String.self, forKey: .aiInstructions) ?? ""
        try validate()
    }

    static func load(from url: URL) throws -> SignalCode {
        var code = try JSONDecoder().decode(SignalCode.self, from: Data(contentsOf: url))
        code.fileURL = url
        return code
    }

    func validate() throws {
        for (symbol, units) in symbols where symbol.count != 1 || units <= 0 {
            throw CodeError("Symbol \"\(symbol)\" must be one character with a positive ON time.")
        }
        var sequences = table.merging(words) { a, _ in a }
        sequences["prefix"] = prefix
        sequences["suffix"] = suffix
        for (key, seq) in sequences {
            if let bad = seq.first(where: { symbols[String($0)] == nil }) {
                throw CodeError("\"\(key)\" uses \"\(bad)\", which isn't in symbols.")
            }
        }
    }

    private func norm(_ s: String) -> String { caseSensitive ? s : s.uppercased() }

    private var normTable: [String: String] {
        Dictionary(table.map { (norm($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    private var normWords: [String: String] {
        Dictionary(words.map { (norm($0.key), $0.value) }, uniquingKeysWith: { a, _ in a })
    }

    /// Characters the AI may use (shown in its instructions).
    var allowedCharacters: String { table.keys.sorted().joined() }

    /// Drop anything this code can't show and collapse whitespace.
    func sanitize(_ text: String) -> String {
        let table = normTable, words = normWords
        var out: [String] = []
        for word in text.split(whereSeparator: \.isWhitespace) {
            let w = norm(String(word))
            let bare = w.trimmingCharacters(in: CharacterSet(charactersIn: ".,!?;:'\"()"))
            if words[bare] != nil {
                out.append(bare)
                continue
            }
            let kept = w.filter { table[String($0)] != nil }
            if !kept.isEmpty { out.append(kept) }
        }
        return out.joined(separator: " ")
    }

    /// Text -> words -> per-letter symbol sequences.
    func encode(_ text: String) -> [[String]] {
        let table = normTable, words = normWords
        return sanitize(text).split(separator: " ").map { word -> [String] in
            if let seq = words[String(word)] { return [seq] }
            return word.compactMap { table[String($0)] }
        }
    }

    /// Text -> LED on/off steps, including prefix/suffix framing.
    func timeline(_ text: String) -> [Step] {
        var words = encode(text)
        if !prefix.isEmpty { words.insert([prefix], at: 0) }
        if !suffix.isEmpty { words.append([suffix]) }

        var steps: [Step] = []
        for (wi, letters) in words.enumerated() {
            if wi > 0 { steps.append(Step(on: false, units: wordGap)) }
            for (li, seq) in letters.enumerated() {
                if li > 0 { steps.append(Step(on: false, units: letterGap)) }
                for (si, symbol) in seq.enumerated() {
                    if si > 0 { steps.append(Step(on: false, units: symbolGap)) }
                    steps.append(Step(on: true, units: symbols[String(symbol)] ?? 1))
                }
            }
        }
        return steps
    }

    /// e.g. ".... .. / - .... . .-. ."
    func pretty(_ text: String) -> String {
        encode(text).map { $0.joined(separator: " ") }.joined(separator: " / ")
    }

    /// PARIS standard: one unit = 1.2 / WPM seconds.
    static func unitSeconds(wpm: Double) -> Double { 1.2 / max(wpm, 1) }
}

struct CodeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Codes live as JSON files in ~/Library/Application Support/Morse Eye/Codes
/// so they can be edited in any text editor. Built-ins are written there on first launch.
enum CodeLibrary {
    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Morse Eye/Codes", isDirectory: true)
    }

    static func installBuiltIns() {
        let fm = FileManager.default
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        for (file, json) in BuiltInCodes.files {
            let url = folder.appendingPathComponent(file)
            if !fm.fileExists(atPath: url.path) {
                try? json.data(using: .utf8)?.write(to: url)
            }
        }
    }

    /// Returns all valid codes plus a list of problems with invalid files.
    static func loadAll() -> (codes: [SignalCode], problems: [String]) {
        installBuiltIns()
        var codes: [SignalCode] = [], problems: [String] = []
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for url in files.filter({ $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            do { codes.append(try SignalCode.load(from: url)) } catch {
                problems.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if codes.isEmpty, let morse = try? JSONDecoder().decode(SignalCode.self, from: Data(BuiltInCodes.morse.utf8)) {
            codes = [morse]
        }
        return (codes, problems)
    }

    /// Copy an existing code to a new file the user can edit.
    static func duplicate(_ code: SignalCode) -> URL? {
        guard let source = code.fileURL else { return nil }
        var n = 1
        var url: URL
        repeat {
            url = folder.appendingPathComponent("My Code \(n).json")
            n += 1
        } while FileManager.default.fileExists(atPath: url.path)
        guard var text = try? String(contentsOf: source, encoding: .utf8) else { return nil }
        text = text.replacingOccurrences(of: "\"name\": \"\(code.name)\"", with: "\"name\": \"My Code \(n - 1)\"")
        try? text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

enum BuiltInCodes {
    static let files: [(String, String)] = [("Morse.json", morse), ("Simple Signals.json", simple)]

    static let morse = """
    {
      "name": "International Morse",
      "description": "Standard ITU Morse. Dot = 1 unit on, dash = 3 units on.",
      "symbols": { ".": 1, "-": 3 },
      "symbol_gap": 1,
      "letter_gap": 3,
      "word_gap": 7,
      "prefix": "-.-.-",
      "suffix": ".-.-.",
      "case_sensitive": false,
      "table": {
        "A": ".-",    "B": "-...",  "C": "-.-.",  "D": "-..",   "E": ".",
        "F": "..-.",  "G": "--.",   "H": "....",  "I": "..",    "J": ".---",
        "K": "-.-",   "L": ".-..",  "M": "--",    "N": "-.",    "O": "---",
        "P": ".--.",  "Q": "--.-",  "R": ".-.",   "S": "...",   "T": "-",
        "U": "..-",   "V": "...-",  "W": ".--",   "X": "-..-",  "Y": "-.--",
        "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "'": ".----.", "!": "-.-.--",
        "/": "-..-.",  "(": "-.--.",  ")": "-.--.-", "&": ".-...",  ":": "---...",
        ";": "-.-.-.", "=": "-...-",  "+": ".-.-.",  "-": "-....-", "@": ".--.-."
      }
    }
    """

    static let simple = """
    {
      "name": "Simple Signals",
      "description": "Short blink (s), long blink (l), hold (h). Whole-word answers plus numbers.",
      "symbols": { "s": 1, "l": 4, "h": 8 },
      "symbol_gap": 1,
      "letter_gap": 4,
      "word_gap": 10,
      "words": {
        "YES": "l",
        "NO": "ss",
        "MAYBE": "sls",
        "ERROR": "h",
        "DONE": "llll"
      },
      "table": {
        "1": "s",  "2": "ss",  "3": "sss",  "4": "ssss",  "5": "l",
        "6": "ls", "7": "lss", "8": "lsss", "9": "lssss", "0": "ll"
      },
      "ai_instructions": "Answer with exactly one of: YES, NO, MAYBE, ERROR, DONE, or a number."
    }
    """
}
