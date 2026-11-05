import SwiftUI
import SchoolisCore

// 成绩模式：左栏是 GPA 和各科，右边是「提分计划」或者某一科的详情。
// 所有数字都由 GradeMath 按学校的规则算出来（和学校给的分逐科核对过）；AI 只负责把建议说成人话。

/// 等级的颜色：A 段绿、B 段蓝、C 段橙、D 和 F 红
func levelTint(_ name: String) -> Color {
    switch name.first {
    case "A": return .green
    case "B": return .blue
    case "C": return .orange
    default: return .red
    }
}

// MARK: - 左栏

struct GradesSidebar: View {
    @ObservedObject var store: Store
    let roomy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GPATargetCard(store: store)

            SidebarHeader(title: "提分")
            SidebarItemRow(icon: "chart.line.uptrend.xyaxis", title: "提分计划",
                           trailing: planHint, selected: store.gradeSelection == .plan, roomy: roomy) {
                store.gradeSelection = .plan
            }

            if !store.gradeSubjects.isEmpty {
                SidebarHeader(title: "各科（分数低的在上面）")
                VStack(spacing: 1) {
                    ForEach(store.gradeSubjects) { subject in
                        GradeSubjectRow(subject: subject, bands: store.grades?.bands ?? [],
                                        selected: store.gradeSelection == .subject(subject.id), roomy: roomy) {
                            store.gradeSelection = .subject(subject.id)
                        }
                    }
                }
            } else {
                Text(store.syncing ? "正在同步成绩…" : "还没有成绩数据，点右上角的同步按钮同步一次。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
        }
    }

    private var planHint: String {
        guard let plan = store.gradePlan else { return "" }
        return plan.alreadyThere ? "已达标" : "差 \(String(format: "%.2f", max(0, plan.target - GradeMath.floor2(plan.currentGPA))))"
    }
}

/// GPA 大卡片：官网 GPA + 目标（可以调）
struct GPATargetCard: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VitraCaption("DYNAMIC GPA")
                Spacer()
                Text(store.syncing ? "正在同步…" : store.updatedText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(store.lastError == nil ? p.muted : Color.red)
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(store.snapshot?.gpa.map { String(format: "%.2f", $0) } ?? "–")
                    .vitraDisplay(32, p)
                    .monospacedDigit()
                Spacer()
                Stepper(value: Binding(get: { store.settings.targetGPA },
                                       set: { value in store.updateSettings { $0.targetGPA = (value * 100).rounded() / 100 } }),
                        in: 3.0...4.3, step: 0.05) {
                    Text("目标 \(String(format: "%.2f", store.settings.targetGPA))")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundStyle(p.primary)
                        .monospacedDigit()
                }
                .help("调整目标 GPA，右边的提分计划会跟着重新算")
            }
            if !store.gpaMatchesOfficial, let mine = store.computedGPA {
                Text("⚠️ 按学校规则算出来是 \(String(format: "%.2f", GradeMath.floor2(mine)))，和官网对不上，下面的推算仅供参考。")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .vitraGlass(.widget, radius: 18)
    }
}

/// 左栏里的一个普通入口（图标 + 名字 + 右边一点提示）
struct SidebarItemRow: View {
    let icon: String
    let title: String
    var trailing = ""
    let selected: Bool
    let roomy: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.blue)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: roomy ? 16 : 15, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? p.display : p.primary)
                Spacer()
                if !trailing.isEmpty {
                    Text(trailing)
                        .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(selected ? p.display : p.muted)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, roomy ? 8 : 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(p.widget)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [p.borderTop, p.borderRB], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        )
                        .shadow(color: p.shadow, radius: 4, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VitraPressStyle())
    }
}

