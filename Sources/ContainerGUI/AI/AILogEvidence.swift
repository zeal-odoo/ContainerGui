import Foundation

enum AILogEvidence {
    static func prepare(_ text: String) -> String {
        // Scan private-key boundaries before discarding old lines. Never run expressions
        // against an unbounded line supplied by a container.
        var lines: [String] = []
        var size = 0
        var privateKey = false
        text.enumerateLines { line, _ in
            let beginsKey = line.contains("-----BEGIN ") && line.contains("PRIVATE KEY-----")
            let endsKey = line.contains("-----END ") && line.contains("PRIVATE KEY-----")
            var safe: String
            if beginsKey || privateKey {
                safe = beginsKey ? "[REDACTED PRIVATE KEY]" : ""
                privateKey = !endsKey
            } else if line.utf8.count > 4_096 {
                safe = "[OMITTED LONG LOG LINE]"
            } else {
                safe = redactLine(line)
            }
            guard !safe.isEmpty else { return }
            lines.append(safe)
            size += safe.utf8.count + 1
            while size > 6_144, !lines.isEmpty {
                size -= lines.removeFirst().utf8.count + 1
            }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func redactLine(_ line: String) -> String {
        var safe = line.replacingOccurrences(of: #"(?i)^.*(?:authorization|proxy-authorization|cookie|set-cookie)\s*[:=].*$"#, with: "[REDACTED AUTH HEADER]", options: .regularExpression)
        safe = safe.replacingOccurrences(of: #"(?i)\b([a-z][a-z0-9+.-]{0,31}://)[^\s/@]+:[^\s/@]+@"#, with: "$1[REDACTED]@", options: .regularExpression)
        // A word boundary and bounded key length prevent scanning every suffix of a
        // long identifier. Classify matched keys separately from the value matcher.
        let expression = try! NSRegularExpression(pattern: #"(?i)\b([a-z_][a-z0-9_-]{0,127})[\"']?\s*[:=]\s*"#)
        let valueExpression = try! NSRegularExpression(pattern: #"(?:\"[^\"]*\"|'[^']*'|[^\s,;\"'}]+)"#)
        let matches = expression.matches(in: safe, range: NSRange(safe.startIndex..., in: safe))
        for match in matches.reversed() {
            guard let keyRange = Range(match.range(at: 1), in: safe),
                  let matchRange = Range(match.range, in: safe) else { continue }
            let key = safe[keyRange].lowercased()
            if ["password", "passwd", "secret", "token", "api_key", "api-key", "apikey", "access_key", "access-key"].contains(where: key.contains) {
                let tailRange = NSRange(matchRange.upperBound..<safe.endIndex, in: safe)
                guard let value = valueExpression.firstMatch(in: safe, options: .anchored, range: tailRange),
                      let valueRange = Range(value.range, in: safe) else { continue }
                safe.replaceSubrange(matchRange.lowerBound..<valueRange.upperBound, with: "\(safe[keyRange])=[REDACTED]")
            }
        }
        return safe
    }
}
