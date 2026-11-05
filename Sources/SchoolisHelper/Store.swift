import AppKit
import SwiftUI
import SchoolisCore

/// 「弹窗」方式的提醒，显示在主窗口最上面
struct AlertMessage: Identifiable, Equatable {
    let id: String
    let title: String
    let body: String
}

/// 作业页左栏的分法
enum TaskGrouping: String, CaseIterable {
    case subject, category

    var title: String { self == .subject ? "科目" : "类型" }
}

/// 主窗口的四种模式（侧边栏顶上切换）
enum AppMode: String, CaseIterable, Hashable {
    case today, tasks, grades, schedule
    var title: String {
        switch self {
        case .today: return "今天"
        case .tasks: return "作业"
        case .grades: return "成绩"
        case .schedule: return "课表"
        }
    }
    var icon: String {
        switch self {
        case .today: return "sparkles"
        case .tasks: return "checklist"
        case .grades: return "chart.bar.fill"
        case .schedule: return "calendar"
        }
    }
}

/// 成绩模式里选中的是「提分计划」还是某一科
enum GradeSelection: Hashable {
    case plan
    case subject(Int)
}

/// AI 写的全局总结（存下来，下次打开还在）
struct AIAdvice: Codable {
    let text: String
    let createdAt: Date
    let model: String
    let target: Double
    /// 用的是哪家的 AI（「智谱 GLM」「本地 Ollama」），旧文件里没有
    var provider: String?
    /// 比如「智谱没连上（原因），这次用的是本地模型」
    var note: String?
    /// 是根据哪次同步的数据写的（数据更新后要重新写）
    var basedOn: Date?
    /// 按固定格式读出来的总结（App 自己排版）。读不出来、或者是旧文件，就显示原文 text
    var structured: AISummary?
}

/// 算一次、用多次的东西：只在数据变了的时候重算。
/// 以前每次重画界面都要把作业分组、提分方案、涨分建议从头算一遍，切换页面就会卡一下。
struct Derived {
    var report = TodoReport()
    var taskSubjects: [String] = []
    /// 有作业的类型，按固定顺序（测验考试、作业练习……）
    var taskCategories: [TaskCategory] = []
    var gradePlan: GradeMath.GPAPlan?
    var gradeSubjects: [SubjectGrade] = []
    var levers: [Int: [GradeMath.Lever]] = [:]
    var futures: [Int: GradeMath.FutureNeed] = [:]
    var computedGPA: Double?
    /// 做了能涨分的作业，按「GPA 能涨多少、这科能涨多少」排好（首页用）
    var moves: [GPAMove] = []
}

/// App 的全部状态和动作：数据、同步、定时、提醒、设置。
@MainActor
final class Store: ObservableObject {
    @Published private(set) var snapshot: Snapshot? { didSet { refreshDerived() } }
    @Published private(set) var syncing = false
    @Published private(set) var lastError: String?
    @Published private(set) var selfReported: Set<Int> { didSet { refreshDerived() } }
    /// 「现在」每分钟更新一次，让「还剩 X 小时」「逾期 X 天」跟着变
    @Published private(set) var now = Date() { didSet { refreshDerived() } }
    @Published private(set) var settings: AppSettings {
        didSet {
            if settings.targetGPA != oldValue.targetGPA { refreshDerived() }
            if settings.aiProvider != oldValue.aiProvider { refreshAPIKeyHint() }
        }
    }
    @Published private(set) var derived = Derived()
    @Published private(set) var scheduleError: String?
    @Published private(set) var notificationStatus = "检查中…"
    @Published private(set) var alertMessages: [AlertMessage] = []
    /// 侧边栏选中的列表
    @Published var selection: SidebarItem = .smart(.all)
    /// 今天 / 作业 / 成绩 / 课表。一打开先看「今天」：AI 的全局总结
    @Published var mode: AppMode = .today
    @Published var gradeSelection: GradeSelection = .plan
    /// 作业页左栏按「科目」还是按「类型」列（记住上次的选择）
    @Published var taskGrouping = TaskGrouping(rawValue: UserDefaults.standard.string(forKey: "taskGrouping") ?? "") ?? .subject {
        didSet { UserDefaults.standard.set(taskGrouping.rawValue, forKey: "taskGrouping") }
    }
    /// 课表看哪一周：0 = 本周，1 = 下周
    @Published var scheduleWeek = 0
    @Published private(set) var aiAdvice: AIAdvice?
    @Published private(set) var aiBusy = false
    /// AI 正在干什么 / 出了什么问题
    @Published private(set) var aiStatus: String?
    /// 设置里正在输入、还没保存的 API Key（不会存到普通文件里）
    @Published var apiKeyDraft = ""
    /// 设置里正在输入、还没保存的校宝密码（不会存到普通文件里）
    @Published var schoolPasswordDraft = ""
    @Published private(set) var hasSchoolPassword = false
    @Published private(set) var apiKeyHint: String?