/// 左栏的一科：圆点 + 科目名 + 分数 + 等级
struct GradeSubjectRow: View {
    let subject: SubjectGrade
    let bands: [LevelBand]
    let selected: Bool
    let roomy: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let band = subject.score.flatMap { GradeMath.band(for: $0, in: bands) }
        Button(action: action) {
            HStack(spacing: 10) {
                Circle().fill(SubjectColor.of(subject.name)).frame(width: 10, height: 10)
                Text(subject.name)
                    .font(.system(size: roomy ? 16 : 15, weight: selected ? .bold : .regular))
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .foregroundStyle(subject.isInGrade ? (selected ? p.display : p.primary) : p.muted)
                Spacer(minLength: 6)
                Text(subject.score.map { Format.number($0) } ?? "–")
                    .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(selected ? p.display : p.primary)
                Text(band?.name ?? "")
                    .font(.system(size: 11.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(minWidth: 26)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(levelTint(band?.name ?? "F").opacity(subject.isInGrade ? 0.9 : 0.4)))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, roomy ? 7 : 5)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(p.widget)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [p.borderTop, p.borderRB], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        )
                        .shadow(color: p.shadow, radius: 4, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VitraPressStyle())
        .help(subject.isInGrade ? "\(subject.name)：\(subject.score.map { Format.number($0) } ?? "–") 分，\(band?.name ?? "") \(band.map { Format.number($0.gpa) } ?? "")" : "\(subject.name)：不计入 GPA")
    }
}

// MARK: - 右边

struct GradesDetailView: View {
    @ObservedObject var store: Store

    var body: some View {
        Group {
            if store.grades == nil {
                ContentUnavailableView {
                    Label(store.syncing ? "正在同步成绩…" : "还没有成绩数据", systemImage: "chart.bar.doc.horizontal")
                } description: {
                    Text("第一次同步成绩要多读一些作业详情，大约 1 分钟。")
                }
            } else {
                switch store.gradeSelection {
                case .plan:
                    GradePlanView(store: store)
                case .subject(let id):
                    if let subject = store.grades?.subjects.first(where: { $0.id == id }) {
                        SubjectGradeView(store: store, subject: subject)
                    } else {
                        GradePlanView(store: store)
                    }
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { StatusBanner(store: store) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.openSchoolWebsite()
                } label: {
                    Label("校宝网页", systemImage: "safari")
                }
                .buttonStyle(VitraRoundStyle())
                .help("在浏览器里打开校宝")
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) { SyncButton(store: store).buttonStyle(VitraRoundStyle()) }
                .sharedBackgroundVisibility(.hidden)
        }
    }
}

// MARK: 提分计划

struct GradePlanView: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let plan = store.gradePlan
        let grades = store.grades
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let plan {
                    // 卡片 1：目标达成总览
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            VitraPod(icon: "target", fill: Vitra.gradient(.blue), size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                VitraCaption("GOAL PROGRESS")
                                Text("目标达成推算").font(.system(size: 15, weight: .heavy)).foregroundStyle(p.display)
                            }
                            Spacer()
                            if plan.alreadyThere {
                                VitraCode("已达标", tint: .green)
                            }
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            BigNumber(title: "现在（官网）", value: store.snapshot?.gpa.map { String(format: "%.2f", $0) } ?? "–")
                            Image(systemName: "arrow.right")
                                .font(.title2.weight(.bold))
                                .foregroundStyle(p.muted)
                            BigNumber(title: "目标 GPA", value: String(format: "%.2f", plan.target))
                            Spacer()
                        }

                        Text(summary(plan))
                            .font(.system(size: 14.5, weight: .medium))
                            .foregroundStyle(p.primary)
                            .fixedSize(horizontal: false, vertical: true)

                        Text("规则：计入成绩的 \(plan.subjectCount) 科，每科按分数段换成绩点（A+ 4.3、A 4.0、A- 3.7、B+ 3.3、B 3.0……），再取平均。在左栏可以调目标。")
                            .font(.system(size: 12))
                            .foregroundStyle(p.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .vitraGlass(.board, radius: 24)

                    // 卡片 2：捷径（一个作业就够）
                    let shortcuts = store.derived.moves.filter { $0.lever.kind != .weakItem && $0.gpaAfter + 1e-9 >= plan.target }
                    if !plan.alreadyThere && !shortcuts.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                VitraPod(icon: "bolt.fill", fill: Vitra.teal, size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    VitraCaption("SHORTCUT MOVE")
                                    Text("提分捷径：一个作业就够")
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundStyle(p.display)
                                }
                                Spacer()
                            }

