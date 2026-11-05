import SwiftUI
import SchoolisCore

// 「今天」：打开 App 第一眼看到的页面。
// 最上面是 AI 写的全局总结（作业、成绩、课表、考勤放在一起看）；
// 下面是程序算好的准确数字——AI 偶尔会说错，以这些为准。

/// 一个「做了能涨 GPA」的作业（首页用）
struct GPAMove: Identifiable {
    let subjectName: String
    let lever: GradeMath.Lever
    /// 做到了等级会变的话，比如「B → A」
    let change: String?
    let gpaAfter: Double
    var id: String { "\(subjectName)-\(lever.id)" }
}

private let dayTitle: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.timeZone = SchoolTime.zone
    f.dateFormat = "M月d日 EEEE"
    return f
}()

// MARK: - 左栏

struct TodaySidebar: View {
    @ObservedObject var store: Store

    var body: some View {
        let report = store.report
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(SmartList.allCases, id: \.self) { list in
                    SmartTile(list: list, count: Sections.count(.smart(list), report), selected: false) {
                        store.selection = .smart(list)
                        store.switchMode(.tasks)
                    }
                }
            }
            Button {
                store.gradeSelection = .plan
                store.switchMode(.grades)
            } label: {
                GPABar(store: store)
            }
            .buttonStyle(VitraPressStyle())
            .padding(.top, 8)
            .help("看提分计划")

            ScheduleSidebar(store: store)
                .padding(.top, 14)
        }
    }
}

// MARK: - 右边

private let captionDay: DateFormatter = {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = SchoolTime.zone
    f.dateFormat = "yyyy.MM.dd · EEE"
    return f
}()

struct TodayView: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    VitraCaption("Today · \(captionDay.string(from: store.now))")
                    Text(dayTitle.string(from: store.now))
                        .vitraDisplay(34, p)
                    Text(greeting)
                        .font(.system(size: 15))
                        .foregroundStyle(p.secondary)
                }

                AISummaryCard(store: store)

                VitraCaption("Precise Data · 程序算好的准确数字，AI 偶尔会说错，以这里为准")
                    .padding(.bottom, -10)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 18, alignment: .top)],
                          alignment: .leading, spacing: 18) {
                    dueCard
                    movesCard
                    rescueCard
                }
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(store: store) }
        .navigationTitle("今天")
        .navigationSubtitle(store.updatedText)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.generateSummary() }
                } label: {
                    Label("重新写总结", systemImage: "sparkles")
                }
                .disabled(store.aiBusy || store.snapshot == nil)
                .help("让 AI 重新写一份总结")
                .buttonStyle(VitraRoundStyle())
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { SyncButton(store: store).buttonStyle(VitraRoundStyle()) }
                .sharedBackgroundVisibility(.hidden)
        }
    }

    private var greeting: String {
        let hour = SchoolTime.calendar.component(.hour, from: store.now)
        let hello = hour < 11 ? "早上好" : hour < 14 ? "中午好" : hour < 18 ? "下午好" : "晚上好"
        let name = store.settings.nickname.trimmingCharacters(in: .whitespaces)
        return "\(hello)，\(name.isEmpty ? "同学" : name)。下面是今天最要紧的事。"
    }

    // MARK: 三张卡片

    private var dueCard: some View {
        let report = store.report
        let tasks = report.today + report.tomorrow
        return QuickCard(title: "今明两天要交", caption: "Due Soon", icon: "sun.max.fill", tint: .orange, count: tasks.count,
                         empty: "今明两天没有要交的作业 🎉") {
            ForEach(tasks.prefix(6)) { task in
                QuickRow(title: task.name, detail: "\(task.subjectName) · \(Format.shortDeadline(task)) 截止",
                         trailing: Format.relative(task.endDate ?? store.now, now: store.now),
                         trailingTint: SchoolTime.calendar.isDateInToday(task.endDate ?? .distantFuture) ? .red : .orange)
            }
        } more: {
            store.selection = .smart(.soon)
            store.switchMode(.tasks)
        }
    }

    private var movesCard: some View {
        let moves = store.derived.moves
        return QuickCard(title: "做了能涨分的作业", caption: "GPA Boost", icon: "chart.line.uptrend.xyaxis", tint: .green,
                         count: moves.count, empty: "没有找到能明显涨分的作业 👍") {
            ForEach(moves.prefix(5)) { move in
                QuickRow(title: move.lever.title,
                         detail: "\(move.subjectName) · " + (move.lever.kind == .redoTask ? "补交 / 重做拿满分" : "认真做拿满分"),
                         trailing: "+\(Format.number(move.lever.gain))" + (move.change.map { "  \($0)" } ?? ""),
                         trailingTint: .green)
            }
        } more: {
            store.gradeSelection = .plan
            store.switchMode(.grades)
        }
    }

    private var rescueCard: some View {
        let report = store.report
        let tasks = report.markedNotDone.filter { ($0.totalScore ?? 0) > 0 } + report.overdue
        return QuickCard(title: "要补救", caption: "Rescue", icon: "exclamationmark.triangle.fill", tint: .red,
                         count: tasks.count, empty: "没有要补救的作业 👍") {
            ForEach(tasks.prefix(6)) { task in
                QuickRow(title: task.name, detail: "\(task.subjectName) · \(Format.shortDeadline(task)) 截止",
                         trailing: task.finishState == 2 ? Format.points(task) : Format.relative(task.endDate ?? store.now, now: store.now),
                         trailingTint: .red)
            }
        } more: {
            store.selection = .smart(.rescue)
            store.switchMode(.tasks)
        }
    }
}