    /// 打开主窗口的动作。只有 SwiftUI 的界面里才拿得到（openWindow），
    /// 所以由菜单栏图标 / 窗口出现时交给 Store；还没拿到时先记下「想开」，拿到了马上开。
    var openWindowAction: (() -> Void)? {
        didSet {
            if wantsWindow, let openWindowAction {
                wantsWindow = false
                openWindowAction()
                NSApp.activate()
            }
        }
    }
    private var wantsWindow = false

    private var syncState: SyncState
    private var retryNotBefore: Date?
    private var failuresThisSlot = 0
    /// failuresThisSlot 记的是哪个时间点的失败（换了时间点就从 0 重新数）
    private var failedSlot: Date?
    /// 上次同步失败是不是「过一会儿再试可能就好」的那种（密码错、要验证码就不是）
    private var lastErrorRetryable = true
    private var ticker: Timer?

    init() {
        snapshot = AppFiles.load(Snapshot.self, from: AppFiles.snapshot)
        selfReported = AppFiles.load(Set<Int>.self, from: AppFiles.selfReported) ?? []
        settings = AppFiles.load(AppSettings.self, from: AppFiles.settings) ?? AppSettings()
        syncState = AppFiles.load(SyncState.self, from: AppFiles.syncState) ?? SyncState()
        aiAdvice = AppFiles.load(AIAdvice.self, from: AppFiles.aiAdvice)
        refreshDerived()
        refreshAPIKeyHint()
    }

