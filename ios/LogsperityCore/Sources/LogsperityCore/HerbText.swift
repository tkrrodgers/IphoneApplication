import Foundation

// Text helpers for HERB's rule-based parser (design §17): a small Python-`re`-style wrapper over
// NSRegularExpression, Python string predicates, and difflib's similarity ratio. Offsets are UTF-16, like
// NSString, and every slice goes through these helpers so ranges and strings never disagree.

/// A compiled regular expression with `search`, `match` (anchored at the start), `findAll`, `sub` and `split`.
/// NSRegularExpression is immutable and thread-safe once built.
struct Rx: @unchecked Sendable {
    let re: NSRegularExpression

    init(_ pattern: String, _ caseInsensitive: Bool = false) {
        do {
            re = try NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : [])
        } catch {
            preconditionFailure("bad HERB pattern \(pattern): \(error)")
        }
    }

    /// Python's `fullmatch`: the whole string must match.
    static func full(_ pattern: String, _ caseInsensitive: Bool = false) -> Rx { Rx("^(?:\(pattern))\\z", caseInsensitive) }

    func search(_ s: String, from: Int = 0) -> RxMatch? {
        let n = s as NSString
        guard from <= n.length else { return nil }
        return re.firstMatch(in: s, options: [], range: NSRange(location: from, length: n.length - from))
            .map { RxMatch(ns: n, r: $0) }
    }

    /// Python's `match`: anchored at `from` (the start by default).
    func match(_ s: String, from: Int = 0) -> RxMatch? {
        let n = s as NSString
        guard from <= n.length else { return nil }
        return re.firstMatch(in: s, options: [.anchored], range: NSRange(location: from, length: n.length - from))
            .map { RxMatch(ns: n, r: $0) }
    }

    func test(_ s: String) -> Bool { search(s) != nil }

    func findAll(_ s: String) -> [RxMatch] {
        let n = s as NSString
        return re.matches(in: s, options: [], range: NSRange(location: 0, length: n.length)).map { RxMatch(ns: n, r: $0) }
    }

    func sub(_ s: String, _ with: (RxMatch) -> String) -> String {
        let ms = findAll(s)
        guard !ms.isEmpty else { return s }
        var out = "", last = 0
        for m in ms {
            out += s.u16(last, m.start) + with(m)
            last = m.end
        }
        return out + s.u16(last, s.u16count)
    }

    func sub(_ s: String, _ literal: String) -> String { sub(s) { _ in literal } }

    func split(_ s: String, maxSplit: Int = 0) -> [String] {
        var out: [String] = [], last = 0, n = 0
        for m in findAll(s) {
            if maxSplit > 0 && n >= maxSplit { break }
            out.append(s.u16(last, m.start))
            last = m.end
            n += 1
        }
        out.append(s.u16(last, s.u16count))
        return out
    }
}

struct RxMatch {
    let ns: NSString
    let r: NSTextCheckingResult

    subscript(_ i: Int) -> String? {
        guard i < r.numberOfRanges else { return nil }
        let g = r.range(at: i)
        return g.location == NSNotFound ? nil : ns.substring(with: g)
    }

    var start: Int { r.range.location }
    var end: Int { r.range.location + r.range.length }
    func start(_ i: Int) -> Int { r.range(at: i).location }
    func end(_ i: Int) -> Int { r.range(at: i).location + r.range(at: i).length }
}

/// `re.search(pattern, text, re.I)` for one-off patterns.
func rxSearch(_ pattern: String, _ text: String, ci: Bool = true) -> RxMatch? { Rx(pattern, ci).search(text) }
func rxTest(_ pattern: String, _ text: String, ci: Bool = true) -> Bool { Rx(pattern, ci).search(text) != nil }
func rxSub(_ pattern: String, _ text: String, _ with: String, ci: Bool = true) -> String { Rx(pattern, ci).sub(text, with) }

extension String {
    var u16count: Int { (self as NSString).length }

