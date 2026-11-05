import SwiftUI

// MARK: - Kinds of clipboard content (each one gets a pasta shape)

enum ClipKind: String, Codable, CaseIterable, Hashable {
    case text, url, email, color, number, code, multiline

    /// The fun name shown on every row.
    var pastaName: String {
        switch self {
        case .text: return "Penne"
        case .url: return "Ravioli"      // stuffed with links
        case .email: return "Farfalle"   // little bow-tie letters
        case .color: return "Rotini"     // twisty rainbow
        case .number: return "Orzo"      // small and precise
        case .code: return "Spaghetti"   // obviously
        case .multiline: return "Lasagna" // layers on layers
        }
    }

    /// The plain-English name used in filter chips.
    var label: String {
        switch self {
        case .text: return "Text"
        case .url: return "Links"
        case .email: return "Emails"
        case .color: return "Colors"
        case .number: return "Numbers"
        case .code: return "Code"
        case .multiline: return "Multi-line"
        }
    }

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .url: return "link"
        case .email: return "envelope.fill"
        case .color: return "paintpalette.fill"
        case .number: return "number"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .multiline: return "text.justify"
        }
    }

    var tint: Color {
        switch self {
        case .text: return Color(red: 0.85, green: 0.55, blue: 0.10)
        case .url: return .blue
        case .email: return .purple
        case .color: return .pink
        case .number: return .green
        case .code: return .orange
        case .multiline: return .teal
        }
    }

    // MARK: Detection

    static func detect(_ raw: String) -> ClipKind {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let isMultiline = t.contains(where: { $0.isNewline })

        if !isMultiline {
            if rgb(from: t) != nil { return .color }
            if isURL(t) { return .url }
            if t.range(of: #"^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$"#,
                       options: [.regularExpression, .caseInsensitive]) != nil { return .email }
            if isNumber(t) { return .number }
        }

        let codeHints = ["{", "}", ";", "=>", "->", "func ", "def ", "const ", "let ", "var ",
                         "import ", "return ", "</", "()", "==", "#include", "SELECT ", "class "]
        let hits = codeHints.filter { t.contains($0) }.count
        if hits >= 2 { return .code }
        return isMultiline ? .multiline : .text
    }

    private static func isURL(_ t: String) -> Bool {
        guard !t.contains(" ") else { return false }
        let lower = t.lowercased()
        if lower.hasPrefix("www.") && t.count > 5 { return true }
        guard lower.hasPrefix("http://") || lower.hasPrefix("https://") else { return false }
        return URL(string: t)?.host != nil
    }

    private static func isNumber(_ t: String) -> Bool {
        guard t.count <= 40, t.contains(where: { $0.isNumber }) else { return false }
        return t.allSatisfy { "0123456789.,-+ %$€£₺".contains($0) }
    }

    /// Parses #RGB / #RRGGBB hex colors.
    static func rgb(from s: String) -> (r: Double, g: Double, b: Double)? {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix("#") else { return nil }
        t.removeFirst()
        if t.count == 3 { t = t.map { "\($0)\($0)" }.joined() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }
}

// MARK: - A single clipboard entry

struct ClipItem: Identifiable, Codable, Equatable {
    var id: UUID
    var text: String
    /// When this text was last copied or picked ("last used").
    var date: Date
    /// When this text was first copied ("date created").
    var createdAt: Date
    var appName: String?
    var bundleID: String?
    var pinned: Bool
    var copyCount: Int
    var kind: ClipKind
    var charCount: Int
    var lineCount: Int

    enum CodingKeys: String, CodingKey {
        case id, text, date, createdAt, appName, bundleID, pinned, copyCount, kind, charCount, lineCount
    }

    init(text: String, appName: String?, bundleID: String?) {
        self.id = UUID()
        self.text = text
        self.date = Date()
        self.createdAt = self.date
        self.appName = appName
        self.bundleID = bundleID
        self.pinned = false
        self.copyCount = 1
        self.kind = ClipKind.detect(text)
        self.charCount = text.count
        self.lineCount = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(omittingEmptySubsequences: false, whereSeparator: { $0.isNewline })
            .count
    }