                            VStack(spacing: 8) {
                                ForEach(shortcuts.prefix(2)) { move in
                                    Button {
                                        if let subject = grades?.subjects.first(where: { $0.name == move.subjectName }) {
                                            store.gradeSelection = .subject(subject.id)
                                        }
                                    } label: {
                                        ShortcutRow(move: move)
                                            .padding(12)
                                            .vitraGlass(.widget, radius: 16)
                                    }
                                    .buttonStyle(VitraPressStyle())
                                }
                            }

                            Text("这个作业拿满分，这科能连升好几级，比下面的方案省事。补交 / 重做要先问老师同不同意。")
                                .font(.system(size: 12))
                                .foregroundStyle(p.muted)
                                .padding(.leading, 4)
                        }
                        .padding(20)
                        .vitraGlass(.board, radius: 24)
                    }

                    // 卡片 3：最省力的方案
                    if !plan.alreadyThere {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                VitraPod(icon: "slider.horizontal.3", fill: Vitra.gradient(.purple), size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    VitraCaption("OPTIMAL PLANS")
                                    Text("最省力的方案（按要提的总分从少到多）")
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundStyle(p.display)
                                }
                                Spacer()
                            }

                            if plan.options.isEmpty {
                                Text(plan.reachable ? "要同时提高 4 科以上才够，试试把目标调低一点。" : "就算所有科目都提到最高等级也到不了这个目标。")
                                    .font(.system(size: 14))
                                    .foregroundStyle(p.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                VStack(spacing: 10) {
                                    ForEach(Array(plan.options.enumerated()), id: \.element.id) { index, option in
                                        PlanOptionView(store: store, index: index, option: option)
                                            .padding(14)
                                            .vitraGlass(.widget, radius: 18)
                                    }
                                }
                            }

                            Text("「要提的分」是这科动态总分要涨多少。每一步下面写了这科最快的涨分办法，点科目名能看详情。")
                                .font(.system(size: 12))
                                .foregroundStyle(p.muted)
                                .padding(.leading, 4)
                        }
                        .padding(20)
                        .vitraGlass(.board, radius: 24)
                    }
                }

                // 卡片 4：各科离下一级还差多少
                if let grades {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            VitraPod(icon: "chart.bar.xaxis", fill: Vitra.gradient(.orange), size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                VitraCaption("NEXT LEVEL DISTANCE")
                                Text("各科离下一级还差多少")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(p.display)
                            }
                            Spacer()
                        }

                        VStack(spacing: 6) {
                            ForEach(stepRows(grades), id: \.subject.id) { row in
                                Button {
                                    store.gradeSelection = .subject(row.subject.id)
                                } label: {
                                    StepRow(row: row)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .vitraGlass(.widget, radius: 14)
                                }
                                .buttonStyle(VitraPressStyle())
                            }
                        }
                    }
                    .padding(20)
                    .vitraGlass(.board, radius: 24)
                }

                // AI 全局总结入口卡片
                HStack(spacing: 12) {
                    VitraPod(icon: "sparkles", fill: Vitra.violet, size: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        VitraCaption("AI ADVICE")
                        Text("AI 的全局总结（作业、成绩、课表一起看）在「今天」页")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(p.display)
                    }
                    Spacer()
                    Button("去看看") { store.switchMode(.today) }
                        .buttonStyle(VitraPrimaryStyle())
                }
                .padding(18)
                .vitraGlass(.board, radius: 22)
            }
            .padding(20)
        }
        .navigationTitle("提分计划")
        .navigationSubtitle("目标 GPA " + String(format: "%.2f", store.settings.targetGPA))
    }

    private func summary(_ plan: GradeMath.GPAPlan) -> String {
        if plan.alreadyThere {
            return "已经达到目标了 🎉 想再往上，就在左栏把目标调高试试。"
        }
        let need = (plan.target - plan.currentGPA) * Double(plan.subjectCount)
        let levels = Int(ceil(need / 0.3 - 0.001))
        let extra = levels > 1 ? "（或者有一科连升好几级）" : ""
        let needStr = String(format: "%.1f", need + 0.0499)
        return "\(plan.subjectCount) 科的绩点加起来还差 \(needStr)。一科升一级能加 0.3 或 0.4，所以大约要 \(levels) 科各升一级\(extra)。"
    }

    struct StepInfo {
        let subject: SubjectGrade
        let band: LevelBand
        let next: GradeMath.LevelStep?
    }

    private func stepRows(_ grades: GradeData) -> [StepInfo] {
        grades.subjects.filter { $0.isInGrade && $0.score != nil }.compactMap { subject in
            guard let s = subject.score, let band = GradeMath.band(for: s, in: grades.bands) else { return nil }
            return StepInfo(subject: subject, band: band,
                            next: GradeMath.steps(for: subject, bands: grades.bands, maxSteps: 1).first)
        }
        .sorted { ($0.next?.delta ?? 999) < ($1.next?.delta ?? 999) }
    }
}

