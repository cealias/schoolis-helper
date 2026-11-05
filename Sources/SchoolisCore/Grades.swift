import Foundation

// MARK: - 数据

/// 分数段：多少分对应什么等级、多少绩点。来自学校接口的 scoreMappingList，比如 93～96.9 → A → 4.0。
public struct LevelBand: Codable, Hashable {
    public let name: String
    public let gpa: Double
    public let min: Double
    public let max: Double
}

/// 成绩构成里的一个评价项目。有的项目下面还有子项目，比如数学「作业」下面分「课堂作业」「作业与练习」「课堂笔记」。
public struct ScoreItem: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    /// 在上一层里占的权重（%）
    public let proportion: Double
    /// 还没出分时是 nil
    public let score: Double?
    public let level: String
    public let children: [ScoreItem]

    public var isLeaf: Bool { children.isEmpty }
}

/// 一科的动态成绩
public struct SubjectGrade: Codable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let classId: Int
    public let score: Double?
    /// 是否计入 GPA（比如「初中体育必选」不计入）
    public let isInGrade: Bool
    public var items: [ScoreItem]
}

public struct GradeData: Codable {
    public var subjects: [SubjectGrade]
    public var bands: [LevelBand]

    public init(subjects: [SubjectGrade], bands: [LevelBand]) {
        self.subjects = subjects
        self.bands = bands
    }
}

// MARK: - 从接口解析

extension GradeData {
    /// 解析 GetStuSemesterDynamicScore：各科总分 + 分数段对照表（成绩构成另外再取）
    public static func parse(scores: Any?) -> GradeData {
        let data = J.dict(scores)
        let configs = J.array(J.array(data["scoreMappingList"]).first?["scoreMappingConfigs"])
        let bands = configs.compactMap { c -> LevelBand? in
            guard let name = J.string(c["displayName"]), let gpa = J.double(c["gpa"]),
                  let min = J.double(c["minValue"]), let max = J.double(c["maxValue"]) else { return nil }
            return LevelBand(name: name, gpa: gpa, min: min, max: max)
        }.sorted { $0.min > $1.min }
        let subjects = J.array(data["studentSemesterDynamicScoreBasicDtos"]).compactMap { d -> SubjectGrade? in
            guard let id = J.int(d["subjectId"]) else { return nil }
            return SubjectGrade(id: id, name: J.string(d["subjectName"]) ?? "（未知科目）",
                                classId: J.int(d["classId"]) ?? 0, score: J.double(d["subjectScore"]),
                                isInGrade: J.bool(d["isInGrade"]) ?? true, items: [])
        }
        return GradeData(subjects: subjects, bands: bands)
    }

    /// 解析 GetDynamicScoreDetail：一科的成绩构成（树形）
    public static func parseItems(detail: Any?) -> [ScoreItem] {
        J.array(J.dict(detail)["evaluationProjectList"]).map(parseItem)
    }

    private static func parseItem(_ d: [String: Any]) -> ScoreItem {
        let isNull = J.bool(d["scoreIsNull"]) ?? false
        return ScoreItem(id: J.int(d["evaluationProjectId"]) ?? 0,
                         name: (J.string(d["evaluationProjectName"]) ?? "").trimmingCharacters(in: .whitespaces),
                         proportion: J.double(d["proportion"]) ?? 0,
                         score: isNull ? nil : J.double(d["score"]),
                         level: J.string(d["scoreLevel"]) ?? "",
                         children: J.array(d["evaluationProjectList"]).map(parseItem))
    }
}

// MARK: - 按学校的规则算分