    /// Custom decoding so history saved by older versions (without `createdAt`) still loads.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Use locals for fallbacks: `self` can't be read inside `??` before init finishes.
        let decodedText = try c.decode(String.self, forKey: .text)
        let decodedDate = try c.decode(Date.self, forKey: .date)
        id = try c.decode(UUID.self, forKey: .id)
        text = decodedText
        date = decodedDate
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? decodedDate
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        bundleID = try c.decodeIfPresent(String.self, forKey: .bundleID)
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        copyCount = try c.decodeIfPresent(Int.self, forKey: .copyCount) ?? 1
        kind = try c.decodeIfPresent(ClipKind.self, forKey: .kind) ?? ClipKind.detect(decodedText)
        charCount = try c.decodeIfPresent(Int.self, forKey: .charCount) ?? decodedText.count
        lineCount = try c.decodeIfPresent(Int.self, forKey: .lineCount) ?? 1
    }

    /// Compact single-paragraph preview for the list.
    var preview: String {
        String(text.prefix(300))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n", with: " ⏎ ")
            .replacingOccurrences(of: "\t", with: "  ")
    }

    var tooltip: String { String(text.prefix(1200)) }

    var sizeLabel: String {
        if lineCount > 1 { return "\(lineCount) lines" }
        return charCount == 1 ? "1 char" : "\(charCount) chars"
    }
}

// MARK: - Icon style

enum IconStyle: String, CaseIterable, Identifiable {
    /// Emoji in the menu bar and colorful pasta icons.
    case colorful
    /// Monochrome, native macOS menu bar look.
    case classic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .colorful: return "Colorful"
        case .classic: return "Classic"
        }
    }

    static var current: IconStyle {
        IconStyle(rawValue: UserDefaults.standard.string(forKey: "iconStyle") ?? "") ?? .colorful
    }
}

extension ClipKind {
    /// The kind's color in Colorful mode, a neutral grey in Classic mode.
    func tint(_ style: IconStyle) -> Color {
        style == .colorful ? tint : Color.secondary
    }
}

// MARK: - Sorting

enum ClipSort: String, CaseIterable, Identifiable {
    case lastUsed
    case created

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastUsed: return "Last used"
        case .created: return "Date created"
        }
    }

    static var current: ClipSort {
        ClipSort(rawValue: UserDefaults.standard.string(forKey: "sortOrder") ?? "") ?? .lastUsed
    }
}

// MARK: - Filters

enum ClipFilter: Hashable {
    case all
    case pinned
    case kind(ClipKind)
}

struct KindCount: Identifiable {
    let kind: ClipKind
    let count: Int
    var id: ClipKind { kind }
}

// MARK: - Little helpers

enum RelTime {
    static func string(_ date: Date, now: Date) -> String {
        let s = Int(max(0, now.timeIntervalSince(date)))
        if s < 10 { return "just now" }
        if s < 60 { return "\(s)s ago" }
        if s < 3600 { return "\(s / 60)m ago" }
        if s < 86_400 { return "\(s / 3600)h ago" }
        if s < 86_400 * 7 { return "\(s / 86_400)d ago" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f.string(from: date)
    }
}

enum Quips {
    static let all = [
        "Fresh copies, served hot.",
        "Al dente clipboard.",
        "Copy. Paste. Mangia! 🤌",
        "Your clipboard, but delicious.",
        "Nothing gets lost in the sauce.",
        "Twirl through your history.",
        "Made with love and ⌘C.",
        "Mamma mia, look at all these copies!",
        "Every noodle remembered.",
        "Grated fresh, just for you. 🧀",
    ]
    static func random() -> String { all.randomElement() ?? all[0] }
}

/// Builds a Text with search terms highlighted.
enum Highlighter {
    static func text(_ s: String, terms: [String]) -> Text {
        guard !terms.isEmpty else { return Text(s) }
        var marks: [Range<String.Index>] = []
        for term in terms where !term.isEmpty {
            var start = s.startIndex
            while start < s.endIndex,
                  let r = s.range(of: term, options: [.caseInsensitive, .diacriticInsensitive],
                                  range: start..<s.endIndex) {
                marks.append(r)
                start = r.upperBound
            }
        }
        guard !marks.isEmpty else { return Text(s) }
        marks.sort { $0.lowerBound < $1.lowerBound }

        var result = Text("")
        var cursor = s.startIndex
        for r in marks {
            if r.lowerBound < cursor {
                // Overlapping match: only highlight the part we haven't emitted yet.
                if r.upperBound > cursor {
                    result = result + hl(String(s[cursor..<r.upperBound]))
                    cursor = r.upperBound
                }
                continue
            }
            result = result + Text(String(s[cursor..<r.lowerBound])) + hl(String(s[r]))
            cursor = r.upperBound
        }
        return result + Text(String(s[cursor...]))
    }

    private static func hl(_ s: String) -> Text {
        Text(s).bold().foregroundColor(.orange).underline()
    }
}
