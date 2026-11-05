import Foundation

/// 待办分组的结果。每个任务只会出现在一个组里。
public struct TodoReport {
    /// 老师记了「未完成」，或者批改了但是 0 分 → 要去找老师
    public var markedNotDone: [LearningTask] = []
    /// 要交的作业过了截止（14 天内），系统里还没有任何记录 → 可能真没交，也可能交了纸质版、老师还没登记
    public var overdue: [LearningTask] = []
    public var today: [LearningTask] = []
    public var tomorrow: [LearningTask] = []
    public var within7Days: [LearningTask] = []
    /// 7 天以后截止，或者没写截止时间
    public var later: [LearningTask] = []
    /// 等老师登分：课堂表现、考勤（本来就不用交），课上已经做完的（考试、检查、展示、登分格子），
    /// 截止时间像是老师随手填的默认值的，还有过了截止 14 天还没记录的 → 都不算逾期
    public var awaitingTeacher: [LearningTask] = []
    /// 你点了「我交了」的
    public var selfReported: [LearningTask] = []
    /// 已经交了、等老师批改
    public var awaitingGrade: [LearningTask] = []
    /// 已经完成、批改完的（包括迟交的、免做的）
    public var completed: [LearningTask] = []

    /// 所有组加起来的件数。每个任务只会出现在一个组里，所以它应该等于任务总数。
    public var totalCount: Int {
        markedNotDone.count + overdue.count + today.count + tomorrow.count + within7Days.count + later.count
            + awaitingTeacher.count + selfReported.count + awaitingGrade.count + completed.count
    }

    /// 菜单栏上显示的数字：需要你马上处理的件数（补救 + 今明两天截止）
    public var urgentCount: Int {
        markedNotDone.count + overdue.count + today.count + tomorrow.count
    }

    public init() {}
}

/// 把任务分成「该做什么」的几组。纯计算，不联网，所以可以用存下来的数据反复测试。
///
/// 规则是按「老师可能会偷懒」来设计的：
/// - 「我的回答」是空的，不代表没交（纸质作业都是空的），所以完全不看它。
/// - 有分数（大于 0）就算交了，哪怕老师忘了改状态。
/// - 同一科有 3 条以上任务的截止时间一模一样，那个时间多半是默认值，过期了也不算逾期。
/// - 课堂表现、考勤是老师打的分，没有东西可交，一律算「等老师登分」，不出现在要交的列表里。
/// - 课上完成的（考试、Notebook Check、Presentation、Lab、老师建的登分格子，见 TaskMode）：
///   没到时间的照常提醒（好复习、准备），过了时间还没分数的是老师还没登，不算「没交」。
///   用户说的：「Progress Check 是他 check 我」「Notebook Check 已经 check 完了」「Presentation 我已经 present 完了」。
/// - 要交的作业过了截止 14 天还没记录，也不再算逾期：老师登分很慢，真没交的话老师一般会记「未完成」。
public enum TodoClassifier {
    /// 要交的作业过了截止多久还没记录，就不再算「可能没交」（14 天）
    public static let staleAfter: TimeInterval = 14 * 24 * 3600

    public static func classify(_ tasks: [LearningTask], now: Date, selfReported: Set<Int>) -> TodoReport {
        var report = TodoReport()
        let placeholders = placeholderDeadlines(in: tasks)

        let calendar = SchoolTime.calendar
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let startOfDayAfter = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))!
        let oneWeekLater = now.addingTimeInterval(7 * 24 * 3600)

        for task in tasks {
            // 免做的不用交，算进「已完成」
            if task.isExempt {
                report.completed.append(task)
                continue
            }
            let score = task.score ?? 0
            let end = task.endDate

            // 1. 已经交了：状态是完成/延迟完成，或者有分数
            if task.finishState == 1 || task.finishState == 3 || score > 0 {
                if task.learningTaskState == 5 {
                    report.awaitingGrade.append(task)
                } else {
                    report.completed.append(task)
                }
                continue
            }

            // 2. 老师明确记了「未完成」，或者已经批改、截止了却是 0 分
            // （不计分的作业批改后本来就是 0 分，不算）
            let gradedZero = task.learningTaskState == 4 && (task.totalScore ?? 0) > 0 && (end.map { $0 < now } ?? true)
            if task.finishState == 2 || gradedZero {
                report.markedNotDone.append(task)
                continue
            }

            // 3. 你说交了线下版的，等老师登记
            if selfReported.contains(task.id) {
                report.selfReported.append(task)
                continue
            }

            // 4. 课堂表现、考勤：老师打分，不用交
            if task.mode == .teacher {
                report.awaitingTeacher.append(task)
                continue
            }

            // 5. 还没交：按截止时间分组
            guard let end else {
                report.later.append(task)
                continue
            }
            if end >= now {
                // 没到截止时间的一律显示出来，不做任何「可能是默认值」的猜测，免得漏掉
                if end < startOfTomorrow { report.today.append(task) }
                else if end < startOfDayAfter { report.tomorrow.append(task) }
                else if end < oneWeekLater { report.within7Days.append(task) }
                else { report.later.append(task) }
            } else if placeholders.contains(deadlineKey(task)) || task.mode.isDoneInClass
                        || now.timeIntervalSince(end) > staleAfter {
                // 截止时间是随手填的；课上已经做完的（考试、检查、展示、登分格子）；
                // 或者过了截止很久还没记录（老师一直没登）→ 都是等老师登分
                report.awaitingTeacher.append(task)
            } else {
                report.overdue.append(task)
            }
        }

        // 快到期的排前面；已经过期的，最近的排前面（越近越有可能补救）
        let soonestFirst: (LearningTask, LearningTask) -> Bool = {
            ($0.endDate ?? .distantFuture) < ($1.endDate ?? .distantFuture)
        }
        let latestFirst: (LearningTask, LearningTask) -> Bool = {
            ($0.endDate ?? .distantPast) > ($1.endDate ?? .distantPast)
        }
        report.today.sort(by: soonestFirst)
        report.tomorrow.sort(by: soonestFirst)
        report.within7Days.sort(by: soonestFirst)
        report.later.sort(by: soonestFirst)
        report.overdue.sort(by: latestFirst)
        report.markedNotDone.sort(by: latestFirst)
        report.awaitingTeacher.sort(by: latestFirst)
        report.selfReported.sort(by: latestFirst)
        report.awaitingGrade.sort(by: latestFirst)
        report.completed.sort(by: latestFirst)
        return report
    }

    /// 「科目 + 截止时间（精确到分钟）」
    static func deadlineKey(_ task: LearningTask) -> String {
        "\(task.subjectName)|\(task.endTime?.prefix(16) ?? "")"
    }

    /// 找出「同一科、同一个截止时间」出现 3 次以上的组合，比如某科开学时一口气建了十几个截止时间一模一样的任务。
    static func placeholderDeadlines(in tasks: [LearningTask]) -> Set<String> {
        let groups = Dictionary(grouping: tasks.filter { $0.endTime != nil }, by: deadlineKey)
        return Set(groups.filter { $0.value.count >= 3 }.keys)
    }
}