/// 所有计算都在这里，纯数学、不联网，可以用存下来的数据反复验证。
///
/// 学校的规则（用真实数据核对过）：
/// - 一个项目的分 = 它下面已出分的子项目按权重加权平均，还没出分的不算；每一层都保留 1 位小数。
///   例：某科「作业」=（课堂作业 70×40 + 作业与练习 90×40）÷ 80 = 80.0
/// - 叶子项目的分 = 算在它里面、已批改作业的得分之和 ÷ 满分之和。
///   例：某科「笔记/作业」=（18+9+25）÷（20+10+30）= 86.7
/// - 各科的绩点按分数段对照表查；动态 GPA = 计入成绩的各科绩点直接平均，舍去到 2 位小数（3.876 显示成 3.87）。
public enum GradeMath {
    /// 保留 1 位小数（四舍五入）。加一点点误差余量，免得 85.85 被电脑存成 85.8499999 而舍错。
    public static func round1(_ x: Double) -> Double {
        ((x * 10) + 1e-6).rounded() / 10
    }

    /// GPA 显示：舍去到 2 位小数
    public static func floor2(_ x: Double) -> Double {
        (x * 100 + 1e-6).rounded(.down) / 100
    }

    public static func band(for score: Double, in bands: [LevelBand]) -> LevelBand? {
        let s = round1(score)
        if let exact = bands.first(where: { s >= $0.min && s <= $0.max }) { return exact }
        // 落在两段之间的缝里（比如 96.95）：归到较低的那一段
        return bands.filter { $0.min <= s }.max { $0.min < $1.min }
    }

    /// 算一组项目合起来的分。overrides：假设某些项目变成某个分（用来算「如果……会怎样」）。
    public static func score(_ items: [ScoreItem], overrides: [Int: Double] = [:]) -> Double? {
        var weight = 0.0, sum = 0.0
        for item in items {
            guard item.proportion > 0, let s = score(of: item, overrides: overrides) else { continue }
            weight += item.proportion
            sum += item.proportion * s
        }
        guard weight > 0 else { return nil }
        return round1(sum / weight)
    }

    public static func score(of item: ScoreItem, overrides: [Int: Double] = [:]) -> Double? {
        if let value = overrides[item.id] { return value }
        if item.isLeaf { return item.score }
        return score(item.children, overrides: overrides) ?? item.score
    }

    /// 一科现在的分：优先用我们按规则重算的（这样「如果」算出来的变化才对得上），算不出来就用学校给的
    public static func currentScore(_ subject: SubjectGrade) -> Double? {
        score(subject.items) ?? subject.score
    }

    /// 动态 GPA（不舍去）。scores：假设某些科目变成某个分。
    public static func gpa(_ subjects: [SubjectGrade], bands: [LevelBand], scores: [Int: Double] = [:]) -> Double? {
        let points = subjects.filter(\.isInGrade).compactMap { subject -> Double? in
            guard let s = scores[subject.id] ?? subject.score, let b = band(for: s, in: bands) else { return nil }
            return b.gpa
        }
        guard !points.isEmpty else { return nil }
        return points.reduce(0, +) / Double(points.count)
    }

    // MARK: 离下一级还差多少

    public struct LevelStep: Hashable {
        public let subjectId: Int
        public let subjectName: String
        public let currentScore: Double
        public let from: LevelBand
        public let to: LevelBand
        /// 这科总分要提高多少分
        public var delta: Double { round1(to.min - currentScore) }
        public var gpaGain: Double { to.gpa - from.gpa }
    }

    /// 一科往上的几个等级，各要多少分
    public static func steps(for subject: SubjectGrade, bands: [LevelBand], maxSteps: Int = 4) -> [LevelStep] {
        guard subject.isInGrade, let s = subject.score, let current = band(for: s, in: bands) else { return [] }
        return bands.filter { $0.min > current.min }
            .sorted { $0.min < $1.min }
            .prefix(maxSteps)
            .map { LevelStep(subjectId: subject.id, subjectName: subject.name, currentScore: s, from: current, to: $0) }
    }

    // MARK: 提到目标 GPA 的方案

    public struct PlanOption: Hashable, Identifiable {
        public let steps: [LevelStep]
        public let resultingGPA: Double
        public var totalDelta: Double { round1(steps.reduce(0) { $0 + $1.delta }) }
        public var id: String { steps.map { "\($0.subjectId)-\($0.to.name)" }.joined(separator: ",") }
    }

