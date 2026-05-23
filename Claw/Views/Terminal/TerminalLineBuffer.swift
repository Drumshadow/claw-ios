import Foundation

struct TerminalLine: Identifiable, Equatable {
    let id: UUID
    let raw: String          // original with ANSI codes
    let timestamp: Date
    // Pre-computed at init so repeated accesses (search, timestamps display,
    // export) pay the ANSI-strip cost only once per line.
    let plainText: String

    init(raw: String, timestamp: Date = Date()) {
        self.id = UUID()
        self.raw = raw
        self.timestamp = timestamp

        // Strip ANSI escape sequences for search and display purposes.
        var result = ""
        var inEscape = false
        for char in raw {
            if char == "\u{1B}" {
                inEscape = true
            } else if inEscape {
                if char.isLetter { inEscape = false }
            } else {
                result.append(char)
            }
        }
        self.plainText = result
    }
}

@Observable
@MainActor
final class TerminalLineBuffer {
    private(set) var lines: [TerminalLine] = []
    let maxLines: Int

    init(maxLines: Int = 10_000) {
        self.maxLines = maxLines
    }

    func append(_ raw: String) {
        let line = TerminalLine(raw: raw)
        lines.append(line)

        // Maintain ring buffer size
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func appendBatch(_ raws: [String]) {
        let newLines = raws.map { TerminalLine(raw: $0) }
        lines.append(contentsOf: newLines)

        // Maintain ring buffer size
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
    }

    func clear() {
        lines.removeAll()
    }

    var lineCount: Int {
        lines.count
    }

    // Returns lines matching a search query (case-insensitive, strips ANSI for matching)
    func search(_ query: String) -> [TerminalLine] {
        guard !query.isEmpty else { return lines }

        let lowercaseQuery = query.lowercased()
        return lines.filter { line in
            line.plainText.lowercased().contains(lowercaseQuery)
        }
    }
}