    /// Slice by UTF-16 offsets, clamped.
    func u16(_ a: Int, _ b: Int) -> String {
        let n = u16count
        let lo = max(0, min(a, n)), hi = max(lo, min(b, n))
        return (self as NSString).substring(with: NSRange(location: lo, length: hi - lo))
    }

    func u16(from a: Int) -> String { u16(a, u16count) }
    func u16(to b: Int) -> String { u16(0, b) }

    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    func strip(_ chars: String) -> String { trimmingCharacters(in: CharacterSet(charactersIn: chars)) }
    func rstrip(_ chars: String) -> String {
        var s = self
        while let c = s.last, chars.contains(c) { s.removeLast() }
        return s
    }

    /// Python's `str.split()`.
    var words: [String] { split(whereSeparator: \.isWhitespace).map(String.init) }

    var pyIsLower: Bool { contains { $0.isLowercase } && !contains { $0.isUppercase } }
    var pyIsUpper: Bool { contains { $0.isUppercase } && !contains { $0.isLowercase } }
    var pyIsAlpha: Bool { !isEmpty && allSatisfy(\.isLetter) }
    var pyCapitalize: String { prefix(1).uppercased() + dropFirst().lowercased() }
    /// Python's `str.title()`: a letter after a non-letter is uppercased, the rest lowercased.
    var pyTitle: String {
        var out = "", prevLetter = false
        for ch in self {
            out += prevLetter ? ch.lowercased() : ch.uppercased()
            prevLetter = ch.isLetter
        }
        return out
    }
    /// First character upper-cased, the rest unchanged.
    var upperFirst: String { prefix(1).uppercased() + dropFirst() }
}

/// difflib.SequenceMatcher(None, a, b).ratio() (no junk heuristic; HERB only compares short words).
func similarity(_ a: String, _ b: String) -> Double {
    let a = Array(a), b = Array(b)
    guard !a.isEmpty || !b.isEmpty else { return 1 }
    var b2j: [Character: [Int]] = [:]
    for (j, ch) in b.enumerated() { b2j[ch, default: []].append(j) }
    func longest(_ alo: Int, _ ahi: Int, _ blo: Int, _ bhi: Int) -> (Int, Int, Int) {
        var (bi, bj, size) = (alo, blo, 0)
        var lens: [Int: Int] = [:]
        for i in alo..<ahi {
            var next: [Int: Int] = [:]
            for j in b2j[a[i]] ?? [] {
                if j < blo { continue }
                if j >= bhi { break }
                let k = (lens[j - 1] ?? 0) + 1
                next[j] = k
                if k > size { (bi, bj, size) = (i - k + 1, j - k + 1, k) }
            }
            lens = next
        }
        return (bi, bj, size)
    }
    var matches = 0
    var queue = [(0, a.count, 0, b.count)]
    while let (alo, ahi, blo, bhi) = queue.popLast() {
        guard alo < ahi, blo < bhi else { continue }
        let (i, j, k) = longest(alo, ahi, blo, bhi)
        guard k > 0 else { continue }
        matches += k
        queue.append((alo, i, blo, j))
        queue.append((i + k, ahi, j + k, bhi))
    }
    return 2 * Double(matches) / Double(a.count + b.count)
}

/// "a", "a and b", "a, b and c".
func joinAnd(_ items: [String?]) -> String {
    let items = items.compactMap { $0 }.filter { !$0.isEmpty }
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    default: return items.dropLast().joined(separator: ", ") + " and " + items.last!
    }
}

/// Python's `round()` (half to even).
func pyRound(_ x: Double) -> Double { x.rounded(.toNearestOrEven) }

/// Python's `f"{x:g}"`.
func gFormat(_ x: Double) -> String { String(format: "%g", x) }

/// Compiles a keyword table: [(pattern, value)] → [(Rx, value)].
func rxTable<T>(_ rows: [(String, T)], ci: Bool = false) -> [(Rx, T)] { rows.map { (Rx($0.0, ci), $0.1) } }