struct BigNumber: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        VStack(alignment: .leading, spacing: 2) {
            VitraCaption(title)
            Text(value)
                .font(.system(size: 28, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(p.display)
        }
    }
}

/// 一个提分方案：几科、各提到哪一级，每一步下面写最快的办法
struct PlanOptionView: View {
    @ObservedObject var store: Store
    let index: Int
    let option: GradeMath.PlanOption
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("方案 \(index + 1)").font(.system(size: 15, weight: .heavy)).foregroundStyle(p.display)
                VitraCode("总共提 \(Format.number(option.totalDelta)) 分", tint: .orange)
                Spacer()
                Text("完成后 GPA ≈ " + String(format: "%.2f", GradeMath.floor2(option.resultingGPA)))
                    .font(.system(size: 14, weight: .heavy, design: .monospaced))
                    .foregroundStyle(.green)
            }
            ForEach(option.steps, id: \.self) { step in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Circle().fill(SubjectColor.of(step.subjectName)).frame(width: 9, height: 9)
                        Button(step.subjectName) {
                            store.gradeSelection = .subject(step.subjectId)
                        }
                        .buttonStyle(VitraLinkStyle())
                        .font(.system(size: 15, weight: .bold))
                        Text("\(Format.number(step.currentScore)) → \(Format.number(step.to.min))")
                            .font(.system(size: 14, design: .monospaced))
                            .foregroundStyle(p.primary)
                        VitraCode("\(step.from.name) → \(step.to.name)", tint: .blue)
                        Spacer()
                        Text("+\(Format.number(step.delta)) 分")
                            .font(.system(size: 14, weight: .heavy, design: .monospaced))
                            .foregroundStyle(.orange)
                    }
                    if let hint = hint(for: step) {
                        Text(hint)
                            .font(.system(size: 12.5))
                            .foregroundStyle(p.secondary)
                            .padding(.leading, 17)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func hint(for step: GradeMath.LevelStep) -> String? {
        guard let subject = store.grades?.subjects.first(where: { $0.id == step.subjectId }) else { return nil }
        var parts: [String] = []
        if let lever = store.levers(for: subject).max(by: { $0.gain < $1.gain }), lever.gain > 0 {
            let what: String
            switch lever.kind {
            case .weakItem: what = "把「\(lever.path)」提上去（满分能 +\(Format.number(lever.gain))）"
            case .redoTask: what = "补交或重做「\(lever.title)」（满分能 +\(Format.number(lever.gain))）"
            case .pendingTask: what = "认真做「\(lever.title)」（满分能 +\(Format.number(lever.gain))）"
            }
            parts.append("最快：" + what)
        }
        if let future = store.futureNeed(for: subject),
           let need = future.needs.first(where: { $0.band == step.to }) {
            parts.append(need.average.map { "或者等还没出分的项目（\(future.items.count) 项，最后占 \(Format.number(future.share))%）平均考到 \(Format.number($0))" }
                         ?? "光靠还没出分的项目考满分也不够")
        }
        return parts.isEmpty ? nil : parts.joined(separator: "；")
    }
}

