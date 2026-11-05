import AppKit
import SwiftUI
import SchoolisCore

// 主窗口、菜单栏面板共用的部件。
//
// 设计原则（见 设计评审.md）：照着系统自带的「提醒事项」做，克制一点——
// - 每行只用两处颜色：课程名用课程色，右边的日期用状态色（逾期红、明天橙……）；
// - 不用彩色卡片底、竖条、大数字方块；
// - 「我交了」= 左边的圆圈，和在「提醒事项」里勾掉一条一样。
//
// 注意：这个项目不用 Xcode，只有命令行工具。新版系统里 SwiftUI 的 @State 是一个「宏」，
// 宏的插件只随 Xcode 提供，所以这里一律不用 @State，需要记住的东西都放在 Store 里。

// MARK: - 侧边栏有哪些列表

/// 侧边栏顶部的四个「智能列表」
enum SmartList: String, CaseIterable, Hashable {
    case rescue, soon, upcoming, all

    var title: String {
        switch self {
        case .rescue: return "补救"
        case .soon: return "今明两天"
        case .upcoming: return "接下来"
        case .all: return "全部待交"
        }
    }

    var icon: String {
        switch self {
        case .rescue: return "exclamationmark"
        case .soon: return "sun.max.fill"
        case .upcoming: return "calendar"
        case .all: return "tray.fill"
        }
    }

    var tint: Color {
        switch self {
        case .rescue: return .red
        case .soon: return .orange
        case .upcoming: return .blue
        // 系统自带的 .gray 偏浅，选中时整块会发白、图标看不清，所以用深一点的灰蓝色
        case .all: return Color(red: 0.40, green: 0.44, blue: 0.50)
        }
    }
}

/// 侧边栏底部「等待中」的三个列表
enum WaitingList: String, CaseIterable, Hashable {
    case awaitingTeacher, selfReported, awaitingGrade, completed

    var title: String {
        switch self {
        case .awaitingTeacher: return "等老师登分"
        case .selfReported: return "你说交了"
        case .awaitingGrade: return "等批改"
        case .completed: return "已完成"
        }
    }

    var icon: String {
        switch self {
        case .awaitingTeacher: return "hourglass"
        case .selfReported: return "hand.raised"
        case .awaitingGrade: return "tray.and.arrow.up"
        case .completed: return "checkmark.circle"
        }
    }
}

/// 侧边栏里选中的是哪一项
enum SidebarItem: Hashable {
    case smart(SmartList)
    case subject(String)
    case category(TaskCategory)
    case waiting(WaitingList)

    var title: String {
        switch self {
        case .smart(let list): return list.title
        case .subject(let name): return name
        case .category(let category): return category.title
        case .waiting(let list): return list.title
        }
    }
}

// MARK: - 列表里的分组

/// 一行作业属于哪种情况。决定左边的圆圈和右边日期的颜色。
enum RowKind: Hashable {
    case markedNotDone, overdue, today, tomorrow, within7Days, later
    case awaitingTeacher, selfReported, awaitingGrade, completed

    var title: String {
        switch self {
        case .markedNotDone: return "老师记为未完成"
        case .overdue: return "过了截止，系统里还没记录"
        case .today: return "今天截止"
        case .tomorrow: return "明天截止"
        case .within7Days: return "7 天内"
        case .later: return "更晚"
        case .awaitingTeacher: return "等老师登分"
        case .selfReported: return "你说交了，等老师登记"
        case .awaitingGrade: return "已交，等批改"
        case .completed: return "已完成"
        }
    }

    var footer: String? {
        switch self {
        case .markedNotDone: return "老师在系统里记了「未完成」或 0 分。其实交了、或者还能补交的，去找老师说。"
        case .overdue: return "要交的作业，过了截止两周内系统里还没记录：可能交了纸质版、老师还没登，也可能真忘了。交了的话，点左边的圆圈。"
        case .awaitingTeacher: return "这些不用你管：课堂表现、考勤，还有课上已经做完的考试、检查、展示，等老师登分就行。要交的作业过了截止两周还没记录的，也放在这里。"
        case .selfReported: return "老师登了分以后会自动从这里消失。点绿色的勾可以撤销。"
        default: return nil
        }
    }

    /// 右边日期文字的颜色
    var dateTint: Color {
        switch self {
        case .markedNotDone, .overdue, .today: return .red
        case .tomorrow: return .orange
        default: return .secondary
        }
    }

    /// 还没交、可以点圆圈说「我交了」的
    var isPending: Bool {
        switch self {
        case .overdue, .today, .tomorrow, .within7Days, .later: return true
        default: return false
        }
    }

