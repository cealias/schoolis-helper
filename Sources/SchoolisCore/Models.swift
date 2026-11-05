import Foundation

// MARK: - 学校的时间

/// 接口里的时间都是北京时间，格式像 "2026-10-05T07:38:00"，有时后面带小数秒。
public enum SchoolTime {
    public static let zone = TimeZone(identifier: "Asia/Shanghai")!

    public static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.firstWeekday = 2 // 一周从周一开始
        return c
    }

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    public static func parse(_ text: String?) -> Date? {
        guard let text, text.count >= 19 else { return nil }
        return parser.date(from: String(text.prefix(19)))
    }
}

// MARK: - 宽容解码

/// 学校接口的字段类型不稳定：同一个字段有时是数字、有时是字符串、有时是 null。
/// 严格解码的话，一个字段不对，整个列表就全读不出来了。所以统一用这几个「宽容」版本：读不出来就当作没有。
extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return String(format: "%g", d) }
        return nil
    }

    func lenientDouble(_ key: Key) -> Double? {
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return d }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Double(s) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        lenientDouble(key).map { Int($0) }
    }

    func lenientBool(_ key: Key) -> Bool? {
        if let b = try? decodeIfPresent(Bool.self, forKey: key) { return b }
        if let i = lenientInt(key) { return i != 0 }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s.lowercased() == "true" }
        return nil
    }
}

/// 接口统一外壳 { "data": ... } 里的 data。
struct DataWrapper<T: Decodable>: Decodable {
    let data: T
}

extension Envelope {
    /// 把 data 部分解码成指定的类型。
    public func decoded<T: Decodable>(_ type: T.Type) throws -> T {
        do {
            return try JSONDecoder().decode(DataWrapper<T>.self, from: raw).data
        } catch {
            throw SchoolisError("数据格式和预想的不一样（\(T.self)），学校网站可能改版了。")
        }
    }
}

// MARK: - 学期

public struct Semester: Decodable {
    public let id: Int
    public let name: String
    public let isNow: Bool
    /// 学期开始那天，比如 "2026-08-11"（统计考勤用）
    public let startDate: String

    enum CodingKeys: String, CodingKey { case id, name, isNow, startDate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenientInt(.id) ?? 0
        name = c.lenientString(.name) ?? ""
        isNow = c.lenientBool(.isNow) ?? false
        startDate = String((c.lenientString(.startDate) ?? "").prefix(10))
    }
}

// MARK: - 学习任务（作业、测验、小结……）

/// 一条学习任务。字段名和学校接口保持一致，所以既能从接口读，也能原样存到本地快照里。
///
/// 状态的含义已经在网页上核对过（2026-10-06）：
/// - finishState：nil = 还没交，1 = 已完成，2 = 未完成（老师判定没交），3 = 延迟完成
/// - learningTaskState：2 = 进行中，4 = 已批改，5 = 已交、等批改
/// 注意：「我的回答」那一栏没用。线下交的纸质作业，那里永远是空的。
public struct LearningTask: Codable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let subjectName: String
    public let typeName: String
    /// 布置（开始）时间。老师事后建的「登分格子」，开始时间和截止时间一模一样
    public let beginTime: String?
    public let endTime: String?
    public let score: Double?
    public let totalScore: Double?
    public let finishState: Int?
    public let learningTaskState: Int?
    public let isExempt: Bool
    public let teacher: String
    /// 统一以后的类型（测验考试、作业练习……），读数据时算好，见 TaskCategory
    public let category: TaskCategory
    /// 怎么完成的（要交 / 课上考 / 课上检查 / 课上展示……），读数据时算好，见 TaskMode
    public let mode: TaskMode

    enum CodingKeys: String, CodingKey {
        case id, name, subjectName, typeName, beginTime, endTime, score, totalScore
        case finishState, learningTaskState, isExempt
        case teacher = "lastEditorName"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.lenientInt(.id) else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "任务没有 id")
        }
        self.id = id
        // 老师写标题时常常多打空格，去掉
        name = (c.lenientString(.name) ?? "（没有标题）").trimmingCharacters(in: .whitespacesAndNewlines)
        subjectName = c.lenientString(.subjectName) ?? "（未知科目）"
        typeName = c.lenientString(.typeName) ?? ""
        beginTime = c.lenientString(.beginTime)
        endTime = c.lenientString(.endTime)
        score = c.lenientDouble(.score)
        totalScore = c.lenientDouble(.totalScore)
        finishState = c.lenientInt(.finishState)
        learningTaskState = c.lenientInt(.learningTaskState)
        isExempt = c.lenientBool(.isExempt) ?? false
        teacher = c.lenientString(.teacher) ?? ""
        category = TaskCategory.of(name: name, typeName: typeName)
        mode = TaskMode.of(name: name, typeName: typeName, category: category,
                           begin: SchoolTime.parse(beginTime), end: SchoolTime.parse(endTime))
    }

    /// 截止时间。解析不了就是 nil。
    public var endDate: Date? { SchoolTime.parse(endTime) }
}

/// 任务列表的一页。
///
/// 防范措施：某一条任务读不懂时，跳过它并记下数量，不让它拖累整页。
/// 同步时会拿「读到的 + 跳过的」去和服务器给的总数比，少了就报错。
public struct TaskPage: Decodable {
    public let totalCount: Int
    public let list: [LearningTask]
    public let skipped: Int

    enum CodingKeys: String, CodingKey { case totalCount, list }

    /// 什么都不读，只用来让解码器「跳过」读不懂的那一条。
    private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalCount = c.lenientInt(.totalCount) ?? 0
        var items: [LearningTask] = []
        var skipped = 0
        if var array = try? c.nestedUnkeyedContainer(forKey: .list) {
            while !array.isAtEnd {
                if let task = try? array.decode(LearningTask.self) {
                    items.append(task)
                } else {
                    _ = try? array.decode(Skip.self)
                    skipped += 1
                }
            }
        }
        list = items
        self.skipped = skipped
    }

    /// 从探针存下来的原始文件（完整的接口返回）里读一页。
    public static func fromRaw(_ data: Data) throws -> TaskPage {
        try JSONDecoder().decode(DataWrapper<TaskPage>.self, from: data).data
    }
}

// MARK: - 本地快照

/// 一次同步的结果，存在本地。断网、学校网站挂了的时候，App 照样能显示上一次的数据。
public struct Snapshot: Codable {
    public var syncedAt: Date
    public var semesterName: String
    /// 学校官网显示的动态 GPA
    public var gpa: Double?
    public var tasks: [LearningTask]
    /// 有几条任务读不懂、被跳过了。正常应该是 0。
    public var unreadableTasks: Int

    // 下面几项是后来加的。旧的快照文件里没有，读出来就是 nil，不影响使用。
    /// 各科成绩和成绩构成
    public var grades: GradeData?
    /// 本周和下周的课表
    public var schedule: [ScheduleEntry]?
    /// 本学期的考勤
    public var attendance: AttendanceSummary?
    /// 每个作业算在成绩构成的哪个项目里：作业 id → 项目 id（来自作业详情，读过一次就存下来）
    public var taskItems: [String: [Int]]?
}
