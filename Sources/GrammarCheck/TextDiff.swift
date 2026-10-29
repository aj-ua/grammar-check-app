import SwiftUI

struct DiffSegment: Equatable {
    enum Kind { case equal, inserted, deleted }
    let kind: Kind
    var text: String
}

/// Word-level diff (Myers, via CollectionDifference) rendered as an AttributedString.
enum TextDiff {
    /// Tokens: runs of word characters, runs of whitespace, single punctuation characters.
    /// Concatenating tokens reproduces the input exactly.
    static func tokenize(_ s: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentClass = -1
        for ch in s {
            let cls: Int
            if ch.isWhitespace { cls = 0 }
            else if ch.isLetter || ch.isNumber || ch == "'" || ch == "\u{2019}" { cls = 1 }
            else { cls = 2 }

            if cls == currentClass && cls != 2 {
                current.append(ch)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = String(ch)
                currentClass = cls
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    static func diff(old: String, new: String) -> [DiffSegment] {
        let a = tokenize(old)
        let b = tokenize(new)
        let changes = b.difference(from: a)

        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in changes {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var segs: [DiffSegment] = []
        func push(_ kind: DiffSegment.Kind, _ text: String) {
            if let last = segs.last, last.kind == kind {
                segs[segs.count - 1].text += text
            } else {
                segs.append(DiffSegment(kind: kind, text: text))
            }
        }

        var i = 0, j = 0
        while i < a.count || j < b.count {
            if i < a.count, removed.contains(i) {
                push(.deleted, a[i]); i += 1
            } else if j < b.count, inserted.contains(j) {
                push(.inserted, b[j]); j += 1
            } else {
                if j < b.count { push(.equal, b[j]) }
                i += 1; j += 1
            }
        }
        return mergeChangeRuns(segs)
    }

    /// "del A, ' ', ins B, del C, ' ', ins D" reads badly. When a run of changes contains
    /// both deletions and insertions and is separated only by whitespace, show it as one
    /// "old phrase → new phrase" pair.
    private static func mergeChangeRuns(_ segs: [DiffSegment]) -> [DiffSegment] {
        var out: [DiffSegment] = []
        var k = 0
        while k < segs.count {
            if segs[k].kind == .equal {
                out.append(segs[k]); k += 1; continue
            }

            var end = k
            var lastChange = k
            while end < segs.count {
                let s = segs[end]
                if s.kind == .equal {
                    if s.text.allSatisfy(\.isWhitespace), end + 1 < segs.count, segs[end + 1].kind != .equal {
                        end += 1; continue
                    }
                    break
                }
                lastChange = end
                end += 1
            }

            let run = segs[k...lastChange]
            let hasDel = run.contains { $0.kind == .deleted }
            let hasIns = run.contains { $0.kind == .inserted }

            if hasDel && hasIns {
                var del = "", ins = ""
                for s in run {
                    switch s.kind {
                    case .deleted: del += s.text
                    case .inserted: ins += s.text
                    case .equal: del += s.text; ins += s.text
                    }
                }
                out.append(DiffSegment(kind: .deleted, text: del))
                out.append(DiffSegment(kind: .inserted, text: ins))
            } else {
                out.append(contentsOf: run)
            }
            k = lastChange + 1
        }
        return out
    }

    static func attributed(_ segs: [DiffSegment]) -> AttributedString {
        typealias UI = AttributeScopes.SwiftUIAttributes
        var out = AttributedString()
        for s in segs {
            var piece = AttributedString(s.text)
            switch s.kind {
            case .equal:
                break
            case .deleted:
                piece[UI.ForegroundColorAttribute.self] = Color(nsColor: .systemRed)
                piece[UI.BackgroundColorAttribute.self] = Color(nsColor: .systemRed).opacity(0.12)
                piece[UI.StrikethroughStyleAttribute.self] = .single
            case .inserted:
                piece[UI.ForegroundColorAttribute.self] = Color(nsColor: .systemGreen)
                piece[UI.BackgroundColorAttribute.self] = Color(nsColor: .systemGreen).opacity(0.15)
            }
            out += piece
        }
        return out
    }

    static func changeCount(_ segs: [DiffSegment]) -> Int {
        // A deleted+inserted pair counts as one change.
        var count = 0
        var prev: DiffSegment.Kind = .equal
        for s in segs {
            if s.kind == .deleted || (s.kind == .inserted && prev != .deleted) { count += 1 }
            prev = s.kind
        }
        return count
    }
}