    var icon: String {
        switch self {
        case .markedNotDone: return "exclamationmark.triangle.fill"
        case .overdue: return "clock.badge.exclamationmark.fill"
        case .today: return "sun.max.fill"
        case .tomorrow: return "sunrise.fill"
        case .within7Days: return "calendar"
        case .later: return "calendar.badge.clock"
        case .awaitingTeacher: return "hourglass"
        case .selfReported: return "hand.raised.fill"
        case .awaitingGrade: return "tray.and.arrow.up.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .markedNotDone, .overdue, .today: return .red
        case .tomorrow: return .orange
        case .within7Days: return .blue
        case .later: return .indigo
        case .awaitingTeacher: return .purple
        case .selfReported: return .teal
        case .awaitingGrade: return .cyan
        case .completed: return .green
        }
    }

    var caption: String {
        switch self {
        case .markedNotDone: return "NEEDS ATTENTION"
        case .overdue: return "OVERDUE"
        case .today: return "DUE TODAY"
        case .tomorrow: return "DUE TOMORROW"
        case .within7Days: return "NEXT 7 DAYS"
        case .later: return "UPCOMING"
        case .awaitingTeacher: return "WAITING FOR TEACHER"
        case .selfReported: return "SELF REPORTED"
        case .awaitingGrade: return "AWAITING GRADE"
        case .completed: return "COMPLETED"
        }
    }
}

struct TaskSectionModel: Identifiable {
    let kind: RowKind
    let tasks: [LearningTask]
    var id: RowKind { kind }
}

/// 按侧边栏的选择，把分好组的作业挑出来
enum Sections {
    static let pendingKinds: [RowKind] = [.markedNotDone, .overdue, .today, .tomorrow, .within7Days, .later]

    static func build(_ item: SidebarItem, _ r: TodoReport) -> [TaskSectionModel] {
        let all: [(RowKind, [LearningTask])] = [
            (.markedNotDone, r.markedNotDone), (.overdue, r.overdue),
            (.today, r.today), (.tomorrow, r.tomorrow), (.within7Days, r.within7Days), (.later, r.later),
            (.awaitingTeacher, r.awaitingTeacher), (.selfReported, r.selfReported), (.awaitingGrade, r.awaitingGrade),
            (.completed, r.completed),
        ]
        var kinds: [RowKind]
        var keep: (LearningTask) -> Bool = { _ in true }
        switch item {
        case .smart(.rescue): kinds = [.markedNotDone, .overdue]
        case .smart(.soon): kinds = [.today, .tomorrow]
        case .smart(.upcoming): kinds = [.within7Days, .later]
        case .smart(.all): kinds = pendingKinds
        case .subject(let name):
            kinds = all.map(\.0)
            keep = { $0.subjectName == name }
        case .category(let category):
            kinds = all.map(\.0)
            keep = { $0.category == category }
        case .waiting(.awaitingTeacher): kinds = [.awaitingTeacher]
        case .waiting(.selfReported): kinds = [.selfReported]
        case .waiting(.awaitingGrade): kinds = [.awaitingGrade]
        case .waiting(.completed): kinds = [.completed]
        }
        return all.compactMap { kind, tasks in
            guard kinds.contains(kind) else { return nil }
            let picked = tasks.filter(keep)
            return picked.isEmpty ? nil : TaskSectionModel(kind: kind, tasks: picked)
        }
    }

    static func count(_ item: SidebarItem, _ r: TodoReport) -> Int {
        build(item, r).reduce(0) { $0 + $1.tasks.count }
    }

    /// 某一科还没交的件数（侧边栏科目旁边的数字）
    static func pendingCount(subject: String, _ r: TodoReport) -> Int {
        pendingCount(.subject(subject), r)
    }

    /// 某一科 / 某一类还没交的件数
    static func pendingCount(_ item: SidebarItem, _ r: TodoReport) -> Int {
        build(item, r).filter { pendingKinds.contains($0.kind) }.reduce(0) { $0 + $1.tasks.count }
    }
}

// MARK: - 颜色

/// 作业类型在左栏里的图标和颜色
extension TaskCategory {
    var icon: String {
        switch self {
        case .quiz: return "checklist"
        case .homework: return "pencil"
        case .project: return "paintpalette.fill"
        case .participation: return "hand.raised.fill"
        case .attendance: return "person.fill.checkmark"
        case .other: return "tray.fill"
        }
    }

    var tint: Color {
        switch self {
        case .quiz: return .red
        case .homework: return .blue
        case .project: return .purple
        case .participation: return .green
        case .attendance: return .teal
        case .other: return .gray
        }
    }
}

/// 每门课一个固定的颜色，列表里一眼就能分出是哪科。
enum SubjectColor {
    static let palette: [Color] = [.blue, .purple, .pink, .orange, .teal, .indigo, .green, .brown, .mint, .cyan, .red, .yellow]

