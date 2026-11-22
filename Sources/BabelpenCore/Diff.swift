import Foundation

/// Word-level diff between the original text and the corrected one.
public enum Diff {
    public enum Op: Equatable {
        case same(String)
        case delete(String)
        case insert(String)
    }

    /// Words (letters, digits, apostrophes), runs of whitespace, or single symbols.
    public static func tokens(_ s: String) -> [String] {
        let ns = s as NSString
        return tokenRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    private static let tokenRegex = try! NSRegularExpression(
        pattern: "\\s+|[\\p{L}\\p{N}'’_]+|.", options: [.dotMatchesLineSeparators])

    /// LCS over tokens, then adjacent edits are merged so "a b" → "c d" reads as
    /// one replacement instead of interleaved fragments.
    public static func diff(_ a: String, _ b: String) -> [Op] {
        let x = tokens(a), y = tokens(b)
        let n = x.count, m = y.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0, m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    dp[i][j] = x[i] == y[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
                }
            }
        }
        var raw: [Op] = []
        var i = 0, j = 0
        while i < n || j < m {
            if i < n, j < m, x[i] == y[j] { raw.append(.same(x[i])); i += 1; j += 1 }
            else if j < m, i == n || dp[i][j + 1] >= dp[i + 1][j] { raw.append(.insert(y[j])); j += 1 }
            else { raw.append(.delete(x[i])); i += 1 }
        }

        var merged: [Op] = []
        var del = "", ins = ""
        func flush() {
            // Whitespace that both sides end with is unchanged text, not part of the edit.
            var tail = ""
            while let a = del.last, let b = ins.last, a == b, a.isWhitespace {
                tail = String(a) + tail
                del.removeLast(); ins.removeLast()
            }
            if !del.isEmpty { merged.append(.delete(del)) }
            if !ins.isEmpty { merged.append(.insert(ins)) }
            if !tail.isEmpty { merged.append(.same(tail)) }
            del = ""; ins = ""
        }
        for op in raw {
            switch op {
            case .delete(let t): del += t
            case .insert(let t): ins += t
            case .same(let t):
                // A single space between two edits belongs to the edit.
                if !del.isEmpty || !ins.isEmpty, t == " " { del += t; ins += t }
                else { flush(); merged.append(.same(t)) }
            }
        }
        flush()
        return merged
    }

    /// Number of separate places that changed.
    public static func changeCount(_ ops: [Op]) -> Int {
        var count = 0, inChange = false
        for op in ops {
            if case .same = op { inChange = false }
            else if !inChange { count += 1; inChange = true }
        }
        return count
    }

    /// Long unchanged stretches collapse to "…" so the suggestion card stays small.
    public static func compact(_ ops: [Op], context: Int = 40) -> [Op] {
        ops.enumerated().map { i, op in
            guard case .same(let t) = op, t.count > context * 2 + 10 else { return op }
            if i == 0 { return .same("…" + t.suffix(context)) }
            if i == ops.count - 1 { return .same(t.prefix(context) + "…") }
            return .same(t.prefix(context) + " … " + t.suffix(context))
        }
    }
}