/// 「捷径：一个作业就够」的一行
struct ShortcutRow: View {
    let move: GPAMove
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(spacing: 12) {
            VitraPod(icon: "bolt.fill", fill: Vitra.gradient(.orange), size: 30)
            VStack(alignment: .leading, spacing: 3) {
                let act = move.lever.kind == .redoTask ? "补交 / 重做" : "认真做完"
            Text("\(move.subjectName)：\(act)「\(move.lever.title)」拿满分")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(p.display)
                    .fixedSize(horizontal: false, vertical: true)
                Text("这科 +\(Format.number(move.lever.gain)) 分" + (move.change.map { "，等级 \($0)" } ?? ""))
                    .font(.system(size: 13))
                    .foregroundStyle(p.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                VitraCaption("GPA AFTER")
                Text(String(format: "%.2f", move.gpaAfter))
                    .font(.system(size: 18, weight: .heavy, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(p.muted)
        }
        .contentShape(Rectangle())
    }
}

/// 「各科离下一级还差多少」的一行
struct StepRow: View {
    let row: GradePlanView.StepInfo
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(spacing: 10) {
            Circle().fill(SubjectColor.of(row.subject.name)).frame(width: 10, height: 10)
            Text(row.subject.name)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(p.primary)
            Spacer()
            Text(row.subject.score.map { Format.number($0) } ?? "–")
                .font(.system(size: 14.5, weight: .medium, design: .monospaced))
                .foregroundStyle(p.display)
            Text(row.band.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(levelTint(row.band.name)))
            if let next = row.next {
                Text("→ \(next.to.name) 差 \(Format.number(next.delta)) 分")
                    .font(.system(size: 13.5, design: .monospaced))
                    .foregroundStyle(.orange)
                    .frame(width: 130, alignment: .trailing)
                Text("+\(Format.number(next.gpaGain)) GPA")
                    .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(p.muted)
                    .frame(width: 75, alignment: .trailing)
            } else {
                Text("已达最高级")
                    .font(.system(size: 13.5))
                    .foregroundStyle(p.muted)
                    .frame(width: 205, alignment: .trailing)
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(p.muted)
        }
        .contentShape(Rectangle())
    }
}

// MARK: 一科的详情

struct SubjectGradeView: View {
    @ObservedObject var store: Store
    let subject: SubjectGrade
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let bands = store.grades?.bands ?? []
        let band = subject.score.flatMap { GradeMath.band(for: $0, in: bands) }
        let levers = store.levers(for: subject)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 卡片 1：当前概况
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 20) {
                        BigNumber(title: "动态总分", value: subject.score.map { Format.number($0) } ?? "–")
                        BigNumber(title: "当前等级", value: band?.name ?? "–")
                        BigNumber(title: "当前绩点", value: band.map { Format.number($0.gpa) } ?? "–")
                        Spacer()
                        if let next = GradeMath.steps(for: subject, bands: bands, maxSteps: 1).first {
                            VStack(alignment: .trailing, spacing: 2) {
                                VitraCaption("NEXT LEVEL (\(next.to.name))")
                                Text("还差 \(Format.number(next.delta)) 分")
                                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                    if !subject.isInGrade {
                        Text("这一科不计入 GPA。").font(.system(size: 13)).foregroundStyle(p.muted)
                    }
                }
                .padding(20)
                .vitraGlass(.board, radius: 24)

                // 卡片 2：怎么涨分
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        VitraPod(icon: "arrow.up.circle.fill", fill: Vitra.gradient(.green), size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            VitraCaption("HOW TO GAIN POINTS")
                            Text("怎么涨分（按能涨多少排）")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(p.display)
                        }
                        Spacer()
                        VitraCode("\(levers.count) 项建议", tint: .green)
                    }

                    if levers.isEmpty {
                        Text("这科没发现明显能涨分的地方 👍").font(.system(size: 14.5)).foregroundStyle(p.secondary)
                            .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(Array(levers.prefix(8).enumerated()), id: \.element.id) { index, lever in
                                if index > 0 {
                                    Divider().opacity(0.3)
                                }
                                LeverRow(lever: lever, change: levelChange(lever, bands: bands))
                            }
                        }
                    }

                    Text("「能涨」是这科动态总分预计的变化，按学校的算法算的。作业能不能补交、重做要问老师。")
                        .font(.system(size: 12))
                        .foregroundStyle(p.muted)
                        .padding(.leading, 4)
                }
                .padding(20)
                .vitraGlass(.board, radius: 24)

                // 卡片 3：还没出分的项目
                if let future = store.futureNeed(for: subject) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 10) {
                            VitraPod(icon: "hourglass", fill: Vitra.gradient(.purple), size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                VitraCaption("PENDING ASSESSMENTS")
                                Text("还没出分的项目（最后占 \(Format.number(future.share))%）")
                                    .font(.system(size: 15, weight: .heavy))
                                    .foregroundStyle(p.display)
                            }
                            Spacer()
                        }

