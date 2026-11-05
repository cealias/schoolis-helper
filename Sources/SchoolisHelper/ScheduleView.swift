import SwiftUI
import SchoolisCore

// 课表模式：左栏是「现在 / 下一节」和今天的课，右边是一周的课表格子和考勤小表。
// 课表只同步本周和下周（再往后的老师也常常还没排好）。

private var calendar: Calendar { SchoolTime.calendar }

private let clock: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.timeZone = SchoolTime.zone
    f.dateFormat = "HH:mm"
    return f
}()

private let dayTitle: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.timeZone = SchoolTime.zone
    f.dateFormat = "M月d日 EEEE"
    return f
}()

private func timeRange(_ entry: ScheduleEntry) -> String {
    guard let begin = entry.beginDate, let end = entry.endDate else { return "" }
    return "\(clock.string(from: begin))–\(clock.string(from: end))"
}

/// 「08:30–09:10 · A101」；没写教室时只显示时间
private func timeAndRoom(_ entry: ScheduleEntry) -> String {
    entry.room.isEmpty ? timeRange(entry) : "\(timeRange(entry)) · \(entry.room)"
}

// MARK: - 左栏

struct ScheduleSidebar: View {
    @ObservedObject var store: Store

    var body: some View {
        let entries = store.snapshot?.schedule ?? []
        let (day, list) = displayDay(entries)
        VStack(alignment: .leading, spacing: 0) {
            NowCard(entries: entries, now: store.now)

            SidebarHeader(title: day.map { (calendar.isDateInToday($0) ? "今天 · " : "下一个上课日 · ") + dayTitle.string(from: $0) } ?? "课程")
            if list.isEmpty {
                Text(entries.isEmpty ? "还没有课表数据，点右上角的同步按钮同步一次。" : "这两周没有课了。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            VStack(spacing: 1) {
                ForEach(list) { entry in
                    ClassRow(entry: entry, now: store.now)
                }
            }

            if let attendance = store.snapshot?.attendance {
                SidebarHeader(title: "考勤（本学期）")
                AttendanceMini(summary: attendance)
            }
        }
    }

    /// 今天还有课就显示今天；今天的课上完了（或者今天没课）就显示下一个上课日
    private func displayDay(_ entries: [ScheduleEntry]) -> (Date?, [ScheduleEntry]) {
        let now = store.now
        let byDay = Dictionary(grouping: entries.compactMap { e in e.beginDate.map { (calendar.startOfDay(for: $0), e) } },
                               by: { $0.0 })
        let today = calendar.startOfDay(for: now)
        if let todays = byDay[today]?.map(\.1), todays.contains(where: { ($0.endDate ?? .distantPast) > now }) {
            return (today, todays.sorted { $0.begin < $1.begin })
        }
        if let next = byDay.keys.filter({ $0 > today }).min() {
            return (next, (byDay[next] ?? []).map(\.1).sorted { $0.begin < $1.begin })
        }
        return (nil, [])
    }
}

/// 「正在上 / 下一节」卡片
struct NowCard: View {
    let entries: [ScheduleEntry]
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let todays = entries.filter { $0.beginDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false }
        let current = todays.first { ($0.beginDate ?? .distantFuture) <= now && now < ($0.endDate ?? .distantPast) }
        let next = todays.filter { ($0.beginDate ?? .distantPast) > now }.min { $0.begin < $1.begin }
        VStack(alignment: .leading, spacing: 6) {
            if let current {
                HStack {
                    VitraCaption("CURRENT CLASS", color: .green)
                    Spacer()
                    VitraCode("还有 \(minutes(until: current.endDate)) 分钟", tint: .green)
                }
                Text(current.name).font(.system(size: 19, weight: .heavy)).foregroundStyle(p.display)
                Text(current.room.isEmpty ? "无教室信息" : current.room)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(p.secondary)
            } else if let next {
                HStack {
                    VitraCaption("UPCOMING CLASS")
                    Spacer()
                    VitraCode("\(minutes(until: next.beginDate)) 分钟后", tint: .blue)
                }
                Text(next.name).font(.system(size: 19, weight: .heavy)).foregroundStyle(p.display)
                Text("\(next.beginDate.map { clock.string(from: $0) } ?? "")\(next.room.isEmpty ? "" : " · " + next.room)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(p.secondary)
            } else {
                HStack {
                    VitraCaption("SCHEDULE STATUS")
                    Spacer()
                }
                Text(todays.isEmpty ? "今天没有课" : "今天的课上完了 🎉")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundStyle(p.display)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .vitraGlass(.widget, radius: 18)
    }

    private func minutes(until date: Date?) -> Int {
        guard let date else { return 0 }
        return max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
    }
}

/// 左栏的一节课：时间 + 课程 + 教室。上完的变淡，正在上的加粗
struct ClassRow: View {
    let entry: ScheduleEntry
    let now: Date
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let isNow = (entry.beginDate ?? .distantFuture) <= now && now < (entry.endDate ?? .distantPast)
        let isPast = (entry.endDate ?? .distantFuture) <= now
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2).fill(SubjectColor.of(entry.name)).frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.name)
                    .font(.system(size: 15, weight: isNow ? .bold : .regular))
                    .foregroundStyle(isNow ? p.display : p.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(timeAndRoom(entry))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(p.muted)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background {
            if isNow {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .opacity(isPast ? 0.45 : 1)
        .help("老师：\(entry.teachers.joined(separator: "、"))")
    }
}

/// 左栏的考勤小结
struct AttendanceMini: View {
    let summary: AttendanceSummary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(spacing: 0) {
            stat("出勤率", summary.rate.map { String(format: "%.1f%%", $0) } ?? "–", (summary.rate ?? 100) < 90 ? .red : p.display)
            stat("迟到", "\(summary.late)", summary.late > 0 ? .orange : p.display)
            stat("早退", "\(summary.earlyLeave)", summary.earlyLeave > 0 ? .orange : p.display)
            stat("缺勤", "\(summary.absent)", summary.absent > 0 ? .red : p.display)
        }
        .padding(.vertical, 10)
        .vitraGlass(.widget, radius: 14)
    }

    private func stat(_ title: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            VitraCaption(title)
            Text(value)
                .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                .foregroundStyle(tint)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 右边

struct ScheduleDetailView: View {
    @ObservedObject var store: Store

    var body: some View {
        let days = weekDays
        let entries = (store.snapshot?.schedule ?? []).filter { e in
            e.beginDate.map { d in days.contains { calendar.isDate($0, inSameDayAs: d) } } ?? false
        }
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if store.snapshot?.schedule == nil {
                    ContentUnavailableView("还没有课表数据", systemImage: "calendar",
                                           description: Text("点右上角的同步按钮同步一次。"))
                } else if entries.isEmpty {
                    ContentUnavailableView("这一周没有课", systemImage: "calendar",
                                           description: Text("可能是放假，或者老师还没排下周的课。"))
                } else {
                    WeekGrid(days: days, entries: entries, now: store.now)
                }
                if let attendance = store.snapshot?.attendance {
                    AttendanceTable(summary: attendance)
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(store: store) }
        .navigationTitle(store.scheduleWeek == 0 ? "本周课表" : "下周课表")
        .navigationSubtitle(weekText(days))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                VitraSegmented(options: [(title: "本周", value: 0), (title: "下周", value: 1)],
                               selection: store.scheduleWeek) { store.scheduleWeek = $0 }
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { SyncButton(store: store).buttonStyle(VitraRoundStyle()) }
                .sharedBackgroundVisibility(.hidden)
        }
    }

    /// 这一周的周一到周五；周末有课的话也带上
    private var weekDays: [Date] {
        guard let monday = calendar.dateInterval(of: .weekOfYear, for: store.now)?.start,
              let start = calendar.date(byAdding: .day, value: 7 * store.scheduleWeek, to: monday) else { return [] }
        let all = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
        let entries = store.snapshot?.schedule ?? []
        return all.enumerated().filter { index, day in
            index < 5 || entries.contains { $0.beginDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        }.map(\.element)
    }

    private func weekText(_ days: [Date]) -> String {
        guard let first = days.first, let last = days.last else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = SchoolTime.zone
        f.dateFormat = "M月d日"
        return "\(f.string(from: first)) – \(f.string(from: last))"
    }
}

/// 一周的课表格子：左边时间轴，每天一列，每节课按时间画成一个块。今天那一列高亮，红线是现在。
struct WeekGrid: View {
    let days: [Date]
    let entries: [ScheduleEntry]
    let now: Date

    private let hourHeight: CGFloat = 80
    private let axisWidth: CGFloat = 50

    var body: some View {
        let (startHour, endHour) = hourRange
        let todayIndex = days.firstIndex { calendar.isDateInToday($0) }
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                Color.clear.frame(width: axisWidth, height: 1)
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    let isToday = index == todayIndex
                    VStack(spacing: 1) {
                        Text(weekday(day)).font(.system(size: 14, weight: .semibold))
                        Text(monthDay(day)).font(.system(size: 12)).monospacedDigit()
                    }
                    .foregroundStyle(isToday ? Color.white : Color.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(isToday ? Color.accentColor : Color.clear))
                    .padding(.horizontal, 3)
                }
            }

            GeometryReader { geo in
                let columnWidth = (geo.size.width - axisWidth) / CGFloat(max(days.count, 1))
                let height = CGFloat(endHour - startHour) * hourHeight
                ZStack(alignment: .topLeading) {
                    if let todayIndex {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.06))
                            .frame(width: columnWidth, height: height)
                            .offset(x: axisWidth + CGFloat(todayIndex) * columnWidth)
                    }
                    ForEach(startHour...endHour, id: \.self) { hour in
                        let y = CGFloat(hour - startHour) * hourHeight
                        Path { path in
                            path.move(to: CGPoint(x: axisWidth, y: y))
                            path.addLine(to: CGPoint(x: geo.size.width, y: y))
                        }
                        .stroke(Color.primary.opacity(0.08))
                        Text(String(format: "%02d:00", hour))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .position(x: axisWidth / 2 - 2, y: y)
                    }
                    ForEach(entries) { entry in
                        if let dayIndex = days.firstIndex(where: { day in entry.beginDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }),
                           let begin = entry.beginDate, let end = entry.endDate {
                            let top = CGFloat(minutesSince(startHour, begin)) / 60 * hourHeight
                            let blockHeight = max(26, CGFloat(end.timeIntervalSince(begin) / 3600) * hourHeight - 2)
                            ClassBlock(entry: entry, isNow: begin <= now && now < end, isPast: end <= now)
                                .frame(width: columnWidth - 6, height: blockHeight)
                                .offset(x: axisWidth + CGFloat(dayIndex) * columnWidth + 3, y: top)
                        }
                    }
                    if let todayIndex {
                        let minutes = minutesSince(startHour, now)
                        if minutes >= 0 && minutes <= (endHour - startHour) * 60 {
                            let y = CGFloat(minutes) / 60 * hourHeight
                            Rectangle().fill(Color.red)
                                .frame(width: columnWidth, height: 2)
                                .offset(x: axisWidth + CGFloat(todayIndex) * columnWidth, y: y - 1)
                            Circle().fill(Color.red)
                                .frame(width: 8, height: 8)
                                .offset(x: axisWidth + CGFloat(todayIndex) * columnWidth - 4, y: y - 4)
                        }
                    }
                }
            }
            .frame(height: CGFloat(endHour - startHour) * hourHeight)
        }
    }

    /// 课表从几点画到几点：最早那节课所在的整点 ~ 最晚那节课结束后的整点
    private var hourRange: (Int, Int) {
        let begins = entries.compactMap { $0.beginDate.map { calendar.component(.hour, from: $0) } }
        let ends = entries.compactMap { $0.endDate.map { d -> Int in
            let h = calendar.component(.hour, from: d)
            return calendar.component(.minute, from: d) > 0 ? h + 1 : h
        } }
        return (min(begins.min() ?? 8, 8), max(ends.max() ?? 17, 15))
    }

    private func minutesSince(_ hour: Int, _ date: Date) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return ((parts.hour ?? 0) - hour) * 60 + (parts.minute ?? 0)
    }

    private func weekday(_ date: Date) -> String {
        ["周日", "周一", "周二", "周三", "周四", "周五", "周六"][calendar.component(.weekday, from: date) - 1]
    }

    private func monthDay(_ date: Date) -> String {
        "\(calendar.component(.month, from: date))/\(calendar.component(.day, from: date))"
    }
}