    public struct GPAPlan {
        public let currentGPA: Double
        public let target: Double
        public let subjectCount: Int
        /// 最省力的几种方案（按总共要提的分数从少到多）
        public let options: [PlanOption]
        /// 所有能提的科目都提到最高也够不到时为 false
        public let reachable: Bool
        public var alreadyThere: Bool { currentGPA + 1e-9 >= target }
    }

    /// 找出「提哪几科、各提到哪一级」能让 GPA 到目标，按要提的总分从少到多排。最多同时提 3 科。
    public static func plan(_ data: GradeData, target: Double, limit: Int = 3) -> GPAPlan? {
        let subjects = data.subjects.filter { $0.isInGrade && $0.score != nil }
        guard let current = gpa(subjects, bands: data.bands) else { return nil }
        let n = Double(subjects.count)
        let need = (target - current) * n // 各科绩点加起来还差多少
        let perSubject = subjects.map { steps(for: $0, bands: data.bands) }.filter { !$0.isEmpty }
        let maxGain = perSubject.compactMap { $0.last?.gpaGain }.reduce(0, +)
        guard need > 1e-9 else {
            return GPAPlan(currentGPA: current, target: target, subjectCount: subjects.count, options: [], reachable: true)
        }

        var feasible: [PlanOption] = []
        func search(from start: Int, chosen: [LevelStep]) {
            let gain = chosen.reduce(0) { $0 + $1.gpaGain }
            if !chosen.isEmpty && gain >= need - 1e-9 {
                feasible.append(PlanOption(steps: chosen, resultingGPA: current + gain / n))
                return // 已经够了，再多提一科只会更费劲
            }
            guard chosen.count < 3, start < perSubject.count else { return }
            for i in start..<perSubject.count {
                for step in perSubject[i] { search(from: i + 1, chosen: chosen + [step]) }
            }
        }
        search(from: 0, chosen: [])

        feasible.sort { ($0.totalDelta, $0.steps.count) < ($1.totalDelta, $1.steps.count) }
        var picked: [PlanOption] = []
        for option in feasible where picked.count < limit {
            // 同样这几科的组合只留最省力的一种，让几个方案之间真的有区别
            let set = Set(option.steps.map(\.subjectId))
            if picked.contains(where: { Set($0.steps.map(\.subjectId)) == set }) { continue }
            picked.append(option)
        }
        return GPAPlan(currentGPA: current, target: target, subjectCount: subjects.count,
                       options: picked, reachable: maxGain >= need - 1e-9)
    }

    // MARK: 一科里「从哪儿涨分」

    /// 一个能涨分的地方
    public struct Lever: Hashable, Identifiable {
        public enum Kind: Hashable {
            /// 已出分、但分不高的项目
            case weakItem
            /// 已批改、分数低的作业（补交 / 重做拿满分能涨多少）
            case redoTask
            /// 还没交 / 还没批的作业（交满分能涨多少、不交会掉多少）
            case pendingTask
        }
        public let kind: Kind
        public let title: String
        public let path: String
        public let detail: String
        /// 这科总分能涨多少（预计）
        public let gain: Double
        /// 不交会掉多少（只有 pendingTask 有）
        public let loss: Double
        public let taskId: Int?
        public var id: String { "\(kind)-\(title)-\(path)" }
    }

    /// 还没出分的项目（期中、期末……）要考到多少，才能保住 / 升到某个等级
    public struct FutureNeed: Hashable {
        public let items: [String]
        /// 这些项目最后占这科总分的比例（%）
        public let share: Double
        /// （等级，剩下的项目平均要考到的分；nil = 就算满分也到不了）
        public let needs: [(band: LevelBand, average: Double?)]