                        Text("包含项目：" + future.items.joined(separator: "、"))
                            .font(.system(size: 13.5))
                            .foregroundStyle(p.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        VStack(spacing: 8) {
                            ForEach(future.needs, id: \.band) { need in
                                HStack {
                                    Text(need.band == band ? "保住 \(need.band.name)（≥\(Format.number(need.band.min))）" : "升到 \(need.band.name)（≥\(Format.number(need.band.min))）")
                                        .font(.system(size: 14.5, weight: .semibold))
                                        .foregroundStyle(p.primary)
                                    Spacer()
                                    Text(need.average.map { "平均要考 \(Format.number($0)) 分" } ?? "满分也到不了")
                                        .font(.system(size: 14.5, weight: .bold, design: .monospaced))
                                        .foregroundStyle(need.average == nil ? p.muted : (need.average! >= 95 ? Color.orange : Color.green))
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .vitraGlass(.widget, radius: 12)
                            }
                        }
                    }
                    .padding(20)
                    .vitraGlass(.board, radius: 24)
                }

                // 卡片 4：成绩构成
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        VitraPod(icon: "list.bullet.indent", fill: Vitra.gradient(.blue), size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            VitraCaption("GRADE BREAKDOWN")
                            Text("成绩构成")
                                .font(.system(size: 15, weight: .heavy))
                                .foregroundStyle(p.display)
                        }
                        Spacer()
                    }

                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 {
                                Divider().opacity(0.3)
                            }
                            ItemRow(row: row)
                                .padding(.vertical, 6)
                        }
                    }

                    Text("每一项的分 = 下面已出分的项目按权重加权平均（还没出分的不算），每层保留 1 位小数。和学校的算法逐科核对过。")
                        .font(.system(size: 12))
                        .foregroundStyle(p.muted)
                        .padding(.leading, 4)
                }
                .padding(20)
                .vitraGlass(.board, radius: 24)
            }
            .padding(20)
        }
        .navigationTitle(subject.name)
        .navigationSubtitle(subject.isInGrade ? "计入 GPA" : "不计入 GPA")
    }

    private func levelChange(_ lever: GradeMath.Lever, bands: [LevelBand]) -> String? {
        guard let score = subject.score, let from = GradeMath.band(for: score, in: bands),
              let to = GradeMath.band(for: score + lever.gain, in: bands), to != from else { return nil }
        return "\(from.name) → \(to.name)"
    }

    private var rows: [ItemRowModel] {
        var result: [ItemRowModel] = []
        let tasks = (store.snapshot?.tasks ?? []).filter { $0.subjectName == subject.name }
        let taskItems = store.snapshot?.taskItems ?? [:]
        func walk(_ items: [ScoreItem], depth: Int) {
            for item in items {
                result.append(ItemRowModel(id: "i\(item.id)-\(depth)-\(result.count)", depth: depth, item: item, task: nil))
                if item.isLeaf {
                    let mine = tasks.filter { (taskItems[String($0.id)] ?? []).contains(item.id) }
                        .sorted { ($0.endTime ?? "") > ($1.endTime ?? "") }
                    for task in mine {
                        result.append(ItemRowModel(id: "t\(task.id)-\(result.count)", depth: depth + 1, item: nil, task: task))
                    }
                } else {
                    walk(item.children, depth: depth + 1)
                }
            }
        }
        walk(subject.items, depth: 0)
        return result
    }
}