/// 课表格子里的一节课
struct ClassBlock: View {
    let entry: ScheduleEntry
    let isNow: Bool
    let isPast: Bool
    @Environment(\.colorScheme) private var scheme

    private func blockText(nameSize: CGFloat, timeSize: CGFloat, showTime: Bool, displayColor: Color, mutedColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(entry.name)
                .font(.system(size: nameSize, weight: .bold))
                .foregroundStyle(displayColor)
                .fixedSize(horizontal: false, vertical: true)
            if showTime {
                Text(timeAndRoom(entry))
                    .font(.system(size: timeSize, design: .monospaced))
                    .foregroundStyle(mutedColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .monospacedDigit()
            }
        }
    }

    var body: some View {
        let p = Vitra.palette(scheme)
        let color = SubjectColor.of(entry.name)
        ViewThatFits(in: .vertical) {
            blockText(nameSize: 13, timeSize: 11, showTime: true, displayColor: p.display, mutedColor: p.muted)
            blockText(nameSize: 12, timeSize: 10, showTime: true, displayColor: p.display, mutedColor: p.muted)
            blockText(nameSize: 12, timeSize: 10, showTime: false, displayColor: p.display, mutedColor: p.muted)
            Text(entry.name)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(p.display)
                .minimumScaleFactor(0.5)
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(isNow ? 0.38 : 0.18))
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3.5).padding(.vertical, 4).padding(.leading, 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isNow ? color : color.opacity(0.35), lineWidth: isNow ? 2 : 1)
        )
        .shadow(color: isNow ? color.opacity(0.4) : .clear, radius: 6, y: 2)
        .opacity(isPast ? 0.72 : 1)
        .help("\(entry.name)\n\(timeRange(entry))\n教室：\(entry.room.isEmpty ? "没写" : entry.room)\n老师：\(entry.teachers.joined(separator: "、"))")
    }
}