        // needs 是元组，没法自动比较，所以手写：三样都要比（以前漏了 needs，分数变了界面可能不刷新）
        public static func == (a: FutureNeed, b: FutureNeed) -> Bool {
            a.items == b.items && a.share == b.share
                && a.needs.map(\.band) == b.needs.map(\.band) && a.needs.map(\.average) == b.needs.map(\.average)
        }
        public func hash(into hasher: inout Hasher) {
            hasher.combine(items); hasher.combine(share); hasher.combine(needs.map(\.average))
        }
    }

    /// 叶子项目 + 它在树里的路径（「作业 › 课堂作业」）
    public struct Leaf {
        public let item: ScoreItem
        public let path: String
        /// 现在它占这科总分的比例（只算已出分的项目）
        public let shareNow: Double
        /// 等所有项目都出分后，它占这科总分的比例
        public let shareFinal: Double
    }

    public static func leaves(_ items: [ScoreItem]) -> [Leaf] {
        var result: [Leaf] = []
        func walk(_ items: [ScoreItem], prefix: String, now: Double, final: Double) {
            let scoredWeight = items.filter { $0.proportion > 0 && score(of: $0) != nil }.reduce(0) { $0 + $1.proportion }
            let allWeight = items.filter { $0.proportion > 0 }.reduce(0) { $0 + $1.proportion }
            for item in items where item.proportion > 0 {
                let path = prefix.isEmpty ? item.name : "\(prefix) › \(item.name)"
                let isScored = score(of: item) != nil
                let shareNow = isScored && scoredWeight > 0 ? now * item.proportion / scoredWeight : 0
                let shareFinal = allWeight > 0 ? final * item.proportion / allWeight : 0
                if item.isLeaf {
                    result.append(Leaf(item: item, path: path, shareNow: shareNow, shareFinal: shareFinal))
                } else {
                    walk(item.children, prefix: path, now: shareNow, final: shareFinal)
                }
            }
        }
        walk(items, prefix: "", now: 1, final: 1)
        return result
    }

    /// 还没出分的项目要考多少
    public static func futureNeed(_ subject: SubjectGrade, bands: [LevelBand]) -> FutureNeed? {
        let pending = leaves(subject.items).filter { $0.item.score == nil }
        guard !pending.isEmpty, let current = currentScore(subject), let currentBand = band(for: current, in: bands) else { return nil }
        // 剩下的项目都考 x 分时，这科最后的分
        func finalScore(_ x: Double) -> Double {
            var overrides: [Int: Double] = [:]
            for leaf in pending { overrides[leaf.item.id] = x }
            return score(subject.items, overrides: overrides) ?? current
        }
        // 至少要考多少（二分查找；分数越高最后的分越高）
        func needed(for target: Double) -> Double? {
            guard finalScore(100) >= target else { return nil }
            if finalScore(0) >= target { return 0 }
            var low = 0.0, high = 100.0
            for _ in 0..<40 {
                let mid = (low + high) / 2
                if finalScore(mid) >= target { high = mid } else { low = mid }
            }
            return (high * 10).rounded(.up) / 10
        }
        let targets = [currentBand] + bands.filter { $0.min > currentBand.min }.sorted { $0.min < $1.min }.prefix(2)
        return FutureNeed(items: pending.map(\.path),
                          share: round1(pending.reduce(0) { $0 + $1.shareFinal } * 100),
                          needs: targets.map { ($0, needed(for: $0.min)) })
    }