    /// App 启动完成后调用一次
    func start() {
        applyLaunchAgent()
        Task {
            _ = await Notifier.shared.requestAuthorization()
            await refreshNotificationStatus()
        }
        // 每分钟：刷新「现在」，并检查是不是到了同步时间
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.now = Date()
                self?.scheduledCheck()
            }
        }
        if snapshot == nil {
            Task { await sync() } // 第一次用，先拉一次数据
        } else {
            scheduledCheck()
            // 总结比数据旧（或者还没有总结），就重新写一份
            if aiAdvice?.basedOn != snapshot?.syncedAt { Task { await generateSummary() } }
        }
    }

    private func refreshDerived() {
        var d = Derived()
        let tasks = snapshot?.tasks ?? []
        d.report = TodoClassifier.classify(tasks, now: now, selfReported: selfReported)
        let report = d.report
        var pending: [String: Int] = [:]
        for name in Set(tasks.map(\.subjectName)) { pending[name] = Sections.pendingCount(subject: name, report) }
        d.taskSubjects = pending.keys.sorted {
            let a = pending[$0] ?? 0, b = pending[$1] ?? 0
            return a != b ? a > b : $0.localizedStandardCompare($1) == .orderedAscending
        }
        let present = Set(tasks.map(\.category))
        d.taskCategories = TaskCategory.allCases.filter(present.contains)
        if let grades = snapshot?.grades {
            d.computedGPA = GradeMath.gpa(grades.subjects, bands: grades.bands)
            d.gradePlan = GradeMath.plan(grades, target: settings.targetGPA)
            d.gradeSubjects = grades.subjects.sorted {
                if $0.isInGrade != $1.isInGrade { return $0.isInGrade }
                return ($0.score ?? 999) < ($1.score ?? 999)
            }
            let taskItems = snapshot?.taskItems ?? [:]
            for subject in grades.subjects {
                d.levers[subject.id] = GradeMath.levers(subject, tasks: tasks, taskItems: taskItems, now: now)
                d.futures[subject.id] = GradeMath.futureNeed(subject, bands: grades.bands)
            }
            var moves: [GPAMove] = []
            for subject in grades.subjects where subject.isInGrade {
                guard let score = subject.score, let band = GradeMath.band(for: score, in: grades.bands) else { continue }
                for lever in d.levers[subject.id] ?? [] where lever.taskId != nil && lever.gain > 0 {
                    let newScore = GradeMath.round1(score + lever.gain)
                    let newBand = GradeMath.band(for: newScore, in: grades.bands) ?? band
                    // 按学校规则舍去到 2 位小数（不是四舍五入），和官网、AI 总结里的数一致
                    let after = GradeMath.floor2(GradeMath.gpa(grades.subjects, bands: grades.bands, scores: [subject.id: newScore]) ?? 0)
                    moves.append(GPAMove(subjectName: subject.name, lever: lever,
                                         change: newBand == band ? nil : "\(band.name)→\(newBand.name)", gpaAfter: after))
                }
            }
            d.moves = moves.sorted { ($0.gpaAfter, $0.lever.gain) > ($1.gpaAfter, $1.lever.gain) }
        }
        derived = d
    }

    var report: TodoReport { derived.report }

    /// 「10月6日 20:03 更新」或者「同步失败，显示的是 10月6日 20:03 的数据」
    var updatedText: String {
        guard let snapshot else { return "还没有数据" }
        let time = Format.syncTime.string(from: snapshot.syncedAt)
        return lastError == nil ? "\(time) 更新" : "同步失败 · 数据停在 \(time)"
    }

    /// 所有科目（作业页侧边栏用），没交的多的排前面
    var subjects: [String] { derived.taskSubjects }
    var categories: [TaskCategory] { derived.taskCategories }

    /// 明天上不上学（课表里明天有没有课）
    var tomorrowHasClasses: Bool {
        let calendar = SchoolTime.calendar
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return true }
        return (snapshot?.schedule ?? []).contains { $0.beginDate.map { calendar.isDate($0, inSameDayAs: tomorrow) } ?? false }
    }

    /// 打开主窗口并放到最前面
    func requestOpenWindow() {
        if let openWindowAction {
            openWindowAction()
            NSApp.activate()
        } else {
            wantsWindow = true
        }
    }

    /// 切换模式（带一点动画，切起来更顺）
    func switchMode(_ mode: AppMode) {
        withAnimation(.snappy(duration: 0.28)) { self.mode = mode }
    }

    // MARK: - 同步

    @discardableResult
    func sync() async -> Bool {
        guard !syncing else { return false }
        syncing = true
        defer { syncing = false }
        if AppFiles.isDemo {
            lastError = "演示模式：用的是虚构数据，不会联网同步"
            lastErrorRetryable = false
            return false
        }
        do {
            let fresh = try await SyncEngine.run(schoolURL: settings.schoolURL, account: settings.schoolAccount,
                                                 previous: snapshot)
            snapshot = fresh
            AppFiles.save(fresh, to: AppFiles.snapshot)
            recordGPAHistory(fresh)
            lastError = nil
            now = Date()
            // 数据更新了，AI 总结也跟着重写（在后台进行，不耽误同步结束）
            Task { await generateSummary() }
            return true
        } catch {
            // 同步失败时不清空旧数据，界面上会写明数据是什么时候的
            lastError = "\(error)"
            lastErrorRetryable = (error as? SchoolisError)?.retryable ?? true
            return false
        }
    }

    // MARK: - 成绩

    var grades: GradeData? { snapshot?.grades }

    /// 我们按规则算的 GPA（不舍去）
    var computedGPA: Double? { derived.computedGPA }

    /// 官网 GPA 和我们算的对不对得上（差 0.01 以内算对得上）
    var gpaMatchesOfficial: Bool {
        guard let official = snapshot?.gpa, let mine = computedGPA else { return true }
        return abs(GradeMath.floor2(mine) - official) < 0.011
    }

    var gradePlan: GradeMath.GPAPlan? { derived.gradePlan }

    /// 成绩页侧边栏的科目：计入 GPA 的按分数从低到高（短板在上面），不计入的放最后
    var gradeSubjects: [SubjectGrade] { derived.gradeSubjects }

    func levers(for subject: SubjectGrade) -> [GradeMath.Lever] { derived.levers[subject.id] ?? [] }

    func futureNeed(for subject: SubjectGrade) -> GradeMath.FutureNeed? { derived.futures[subject.id] }

    /// 每次同步后记下「官网 GPA + 我们算的 + 各科绩点」。官网 GPA 怎么算学校没公开，
    /// 记得多了以后可以反推出各科的真实权重。
    private func recordGPAHistory(_ snapshot: Snapshot) {
        guard let grades = snapshot.grades else { return }
        var history = AppFiles.load([GPARecord].self, from: AppFiles.gpaHistory) ?? []
        var points: [String: Double] = [:]
        for subject in grades.subjects where subject.isInGrade {
            if let s = subject.score, let band = GradeMath.band(for: s, in: grades.bands) { points[subject.name] = band.gpa }
        }
        let record = GPARecord(date: snapshot.syncedAt, official: snapshot.gpa,
                               computed: GradeMath.gpa(grades.subjects, bands: grades.bands), points: points)
        if let last = history.last, last.official == record.official, last.points == record.points { return }
        history.append(record)
        AppFiles.save(history, to: AppFiles.gpaHistory)
    }

    // MARK: - AI 全局总结

    /// 让 AI 把作业、成绩、课表、考勤放在一起，写一份「今天该干什么、怎么干」的总结。
    /// 所有数字都由程序算好，AI 只负责挑重点、把话说顺。
    /// 顺序：Antigravity（本机装了 agy 就用）→ 设置里选的云端 AI → 另一家填了 Key 的 → 本地模型兜底。
    /// 在设置里选了「本地模型」：只用本地模型，数据绝不发到云端。
    func generateSummary() async {
        guard !aiBusy, let snapshot else { return }
        aiBusy = true
        defer { aiBusy = false }
        var reminders = AppFiles.load(AIReminders.self, from: AppFiles.aiReminders) ?? AIReminders()
        let input = SummaryFacts.build(snapshot: snapshot, derived: derived, target: settings.targetGPA, now: now,
                                       reminders: reminders)
        let facts = input.text
        // 留一份交给 AI 的数据，总结写得不对时可以对照查（只存在这台电脑上）
        try? facts.write(to: AppFiles.directory.appendingPathComponent("ai-last-input.json"), atomically: true, encoding: .utf8)
        var note: String?
        do {
            var result: (text: String, provider: String, model: String)?
            var problems: [String] = []
            let localOnly = settings.aiProvider == .ollama

            if !localOnly {
                // 要用 Google 的模型（Antigravity / Gemini）时才看网络：装了 Clash 就先帮你在后台打开它，
                // 打不开就跳过 Google，省得干等；没装 Clash 的电脑照常直连（或者走你自己的系统代理）
                let wantsGoogle = AgyAI.isAvailable || settings.aiProvider == .gemini
                    || APIKeyStore.get(AIProvider.gemini.keyAccount)?.isEmpty == false
                var googleReachable = true
                if wantsGoogle && ClashProxy.isInstalled {
                    aiStatus = "正在检查网络…"
                    googleReachable = await ClashProxy.prepare() != nil
                    if !googleReachable { problems.append("Clash 没开起来，跳过了 Google 的模型") }
                }

                // 1. Antigravity（本机装了 agy 就用，免 Key）
                if googleReachable && AgyAI.isAvailable && (settings.aiProvider.isAgy || settings.aiProvider == .gemini) {
                    aiStatus = "Antigravity（Gemini 3.8 Flash）正在写总结…"
                    do {
                        let answer = try await AgyAI.chat(model: "gemini-3.8-flash", system: SummaryFacts.systemPrompt, user: facts)
                        result = (answer, "Antigravity", "gemini-3.8-flash")
                    } catch {
                        problems.append("Antigravity 没成功：\(error)")
                    }
                }

                // 2. 云端 API：设置里选的那家优先，另一家填了 Key 的也试试
                if result == nil {
                    var order: [AIProvider] = []
                    if settings.aiProvider.isCloud { order.append(settings.aiProvider) }
                    for other in [AIProvider.gemini, .zhipu] where !order.contains(other) {
                        if APIKeyStore.get(other.keyAccount)?.isEmpty == false { order.append(other) }
                    }
                    if !googleReachable { order.removeAll { $0 == .gemini } }
                    for provider in order {
                        guard let key = APIKeyStore.get(provider.keyAccount), !key.isEmpty else {
                            problems.append("还没填 \(provider.title) 的 API Key")
                            continue
                        }
                        aiStatus = "\(provider.title) 正在写总结（大约 10～40 秒）…"
                        let preferred = provider == .gemini ? settings.geminiModel : settings.zhipuModel
                        do {
                            let answer = try await CloudAI.summarize(provider: provider, key: key, preferredModel: preferred,
                                                                     thinking: settings.aiThinking,
                                                                     system: SummaryFacts.systemPrompt, user: facts)
                            result = (answer.text, provider.title, answer.model)
                            if let detail = answer.note { problems.append(detail) }
                            break
                        } catch {
                            problems.append("\(provider.title) 没成功：\(error)")
                        }
                    }
                }
            }

            if !problems.isEmpty {
                note = problems.joined(separator: "；") + (result == nil ? "。这次用的是本地模型。" : "")
            }

            // 3. 兜底：本地模型（设置 → AI → 本地模型）
            if result == nil {
                guard let local = LocalLLM.config(from: settings) else {
                    throw LocalAI.AIError("本地模型的地址填得不对（设置 → AI → 本地模型）")
                }
                let text = try await LocalLLM.chat(local, system: SummaryFacts.systemPrompt, user: facts) { self.aiStatus = $0 }
                result = (text, "本地模型", local.model.isEmpty ? "local" : local.model)
            }
            guard let result else { return }
            let advice = AIAdvice(text: result.text, createdAt: Date(), model: result.model, target: settings.targetGPA,
                                  provider: result.provider, note: note, basedOn: snapshot.syncedAt,
                                  structured: AISummary.parse(result.text))
            aiAdvice = advice
            AppFiles.save(advice, to: AppFiles.aiAdvice)
            // 记下这次提了哪些事：过了截止的明天就不再提，提分建议最多提两天
            if let summary = advice.structured {
                reminders.record(input.mentionedKeys(in: summary), now: Date())
                AppFiles.save(reminders, to: AppFiles.aiReminders)
            }
            aiStatus = nil
        } catch {
            aiStatus = "AI 没能写出总结：\(error)" + (note.map { "（\($0)）" } ?? "")
        }
    }

    /// 在浏览器里打开校宝（设置里填的学校网址）
    func openSchoolWebsite() {
        if let url = URL(string: settings.schoolURL.trimmingCharacters(in: .whitespacesAndNewlines)), url.scheme == "https" {
            NSWorkspace.shared.open(url)
        }
    }

    /// 保存校宝密码（存进钥匙串，账号用设置里填的）
    @discardableResult
    func saveSchoolPassword(_ password: String) -> String? {
        let account = settings.schoolAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty else { return "先填账号" }
        guard !password.isEmpty else { return "密码是空的" }
        do {
            try Keychain.save(account: account, secret: password)
            hasSchoolPassword = true
            return nil
        } catch {
            return "\(error)"
        }
    }

    /// 钥匙串里有没有这个账号的密码（只看有没有，不读出来）
    func refreshSchoolPasswordState() {
        let account = settings.schoolAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        hasSchoolPassword = !account.isEmpty && (try? Keychain.password(account: account)) != nil
    }

    // MARK: - AI 设置

    /// 保存当前选的云端 AI 的 Key
    func saveAPIKey() {
        let key = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, settings.aiProvider.isCloud else { return }
        APIKeyStore.set(settings.aiProvider.keyAccount, key)
        apiKeyDraft = ""
        refreshAPIKeyHint()
    }

    func deleteAPIKey() {
        APIKeyStore.delete(settings.aiProvider.keyAccount)
        refreshAPIKeyHint()
    }

    private func refreshAPIKeyHint() {
        if settings.aiProvider.isCloud, let key = APIKeyStore.get(settings.aiProvider.keyAccount), key.count > 4 {
            apiKeyHint = "已保存（结尾是 …\(key.suffix(4))）"
        } else {
            apiKeyHint = nil
        }
    }

    // MARK: - 定时同步

    /// 检查是不是错过了某个同步时间点，是的话就同步一次。
    /// 每分钟检查一次，所以电脑睡眠醒来、开机后，都会在一分钟内补上。
    func scheduledCheck() {
        guard settings.autoSync, !syncing, !AppFiles.isDemo,
              let due = Schedule.latestSlot(settings.syncTimes, atOrBefore: Date()) else { return }
        if let handled = syncState.lastSlotHandled, handled >= due { return }
        // 这个时间点之后已经手动同步过了，就不用再同步
        if let snapshot, snapshot.syncedAt >= due {
            markHandled(due)
            return
        }
        if let retryNotBefore, Date() < retryNotBefore { return }
        retryNotBefore = Date().addingTimeInterval(300) // 防止重复触发（下面还会随机等 0～3 分钟）
        Task { await runScheduledSync(slot: due) }
    }

    private func runScheduledSync(slot: Date) async {
        if failedSlot != slot {
            failedSlot = slot
            failuresThisSlot = 0
            // 每个时间点第一次同步前随机等 0～3 分钟：用的人多了，也不会在同一秒一起挤到学校服务器上
            try? await Task.sleep(nanoseconds: UInt64.random(in: 0...180) * 1_000_000_000)
        }
        let previous = snapshot
        if await sync() {
            failuresThisSlot = 0
            retryNotBefore = nil
            markHandled(slot)
            announce(previous: previous)
        } else {
            failuresThisSlot += 1
            // 密码错、要验证码、没填账号：重试只会更糟（可能把账号锁住），立刻停下，告诉你
            if !lastErrorRetryable || failuresThisSlot >= 3 {
                // 隔 10 分钟试一次，试了 3 次都不行，就告诉你，然后等下一个时间点
                failuresThisSlot = 0
                retryNotBefore = nil
                markHandled(slot)
                Notifier.shared.post(id: "sync-failed", title: "学习助手：同步失败",
                                     body: "\(lastError ?? "原因不明")\n现在看到的是旧数据。", sound: false)
            } else {
                retryNotBefore = Date().addingTimeInterval(10 * 60)
            }
        }
    }

    private func markHandled(_ slot: Date) {
        syncState.lastSlotHandled = slot
        AppFiles.save(syncState, to: AppFiles.syncState)
    }

    // MARK: - 提醒

    /// 定时同步完成后：先发紧急提醒（今明两天截止、新出现的），再发一条汇总。
    private func announce(previous: Snapshot?) {
        let report = self.report
        let pending = report.markedNotDone + report.overdue + report.today + report.tomorrow
            + report.within7Days + report.later

        // 新出现的：上次同步时还没有的作业，或者这次才被老师记为「未完成」的。
        // 专门防「老师截止之后才把作业发到系统上」这种情况。
        var fresh: [LearningTask] = []
        if let previous {
            let oldIds = Set(previous.tasks.map(\.id))
            let oldMarked = Set(TodoClassifier.classify(previous.tasks, now: now, selfReported: selfReported)
                .markedNotDone.map(\.id))
            let marked = Set(report.markedNotDone.map(\.id))
            fresh = pending.filter { !oldIds.contains($0.id) || (marked.contains($0.id) && !oldMarked.contains($0.id)) }
        }

        let soon = report.today + report.tomorrow
        let soonIds = Set(soon.map(\.id))
        let urgent = soon + fresh.filter { !soonIds.contains($0.id) }
        if !urgent.isEmpty {
            var parts: [String] = []
            if !soon.isEmpty { parts.append("今明两天截止 \(soon.count) 个") }
            if !fresh.isEmpty { parts.append("新出现 \(fresh.count) 个") }
            deliver(settings.urgentStyle, id: "urgent", title: "⏰ " + parts.joined(separator: "，"),
                    body: Format.lines(urgent), sound: true)
        }
        if !pending.isEmpty {
            deliver(settings.summaryStyle, id: "summary", title: "学习助手：\(report.urgentCount) 件要处理",
                    body: Format.summary(report), sound: false)
        }
    }

    private func deliver(_ style: AlertStyle, id: String, title: String, body: String, sound: Bool) {
        switch style {
        case .popup:
            alertMessages.removeAll { $0.id == id }
            alertMessages.append(AlertMessage(id: id, title: title, body: body))
            requestOpenWindow()
            if sound { NSSound(named: "Glass")?.play() }
        case .system:
            Notifier.shared.post(id: id, title: title, body: body, sound: sound)
        case .badgeOnly:
            break
        }
    }

    func dismissAlerts() {
        alertMessages.removeAll()
    }

    /// 设置页里的「试一下」按钮
    func testAlert(urgent: Bool) {
        let report = self.report
        if urgent {
            let sample = report.today + report.tomorrow + report.within7Days
            deliver(settings.urgentStyle, id: "test-urgent", title: "⏰（测试）紧急提醒长这样",
                    body: sample.isEmpty ? "现在没有快到期的作业，这只是测试。" : Format.lines(sample), sound: true)
        } else {
            deliver(settings.summaryStyle, id: "test-summary",
                    title: "（测试）学习助手：\(report.urgentCount) 件要处理", body: Format.summary(report), sound: false)
        }
    }

    func refreshNotificationStatus() async {
        notificationStatus = await Notifier.shared.statusText()
    }

    // MARK: - 设置

    func updateSettings(_ change: (inout AppSettings) -> Void) {
        var copy = settings
        change(&copy)
        copy.syncTimes = Array(Set(copy.syncTimes)).sorted()
        if copy.syncTimes.isEmpty { copy.syncTimes = AppSettings().syncTimes }
        guard copy != settings else { return }
        let scheduleChanged = copy.syncTimes != settings.syncTimes || copy.autoSync != settings.autoSync
        settings = copy
        AppFiles.save(settings, to: AppFiles.settings)
        if scheduleChanged { applyLaunchAgent() }
    }

    /// 按设置装上或删掉定时任务
    func applyLaunchAgent() {
        // 只有打包好的 .app 才装定时任务：用 swift run 调试、或者演示模式打开时都不碰系统设置
        guard Bundle.main.bundlePath.hasSuffix(".app"), !AppFiles.isDemo else { return }
        do {
            if settings.autoSync {
                try LaunchAgent.install(times: settings.syncTimes, appPath: Bundle.main.bundlePath)
            } else {
                LaunchAgent.uninstall()
            }
            scheduleError = nil
        } catch {
            scheduleError = "\(error)"
        }
    }

    var scheduleStatusText: String {
        guard settings.autoSync else {
            return "自动同步已关闭，定时任务也已删除。只有你点 ↻ 的时候才会同步。"
        }
        let times = settings.syncTimes.map(\.text).joined(separator: "、")
        var text = "每天 \(times) 自动同步。就算退出了 App，到点也会在后台把它启动起来。"
            + "电脑关机或合上盖子时会错过，下次打开后一分钟内补上。"
        if let scheduleError { text += "\n⚠️ 定时任务没装上：\(scheduleError)" }
        let path = Bundle.main.bundlePath
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if !path.hasPrefix(home + "/Applications/") && !path.hasPrefix("/Applications/") {
            text += "\n⚠️ App 不在「应用程序」文件夹里，挪动它之后定时任务会找不到。请用 build-app.sh 重新安装。"
        }
        return text
    }

    // MARK: - 「我交了」

    /// 只记在你自己电脑上，不会告诉学校。
    func setSelfReported(_ task: LearningTask, _ submitted: Bool) {
        if submitted { selfReported.insert(task.id) } else { selfReported.remove(task.id) }
        AppFiles.save(selfReported, to: AppFiles.selfReported)
    }
}