    static func of(_ subject: String) -> Color {
        // 自己算一个简单的哈希：同一门课每次启动都是同一个颜色。
        // （Swift 自带的 hashValue 每次启动都不一样，不能用）
        let sum = subject.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fff_ffff }
        return palette[sum % palette.count]
    }
}

// MARK: - 一行作业

struct TaskRow: View {
    @ObservedObject var store: Store
    let task: LearningTask
    let kind: RowKind
    var compact = false

    // 字号：主窗口里放大（作业名 16pt），菜单栏小面板地方小，保持紧凑
    private var titleSize: CGFloat { compact ? 13 : 16 }
    private var detailSize: CGFloat { compact ? 11 : 13 }
    private var trailingSize: CGFloat { compact ? 12 : 15 }

    var body: some View {
        HStack(alignment: .top, spacing: compact ? 10 : 12) {
            statusCircle
                .font(.system(size: compact ? 15 : 19))
                .frame(width: compact ? 22 : 26)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: compact ? 3 : 4) {
                Text(task.name)
                    .font(.system(size: titleSize))
                    .lineLimit(2)
                    .foregroundStyle(kind == .selfReported || kind == .awaitingGrade || kind == .completed ? .secondary : .primary)
                HStack(spacing: 6) {
                    Text(task.subjectName).foregroundStyle(SubjectColor.of(task.subjectName))
                    Text(Format.deadlineText(task)).foregroundStyle(.secondary)
                    if kind != .markedNotDone && kind != .completed, let total = task.totalScore, total > 0 {
                        Text("· 满分 \(Format.number(total))").foregroundStyle(.tertiary)
                    }
                    if kind == .completed && task.finishState == 3 {
                        Text("· 迟交").foregroundStyle(.orange)
                    }
                    if task.isExempt {
                        Text("· 免做").foregroundStyle(.tertiary)
                    }
                    // 老师原来填的类型（中文或英文），按类型看的时候能核对分得对不对
                    if !compact && !task.typeName.isEmpty {
                        Text("· \(task.typeName)").foregroundStyle(.tertiary)
                    }
                }
                .font(.system(size: detailSize))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 12)
            trailing
                .font(.system(size: trailingSize))
                .padding(.top, 1)
        }
        .padding(.vertical, compact ? 3 : 7)
        .contentShape(Rectangle())
        .help(task.name)
        .contextMenu {
            if kind.isPending {
                Button("我交了（纸质版 / 线下交的）") { store.setSelfReported(task, true) }
            }
            if kind == .selfReported {
                Button("撤销「我交了」") { store.setSelfReported(task, false) }
            }
            Button("复制作业名") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(task.name, forType: .string)
            }
        }
    }

    /// 左边的圆圈：空圈 = 还没交（点一下 = 我交了）；绿勾 = 你说交了；红感叹号 = 老师记了未完成
    @ViewBuilder private var statusCircle: some View {
        switch kind {
        case .overdue, .today, .tomorrow, .within7Days, .later:
            Button {
                store.setSelfReported(task, true)
            } label: {
                Image(systemName: "circle").foregroundStyle(.tertiary)
            }
            .buttonStyle(VitraPressStyle())
            .help("我交了：交的是纸质版、系统里还没登记时点这里（只记在你自己电脑上）")
        case .selfReported:
            Button {
                store.setSelfReported(task, false)
            } label: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.teal)
            }
            .buttonStyle(VitraPressStyle())
            .help("撤销「我交了」")
        case .markedNotDone:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .awaitingTeacher:
            Image(systemName: "hourglass.circle").foregroundStyle(.secondary)
        case .awaitingGrade:
            Image(systemName: "checkmark.circle").foregroundStyle(.secondary)
        case .completed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    @ViewBuilder private var trailing: some View {
        switch kind {
        case .markedNotDone:
            Text(Format.points(task))
                .monospacedDigit()
                .fontWeight(.semibold)
                .foregroundStyle((task.totalScore ?? 0) > 0 ? Color.red : Color.secondary)
        case .overdue, .today, .tomorrow, .within7Days, .later:
            if let end = task.endDate {
                Text(Format.relative(end, now: store.now))
                    .monospacedDigit()
                    .foregroundStyle(kind.dateTint)
            }
        case .completed:
            Text(Format.points(task))
                .monospacedDigit()
                .foregroundStyle(Format.scoreTint(task))
        case .awaitingTeacher, .selfReported, .awaitingGrade:
            EmptyView()
        }
    }
}

// MARK: - 提示条

/// 同步失败、数据读不懂时，浮在列表上方的一条玻璃提示
struct StatusBanner: View {
    @ObservedObject var store: Store