    /// 一科里能涨分的地方，按能涨的分从多到少排。
    /// tasks / taskItems：作业和「作业算在哪个项目里」的对应表（来自作业详情）；没有时只给项目层面的建议。
    public static func levers(_ subject: SubjectGrade, tasks: [LearningTask], taskItems: [String: [Int]],
                              now: Date = Date()) -> [Lever] {
        guard let current = currentScore(subject) else { return [] }
        var result: [Lever] = []
        let subjectTasks = tasks.filter { $0.subjectName == subject.name }

        for leaf in leaves(subject.items) {
            let mine = subjectTasks.filter { (taskItems[String($0.id)] ?? []).contains(leaf.item.id) }
            let graded = mine.filter { $0.learningTaskState == 4 && ($0.totalScore ?? 0) > 0 }
            let earned = graded.reduce(0) { $0 + ($1.score ?? 0) }
            let possible = graded.reduce(0) { $0 + ($1.totalScore ?? 0) }

            // 1. 分不高的项目本身
            if let s = leaf.item.score, s < 90 {
                let gain = round1((score(subject.items, overrides: [leaf.item.id: 100]) ?? current) - current)
                if gain >= 0.3 {
                    result.append(Lever(kind: .weakItem, title: leaf.item.name, path: leaf.path,
                                        detail: "现在 \(fmt(s)) 分，占这科现在总分的 \(fmt(round1(leaf.shareNow * 100)))%。这一项每提高 10 分，这科总分约 +\(fmt(round1(leaf.shareNow * 10)))。",
                                        gain: gain, loss: 0, taskId: nil))
                }
            }

            // 作业层面的建议：只有当「按作业算出来的项目分」和学校给的对得上时才给，免得对应关系错了还瞎算
            let verified: Bool = {
                guard let official = leaf.item.score else { return graded.isEmpty }
                guard possible > 0 else { return false }
                return abs(round1(earned / possible * 100) - official) <= 0.15
            }()
            guard verified else { continue }

            // 2. 已批改、分数低的作业：补交 / 重做拿满分能涨多少
            // 课堂表现、考勤没法补交或重做，不给这种建议
            for task in graded where !task.category.isTeacherRecorded {
                let s = task.score ?? 0, t = task.totalScore ?? 0
                guard t > 0, s / t < 0.9 else { continue }
                let newLeaf = round1((earned - s + t) / possible * 100)
                let gain = round1((score(subject.items, overrides: [leaf.item.id: newLeaf]) ?? current) - current)
                guard gain >= 0.1 else { continue }
                result.append(Lever(kind: .redoTask, title: task.name, path: leaf.path,
                                    detail: "得了 \(fmt(s))/\(fmt(t))。如果能补交或重做拿满分，「\(leaf.item.name)」会从 \(fmt(leaf.item.score ?? 0)) 变成 \(fmt(newLeaf))。",
                                    gain: gain, loss: 0, taskId: task.id))
            }

            // 3. 还没交 / 还没批的作业：交满分能涨多少，不交会掉多少
            // 课上已经做完、只等老师登分的（考试考完了、展示讲完了、本子检查过了），学生做不了什么，不算
            for task in mine where task.learningTaskState == 2 && (task.score ?? 0) == 0
                && task.finishState != 1 && task.finishState != 3 && !task.category.isTeacherRecorded
                && !(task.mode.isDoneInClass && (task.endDate.map { $0 < now } ?? false)) {
                let t = task.totalScore ?? 0
                guard t > 0 else { continue }
                let full = round1((earned + t) / (possible + t) * 100)
                let zero = round1(earned / (possible + t) * 100)
                let gain = round1((score(subject.items, overrides: [leaf.item.id: full]) ?? current) - current)
                let loss = round1(current - (score(subject.items, overrides: [leaf.item.id: zero]) ?? current))
                guard gain >= 0.1 || loss >= 0.1 else { continue }
                result.append(Lever(kind: .pendingTask, title: task.name, path: leaf.path,
                                    detail: "满分 \(fmt(t))，算在「\(leaf.item.name)」里，还没出分。拿满分这科 +\(fmt(gain))；没交或 0 分 −\(fmt(loss))。",
                                    gain: gain, loss: loss, taskId: task.id))
            }
        }
        // 按「能涨多少」排；涨得一样多时，不做会掉得多的排前面
        return result.sorted { ($0.gain, $0.loss) > ($1.gain, $1.loss) }
    }

    static func fmt(_ x: Double) -> String { String(format: "%g", round1(x)) }
}