/// 考勤小表：每科出勤 / 迟到 / 早退 / 缺勤 / 出勤率
struct AttendanceTable: View {
    let summary: AttendanceSummary
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VitraPod(icon: "person.crop.circle.badge.checkmark", fill: Vitra.gradient(.teal), size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    VitraCaption("ATTENDANCE RECORDS")
                    Text("考勤").font(.system(size: 15, weight: .heavy)).foregroundStyle(p.display)
                }
                Text("本学期 \(summary.range)").font(.system(size: 12, design: .monospaced)).foregroundStyle(p.muted)
                Spacer()
                VitraCode("出勤率 \(summary.rate.map { String(format: "%.2f%%", $0) } ?? "–") · 共 \(summary.total) 次", tint: (summary.rate ?? 100) < 90 ? .red : .teal)
            }
            Grid(alignment: .leading, horizontalSpacing: 22, verticalSpacing: 9) {
                GridRow {
                    header("课程")
                    header("出勤").gridColumnAlignment(.trailing)
                    header("迟到").gridColumnAlignment(.trailing)
                    header("早退").gridColumnAlignment(.trailing)
                    header("缺勤").gridColumnAlignment(.trailing)
                    header("出勤率").gridColumnAlignment(.trailing)
                }
                Divider().opacity(0.35).gridCellUnsizedAxes(.horizontal)
                ForEach(summary.subjects.sorted { ($0.rate ?? 100) < ($1.rate ?? 100) }) { subject in
                    GridRow {
                        HStack(spacing: 8) {
                            Circle().fill(SubjectColor.of(subject.name)).frame(width: 8, height: 8)
                            Text(subject.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(p.primary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                        }
                        cell(subject.normal, p.primary)
                        cell(subject.late, subject.late > 0 ? .orange : p.muted)
                        cell(subject.earlyLeave, subject.earlyLeave > 0 ? .orange : p.muted)
                        cell(subject.absent, subject.absent > 0 ? .red : p.muted)
                        Text(subject.rate.map { String(format: "%.0f%%", $0) } ?? "–")
                            .font(.system(size: 14, weight: (subject.rate ?? 100) < 90 ? .heavy : .medium, design: .monospaced))
                            .foregroundStyle((subject.rate ?? 100) < 90 ? Color.red : p.display)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(20)
        .vitraGlass(.board, radius: 24)
    }

    private func header(_ text: String) -> some View {
        VitraCaption(text)
    }

    private func cell(_ value: Int, _ tint: Color) -> some View {
        Text("\(value)").font(.system(size: 14, design: .monospaced)).foregroundStyle(tint).monospacedDigit()
    }
}
