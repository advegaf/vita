import Foundation

/// Deterministic JSON with AUTHORED key order. Swift `[String: Any]` +
/// JSONSerialization emits keys in per-launch hash order — and the tool schema's
/// field order is rendered into the model's context, where a scrambled order was
/// observed (live, reproducibly) to destabilize long constrained tool outputs into
/// markup-leak degeneration. Everything the labs vision request sends goes through
/// this so the wire bytes are canonical.
indirect enum OrderedJSON: Sendable {
    case object([(String, OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null

    var serialized: String {
        switch self {
        case .object(let pairs):
            return "{" + pairs.map { "\"\(Self.escape($0.0))\":\($0.1.serialized)" }.joined(separator: ",") + "}"
        case .array(let items):
            return "[" + items.map(\.serialized).joined(separator: ",") + "]"
        case .string(let s):
            return "\"\(Self.escape(s))\""
        case .int(let i):
            return String(i)
        case .double(let d):
            return d == d.rounded() && abs(d) < 1e15 ? String(Int(d)) : String(d)
        case .bool(let b):
            return b ? "true" : "false"
        case .null:
            return "null"
        }
    }

    func data() -> Data { Data(serialized.utf8) }

    static func escape(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            switch c {
            case "\"": out.append(contentsOf: "\\\"".unicodeScalars)
            case "\\": out.append(contentsOf: "\\\\".unicodeScalars)
            case "\n": out.append(contentsOf: "\\n".unicodeScalars)
            case "\r": out.append(contentsOf: "\\r".unicodeScalars)
            case "\t": out.append(contentsOf: "\\t".unicodeScalars)
            default:
                if c.value < 0x20 {
                    out.append(contentsOf: String(format: "\\u%04x", c.value).unicodeScalars)
                } else {
                    out.append(c)
                }
            }
        }
        return String(out)
    }
}