/// AI 总结：一整块大玻璃面板（VITRA 的 layer-1-board）
struct AISummaryCard: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                VitraPod(icon: "sparkles", fill: Vitra.violet, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    VitraCaption("AI Summary · 今日简报")
                    Text("AI 总结").font(.system(size: 17, weight: .heavy)).foregroundStyle(p.display)
                }
                Spacer()
                if store.aiBusy { ProgressView().controlSize(.small) }
                if let advice = store.aiAdvice {
                    VitraCode(advice.model)
                        .help(advice.provider ?? "本地模型")
                }
            }

            if let advice = store.aiAdvice {
                if let summary = advice.structured {
                    SummaryBody(summary: summary, tomorrowLabel: store.tomorrowHasClasses ? "明天" : "下次上课")
                } else {
                    // 旧格式（一大段文字）或者没按格式回答：显示原文
                    Text(markdown(advice.text))
                        .font(.system(size: 15.5))
                        .foregroundStyle(p.primary)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("写于 \(Format.syncTime.string(from: advice.createdAt))" +
                         (store.snapshot?.syncedAt != advice.basedOn ? " · 数据更新了，可以点右上角 ✨ 重新写" : ""))
                        .foregroundStyle(p.muted)
                    if let note = advice.note {
                        Text(note).foregroundStyle(.orange)
                    }
                }
                .font(.system(size: 11.5))
            } else if !store.aiBusy {
                Text(store.snapshot == nil ? "同步完数据以后，AI 会在这里写今天的总结。" : "还没有总结。")
                    .font(.system(size: 15))
                    .foregroundStyle(p.secondary)
                VitraSolidButton(title: "现在写一份", icon: "sparkles") {
                    Task { await store.generateSummary() }
                }
                .disabled(store.snapshot == nil)
            }

            if let status = store.aiStatus {
                Text(status)
                    .font(.system(size: 12.5))
                    .foregroundStyle(status.hasPrefix("AI 没能") ? Color.red : p.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if store.settings.aiProvider.isCloud && store.apiKeyHint == nil {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb.fill").foregroundStyle(.yellow)
                    Text("想要更聪明、更快的总结？可以在设置里填一个 AI 的 API Key。")
                    SettingsLink { Text("打开设置") }.buttonStyle(VitraLinkStyle())
                }
                .font(.system(size: 12.5))
                .foregroundStyle(p.secondary)
            }
        }
        .padding(26)
        .frame(maxWidth: .infinity, alignment: .leading)
        .vitraGlass(.board, radius: 32)
    }

    /// AI 回答里的 **加粗** 显示成加粗，换行保留
    private func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(text)
    }
}