struct LeverRow: View {
    let lever: GradeMath.Lever
    var change: String? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(lever.title).font(.system(size: 15, weight: .bold)).foregroundStyle(p.display)
                Text("\(lever.path) · \(lever.detail)")
                    .font(.system(size: 12.5))
                    .foregroundStyle(p.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            VStack(alignment: .trailing, spacing: 2) {
                Text("+\(Format.number(lever.gain))")
                    .font(.system(size: 17, weight: .heavy, design: .rounded))
                    .foregroundStyle(lever.gain > 0 ? Color.green : p.secondary)
                    .monospacedDigit()
                if let change {
                    Text("升级 \(change)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.green))
                }
                if lever.loss > 0 {
                    Text("不交 −\(Format.number(lever.loss))")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.red)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private var icon: String {
        switch lever.kind {
        case .weakItem: return "chart.bar.fill"
        case .redoTask: return "arrow.counterclockwise.circle.fill"
        case .pendingTask: return "square.and.pencil"
        }
    }

    private var tint: Color {
        switch lever.kind {
        case .weakItem: return .blue
        case .redoTask: return .orange
        case .pendingTask: return .purple
        }
    }
}

struct ItemRowModel {
    let id: String
    let depth: Int
    let item: ScoreItem?
    let task: LearningTask?
}

/// 成绩构成的一行：项目（名字、权重、分、等级），或者算在项目里的一个作业
struct ItemRow: View {
    let row: ItemRowModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(spacing: 8) {
            if let item = row.item {
                Text(item.name)
                    .font(.system(size: row.depth == 0 ? 15 : 14, weight: row.depth == 0 ? .heavy : .medium))
                    .foregroundStyle(row.depth == 0 ? p.display : p.primary)
                Text("\(Format.number(item.proportion))%")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(p.muted)
                Spacer()
                if let score = item.score {
                    Text(Format.number(score))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(p.display)
                        .monospacedDigit()
                    Text(item.level)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(levelTint(item.level)))
                } else {
                    Text("未出分").font(.system(size: 13)).foregroundStyle(p.muted)
                    Text("").frame(width: 28)
                }
            } else if let task = row.task {
                Image(systemName: "doc.text")
                    .font(.system(size: 11))
                    .foregroundStyle(p.muted)
                Text(task.name)
                    .font(.system(size: 13))
                    .foregroundStyle(p.secondary)
                    .lineLimit(2)
                Spacer()
                Text(taskScore(task))
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(taskTint(task))
                    .monospacedDigit()
                Text("").frame(width: 28)
            }
        }
        .padding(.leading, CGFloat(row.depth) * 20)
    }

    private func taskScore(_ task: LearningTask) -> String {
        let total = task.totalScore ?? 0
        if task.learningTaskState != 4 { return total > 0 ? "未批改 /\(Format.number(total))" : "未批改" }
        return total > 0 ? "\(Format.number(task.score ?? 0))/\(Format.number(total))" : "不计分"
    }

    private func taskTint(_ task: LearningTask) -> Color {
        guard task.learningTaskState == 4 else { return .secondary }
        return Format.scoreTint(task)
    }
}