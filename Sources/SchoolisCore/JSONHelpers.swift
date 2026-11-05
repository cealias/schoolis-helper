import Foundation

/// 学校接口返回的 JSON 字段类型不稳定：数字有时是字符串，有时是 null，嵌套的列表有时干脆没有。
/// 这几个函数统一「宽容地读」：读不出来就当没有，不让一个怪字段把整份数据搞崩。
enum J {
    static func string(_ value: Any?) -> String? {
        if let s = value as? String { return s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    static func double(_ value: Any?) -> Double? {
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) }
        return nil
    }

    static func int(_ value: Any?) -> Int? {
        double(value).map { Int($0) }
    }

    static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let n = value as? NSNumber { return n.intValue != 0 }
        if let s = value as? String { return s.lowercased() == "true" }
        return nil
    }

    static func dict(_ value: Any?) -> [String: Any] {
        value as? [String: Any] ?? [:]
    }

    static func array(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }
}