/// AI 总结的正文：支持 AI 自由组合决策的动态卡片流（Blocks Flow）
/// 包含：一句话大字 Headline + AI 自主选择编排的 Alert / Todo / Boost / Schedule / Tip 等组件
struct SummaryBody: View {
    let summary: AISummary
    /// 明天不上学时写「下次上课」（AI 会写成「周一 08:30 …」）
    var tomorrowLabel = "明天"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        VStack(alignment: .leading, spacing: 16) {
            Text(summary.headline)
                .vitraDisplay(24, p)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            ForEach(summary.blocks) { block in
                SummaryBlockView(block: block, tomorrowLabel: tomorrowLabel)
            }
        }
    }
}

/// 动态组件调度器：将 AI 返回的各个 Block 映射到对应的高质感 VITRA 卡片
struct SummaryBlockView: View {
    let block: AISummaryBlock
    let tomorrowLabel: String

    var body: some View {
        switch block.type {
        case .alert:
            SummaryAlertCard(block: block)
        case .todo:
            SummaryTodoBlock(block: block)
        case .boost:
            SummaryBoostRow(action: block.action ?? block.title ?? "提分动作", result: block.result)
        case .schedule:
            SummaryScheduleRow(block: block, defaultLabel: tomorrowLabel)
        case .tip:
            SummaryTipRow(block: block)
        }
    }
}

/// 紧急警告卡（Alert）：红宝石/琥珀微光玻璃卡，用于未完成作业、严重逾期或缺勤预警
struct SummaryAlertCard: View {
    let block: AISummaryBlock
    @Environment(\.colorScheme) private var scheme

    private var isUrgent: Bool {
        block.level?.lowercased() == "urgent" || block.title?.contains("未完成") == true || block.title?.contains("紧急") == true
    }

    var body: some View {
        let p = Vitra.palette(scheme)
        let tintColor: Color = isUrgent ? .red : .orange
        let bgGradient = LinearGradient(colors: [tintColor.opacity(0.18), tintColor.opacity(0.08)],
                                        startPoint: .top, endPoint: .bottom)
        let glowGradient = LinearGradient(colors: [tintColor.opacity(0.35), tintColor.opacity(0.18)],
                                          startPoint: .leading, endPoint: .trailing)
        HStack(alignment: .top, spacing: 14) {
            VitraPod(icon: isUrgent ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill",
                     fill: Vitra.gradient(tintColor), size: 34)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(block.title ?? (isUrgent ? "紧急警告" : "注意事项"))
                        .font(.system(size: 15.5, weight: .bold))
                        .foregroundStyle(isUrgent ? .red : p.display)
                    Spacer()
                    VitraCode(isUrgent ? "🚨 紧急" : "⚠️ 注意", tint: tintColor)
                }
                if let detail = block.detail ?? block.action, !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(p.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .vitraGlass(.tinted(bgGradient, glow: glowGradient), radius: 24)
    }
}

/// 待办清单块（Todo Block）：包含清单小标题与带紫色序号舱的待办条目
struct SummaryTodoBlock: View {
    let block: AISummaryBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = block.title, !title.isEmpty {
                VitraCaption("Todo · \(title)")
                    .padding(.leading, 4)
            }
            if let items = block.items, !items.isEmpty {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    SummaryTodoRow(number: index + 1, item: item)
                }
            }
        }
    }
}

/// 「今天做」的一条：一块小玻璃，左边紫色序号舱，中间动作 + 科目 · 作业名，右边截止时间胶囊
struct SummaryTodoRow: View {
    let number: Int
    let item: AISummaryBlock.TodoItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(alignment: .center, spacing: 14) {
            Text("\(number)")
                .font(.system(size: 14, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Vitra.violet))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .clear],
                                                              startPoint: .top, endPoint: .bottom)))
                .shadow(color: Vitra.rgb(0x804AFF).opacity(0.35), radius: 5, y: 3)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.action)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(p.display)
                let detail = [item.subject, item.task].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(p.secondary)
                        .lineLimit(2)
                        .help(detail)
                }
                if let why = item.why, !why.isEmpty {
                    Text(why)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(whyTint(why))
                }
            }
            Spacer(minLength: 8)
            if let due = item.due, !due.isEmpty {
                VitraCode(due, tint: due.contains("过期") || due.contains("今天") ? .red : .orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .vitraGlass(.widget, radius: 20)
    }

    /// 掉分用橙色，涨分用绿色，其他用灰色
    private func whyTint(_ text: String) -> Color {
        if ["掉", "扣", "降", "−"].contains(where: text.contains) { return .orange }
        if ["涨", "+", "升", "满分"].contains(where: text.contains) { return .green }
        return Vitra.palette(scheme).muted
    }
}