    var body: some View {
        if let message = text {
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(message)
                    .font(.callout)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if store.lastError != nil {
                    Button("重试") { Task { await store.sync() } }.buttonStyle(VitraSoftStyle())
                        .disabled(store.syncing)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .vitraGlass(.widget, radius: 14)
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    private var text: String? {
        if let error = store.lastError {
            return "同步失败：\(error)\n下面显示的是 \(store.snapshot.map { Format.syncTime.string(from: $0.syncedAt) } ?? "以前") 的数据。"
        }
        if let unreadable = store.snapshot?.unreadableTasks, unreadable > 0 {
            return "有 \(unreadable) 条任务读不懂，可能是学校网站改版了，列表不完整。"
        }
        return nil
    }
}

/// 同步按钮（工具栏和菜单栏面板都用）
struct SyncButton: View {
    @ObservedObject var store: Store

    var body: some View {
        Button {
            Task { await store.sync() }
        } label: {
            if store.syncing {
                ProgressView().controlSize(.small)
            } else {
                Label("同步", systemImage: "arrow.clockwise")
            }
        }
        .disabled(store.syncing)
        .help(store.syncing ? "正在同步…" : "立即同步")
    }
}

// MARK: - 文字格式

enum Format {
    static let deadline: DateFormatter = makeFormatter("M月d日 EEE HH:mm")
    static let syncTime: DateFormatter = makeFormatter("M月d日 HH:mm")
    private static let clock: DateFormatter = makeFormatter("HH:mm")
    private static let monthDay: DateFormatter = makeFormatter("M月d日")

    private static func makeFormatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = SchoolTime.zone
        f.dateFormat = pattern
        return f
    }

    static func number(_ x: Double) -> String { String(format: "%g", x) }

    static func deadlineText(_ task: LearningTask) -> String {
        task.endDate.map { deadline.string(from: $0) } ?? "没写截止时间"
    }

    /// 「今天 23:59」「明天 13:23」「10月9日 15:39」
    static func shortDeadline(_ task: LearningTask) -> String {
        guard let end = task.endDate else { return "没写截止" }
        let calendar = SchoolTime.calendar
        if calendar.isDateInToday(end) { return "今天 " + clock.string(from: end) }
        if calendar.isDateInTomorrow(end) { return "明天 " + clock.string(from: end) }
        return monthDay.string(from: end) + " " + clock.string(from: end)
    }

    static func relative(_ end: Date, now: Date) -> String {
        let seconds = end.timeIntervalSince(now)
        let hours = abs(seconds) / 3600
        if seconds >= 0 {
            if hours < 1 { return "不到 1 小时" }
            if hours < 24 { return "还剩 \(Int(hours)) 小时" }
            return "还有 \(Int(ceil(hours / 24))) 天"
        } else {
            if hours < 24 { return "逾期 \(max(1, Int(hours))) 小时" }
            return "逾期 \(Int(hours / 24)) 天"
        }
    }

    /// 得分率低于 60% 标红，低于 80% 标橙，其他用普通灰色（分数高的不需要吸引注意）
    static func scoreTint(_ task: LearningTask) -> Color {
        guard let total = task.totalScore, total > 0 else { return .secondary }
        let ratio = (task.score ?? 0) / total
        if ratio < 0.6 { return .red }
        if ratio < 0.8 { return .orange }
        return .secondary
    }

    static func points(_ task: LearningTask) -> String {
        let total = task.totalScore ?? 0
        if total == 0 { return "不计分" }
        return "\(number(task.score ?? 0))/\(number(total))"
    }

    /// 通知里的作业清单，最多列 4 条
    static func lines(_ tasks: [LearningTask]) -> String {
        var rows = tasks.prefix(4).map { "• \(shortDeadline($0))  \($0.subjectName)｜\($0.name)" }
        if tasks.count > 4 { rows.append("…还有 \(tasks.count - 4) 个") }
        return rows.joined(separator: "\n")
    }

    /// 汇总通知的正文
    static func summary(_ r: TodoReport) -> String {
        var parts: [String] = []
        if !r.markedNotDone.isEmpty { parts.append("老师记未完成 \(r.markedNotDone.count)") }
        if !r.overdue.isEmpty { parts.append("过了截止 \(r.overdue.count)") }
        if !r.today.isEmpty { parts.append("今天截止 \(r.today.count)") }
        if !r.tomorrow.isEmpty { parts.append("明天截止 \(r.tomorrow.count)") }
        if !r.within7Days.isEmpty { parts.append("7 天内 \(r.within7Days.count)") }
        var text = parts.isEmpty ? "没有要交的作业" : parts.joined(separator: " · ")
        if let next = (r.today + r.tomorrow + r.within7Days + r.later).first {
            text += "\n最近要交：\(shortDeadline(next))  \(next.subjectName)｜\(next.name)"
        }
        return text
    }
}
