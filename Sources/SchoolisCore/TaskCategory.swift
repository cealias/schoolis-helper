import Foundation

/// 作业的「类型」，统一成几大类。
///
/// 为什么不直接用老师填的类型（typeName）：
/// 1. 有的老师写中文（「家庭作业」「小测试」），有的写英文（「General Homework」「Quiz」），同一类东西有好几种叫法；
/// 2. 老师填的类型经常不准：「每周小结」里有测验、有练习册、有课堂表现，「动手操作」里有英语测验和科学考试。
/// 所以先看作业名里的关键词（Quiz、Test、听写、出勤……），看不出来再按老师填的类型归类。
/// 列表里每一行仍然会写出老师原来填的类型，分错了也能看出来。
public enum TaskCategory: String, CaseIterable, Hashable, Sendable {
    case quiz, homework, project, participation, attendance, other

    public var title: String {
        switch self {
        case .quiz: return "测验考试"
        case .homework: return "作业练习"
        case .project: return "项目作品"
        case .participation: return "课堂表现"
        case .attendance: return "考勤"
        case .other: return "其他类型"
        }
    }

    /// 课堂表现、考勤：分数是老师打的，你没有东西可交，也没法「补交、重做」
    public var isTeacherRecorded: Bool { self == .participation || self == .attendance }

    public static func of(name: String, typeName: String) -> TaskCategory {
        if let byName = keywords(in: name) { return byName }
        let type = typeName.trimmingCharacters(in: .whitespaces)
        if let known = byType[type.lowercased()] { return known }
        // 以后出现没见过的类型名（比如「Homework Check」），也按关键词猜一下
        return keywords(in: type) ?? .other
    }

    /// 作业名里的关键词。顺序有讲究：
    /// 「Participation Quiz」先算课堂表现；「Quiz Workbook」先算测验；
    /// 但「听写、默写」比「作业」弱：「提交古诗默写单」是作业，「词语听写大挑战成绩」才是测验。
    /// 体育老师用繁体字，所以常用词都带上繁体写法。
    private static func keywords(in text: String) -> TaskCategory? {
        let t = text.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        // 英文单词要整词匹配：不然「protest」里也有 test。下划线、数字算分隔（「Wk2_Quiz_WYTAT」）
        func word(_ pattern: String) -> Bool {
            t.range(of: "(?<![a-z])(\(pattern))(?![a-z])", options: .regularExpression) != nil
        }
        if has(["attendance", "出勤", "考勤"]) { return .attendance }
        if has(["participation", "课堂表现", "課堂表現", "课堂参与", "課堂參與", "discussion", "seminar", "讨论", "討論"]) {
            return .participation
        }
        if has(["quiz", "assessment", "测验", "測驗", "测试", "測試", "考试", "考試", "测评", "測評"]) || word("tests?|exams?") {
            return .quiz
        }
        if has(["project", "presentation", "项目", "項目", "展示"]) { return .project }
        if has(["homework", "workbook", "worksheet", "notebook", "warm up", "作业", "作業", "练习", "練習", "练笔", "背诵", "探究单"])
            || word("wks|hw") {
            return .homework
        }
        if has(["听写", "聽寫", "默写", "默寫", "progress check", "单元评估"]) { return .quiz }
        return nil
    }

    /// 老师填的类型 → 大类（2026-10 学期里出现过的全部 27 种；键都是小写）
    private static let byType: [String: TaskCategory] = [
        "quiz": .quiz, "小测试": .quiz, "vocabulary": .quiz, "progress check": .quiz, "体育单元评估": .quiz,
        "家庭作业": .homework, "作业": .homework, "general homework": .homework, "notebooks/hw": .homework,
        "general classwork": .homework, "平时成绩": .homework, "每周小结": .homework, "名著阅读": .homework,
        "动手操作": .project, "summative projects": .project, "project work": .project,
        "project or presentation": .project, "项目学习及展示": .project,
        "课堂参与度": .participation, "课堂表现": .participation, "参加": .participation,
        "class discussion": .participation, "过程性评价": .participation,
        "中学考勤": .attendance, "attendance": .attendance,
        "学习习惯": .other, "默认类型": .other,
    ]
}

/// 一个任务「是怎么完成的」。决定两件事：
/// 1. 过了截止、系统里还没分数时，算不算「可能没交」——只有要交东西的（submit）才算；
///    课上考的、课上检查的、课上展示的、老师打分的，过了时间没分数只是老师还没登分。
/// 2. AI 提醒时用什么动词：考试是「复习」，检查是「整理好本子」，展示是「准备」，作业才是「做完交」。
///
/// 依据（2026-10-17 用真实数据核对过，也请 Gemini 4 Argon 看过）：
/// - 学生说 Notebook Check 老师检查完了、Presentation 展示完了、Class Participation 是老师打分，都没东西可交；
/// - 原始数据里一大批任务「开始时间 = 截止时间」（所有 Quiz、Lab、Notebook Check，数学的全部任务），
///   这是老师课后建的「登分格子」，不是布置给学生、限时交的作业；
/// - 学生真没交时，老师批改后一般会记「未完成」（finishState = 2），那才是真信号。
public enum TaskMode: String, Codable, Hashable, Sendable {
    /// 要交东西的：作业、练习单、项目、签字页……
    case submit
    /// 课上考：Quiz、Test、听写、默写、Progress Check
    case test
    /// 课上检查：Notebook / Workbook Check、Warm ups
    case check
    /// 课上展示、讨论：Presentation、Seminar、Discussion
    case present
    /// 课上完成：实验（Lab）、课堂练习
    case classwork
    /// 老师打分：课堂表现、考勤
    case teacher
    /// 老师建的登分格子（开始时间 = 截止时间），事情已经在课上做完了
    case slot

    /// 过了截止还没分数时，算「等老师登分」，而不是「可能没交」
    public var isDoneInClass: Bool { self != .submit }

    /// 给 AI 看的说明（放在每条任务后面）
    public var hint: String {
        switch self {
        case .submit: return "要交的作业"
        case .test: return "课上考，提前复习"
        case .check: return "课上检查，提前把本子 / 练习册整理好"
        case .present: return "课上展示，提前准备"
        case .classwork: return "课上完成"
        case .teacher: return "老师打分，不用交"
        case .slot: return "老师建的登分格子，课上已经做完，不用交"
        }
    }

    public static func of(name: String, typeName: String, category: TaskCategory, begin: Date?, end: Date?) -> TaskMode {
        let t = name.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        func word(_ pattern: String) -> Bool {
            t.range(of: "(?<![a-z])(\(pattern))(?![a-z])", options: .regularExpression) != nil
        }
        // 名字里写明了「提交」的，一定是要交的（比如「提交古诗默写单」「提交课堂学习笔记」）
        if has(["提交", "上传", "submit", "upload"]) { return .submit }
        if category.isTeacherRecorded { return .teacher }
        if category == .quiz { return .test }
        if has(["presentation", "seminar", "discussion", "debate", "speech", "展示", "汇报", "讨论", "演讲", "辩论"])
            || word("present") {
            return .present
        }
        if word("checks?") || has(["warm up", "warm-up", "warmup", "bell ringer", "检查", "ticket"]) { return .check }
        if word("labs?") || has(["classwork", "class work", "实验", "课堂练习", "随堂"])
            || typeName.lowercased() == "general classwork" {
            return .classwork
        }
        // 开始时间 = 截止时间（差不到 3 小时）：老师课后建的登分格子
        if let begin, let end, abs(end.timeIntervalSince(begin)) < 3 * 3600 { return .slot }
        return .submit
    }
}