/// 提分捷径：青色的光学胶囊（VITRA 的 Secondary 按钮那种）
struct SummaryBoostRow: View {
    let action: String
    let result: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Circle().fill(.white.opacity(0.22)))
                .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1)],
                                                              startPoint: .top, endPoint: .bottom)))
            VStack(alignment: .leading, spacing: 2) {
                VitraCaption("Boost · 提分捷径", color: .white.opacity(0.78))
                Text(action)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .shadow(color: Vitra.rgb(0x0A4844).opacity(0.28), radius: 1, y: 1)
            Spacer(minLength: 8)
            if let result = result, !result.isEmpty {
                Text(result)
                    .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Vitra.rgb(0x0E5F58))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(.white.opacity(0.92)))
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .vitraGlass(.tinted(Vitra.teal, glow: Vitra.tealGlow), radius: 26)
    }
}

/// 日程/课程预告（Schedule）：小玻璃胶囊
struct SummaryScheduleRow: View {
    let block: AISummaryBlock
    var defaultLabel = "明天"
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let label = block.title ?? defaultLabel
        let content = [block.time, block.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        HStack(spacing: 10) {
            VitraPod(icon: "calendar", fill: Vitra.gradient(.blue), size: 26)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(p.muted)
            Text(content.isEmpty ? (block.action ?? "") : content)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(p.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .vitraGlass(.widget, radius: 22)
    }
}

/// 学长贴士/建议（Tip）：温润金黄玻璃微光胶囊
struct SummaryTipRow: View {
    let block: AISummaryBlock
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let tipText = block.detail ?? block.action ?? ""
        HStack(spacing: 10) {
            VitraPod(icon: "lightbulb.fill", fill: Vitra.gradient(.yellow), size: 26)
            if let title = block.title, !title.isEmpty {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.yellow)
            }
            Text(tipText)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(p.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .vitraGlass(.widget, radius: 22)
    }
}

/// 「下次上课」这种一行的信息：小玻璃胶囊（保留向后兼容）
struct SummaryInfoRow: View {
    let icon: String
    let tint: Color
    let label: String
    let text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(spacing: 10) {
            VitraPod(icon: icon, fill: Vitra.gradient(tint), size: 26)
            Text(label)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(p.muted)
            Text(text)
                .font(.system(size: 14.5, weight: .medium))
                .foregroundStyle(p.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .vitraGlass(.widget, radius: 22)
    }
}

/// 首页下面的小卡片：一块玻璃，标题栏有图标舱、数字胶囊和「全部」按钮
struct QuickCard<Content: View>: View {
    let title: String
    let caption: String
    let icon: String
    let tint: Color
    let count: Int
    let empty: String
    @ViewBuilder var content: () -> Content
    let more: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                VitraPod(icon: icon, fill: Vitra.gradient(tint), size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    VitraCaption(caption)
                    Text(title).font(.system(size: 15, weight: .heavy)).foregroundStyle(p.display)
                }
                VitraCode("\(count)", tint: count > 0 ? tint : nil)
                Spacer()
                VitraSolidButton(title: "全部", action: more)
            }
            if count == 0 {
                Text(empty).font(.system(size: 14)).foregroundStyle(p.secondary)
            } else {
                VStack(alignment: .leading, spacing: 9) { content() }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .vitraGlass(.widget, radius: 26)
    }
}

struct QuickRow: View {
    let title: String
    let detail: String
    let trailing: String
    let trailingTint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(p.primary).lineLimit(2)
                Text(detail).font(.system(size: 12)).foregroundStyle(p.muted).lineLimit(2)
            }
            Spacer(minLength: 6)
            Text(trailing)
                .font(.system(size: 12.5, weight: .bold, design: .monospaced))
                .foregroundStyle(trailingTint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .help(title)
    }
}
