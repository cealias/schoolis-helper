// M1 探针：登录校宝 → 每个接口调一遍 → 原始数据存到本地 → 打印一份摘要，拿去和网页对照。
//
// 只读：不会提交作业，也不会改动任何东西。
// 输出里不会出现密码、密码哈希或 Cookie。
//
// 用法：
//   swift run probe              正式跑一次（需要先把密码存进钥匙串，见 README）
//   swift run probe --selftest   不联网，只检查密码哈希算法写得对不对

import Foundation
import SchoolisCore

// MARK: - 自检（不联网）

if CommandLine.arguments.contains("--selftest") {
    // 用一个假密码 test123 和固定时间戳，和 Python 算出的标准答案对比。
    let got = SchoolisClient.passwordHash("test123", timestamp: 1_791_100_000)
    let expected = "9D43CF27B35002A43F567E248E2621F6"
    print(got == expected ? "✅ 密码哈希算法正确" : "❌ 密码哈希不对：\(got)，应为 \(expected)")
    exit(got == expected ? 0 : 1)
}

// MARK: - 待办分组测试（不联网）

// swift run probe --todo [原始数据文件夹]
// 用探针以前存下的数据跑一遍待办分组规则，看分得对不对。不写文件夹就用最新的一次。
if let flag = CommandLine.arguments.firstIndex(of: "--todo") {
    let rawRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SchoolisHelper/raw")
    let folder: URL
    if flag + 1 < CommandLine.arguments.count {
        folder = URL(fileURLWithPath: CommandLine.arguments[flag + 1])
    } else {
        let runs = (try? FileManager.default.contentsOfDirectory(atPath: rawRoot.path)) ?? []
        guard let latest = runs.filter({ !$0.hasPrefix(".") }).sorted().last else {
            print("❌ 还没有原始数据，先正常跑一次探针")
            exit(1)
        }
        folder = rawRoot.appendingPathComponent(latest)
    }
    let pages = ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        .filter { $0.hasPrefix("tasks-page") }.sorted()
    var tasks: [LearningTask] = []
    var skipped = 0
    for name in pages {
        let page = try TaskPage.fromRaw(Data(contentsOf: folder.appendingPathComponent(name)))
        tasks += page.list
        skipped += page.skipped
    }
    print("数据：\(folder.lastPathComponent)，共 \(tasks.count) 条任务，读不懂 \(skipped) 条\n")

    let report = TodoClassifier.classify(tasks, now: Date(), selfReported: [])
    func show(_ title: String, _ list: [LearningTask]) {
        guard !list.isEmpty else { return }
        print("【\(title)】\(list.count) 条")
        for t in list {
            let points = "\(t.score.map { String(format: "%g", $0) } ?? "-")/\(t.totalScore.map { String(format: "%g", $0) } ?? "-")"
            print("  \(t.endTime?.prefix(16) ?? "无截止") | \(t.subjectName) | \(t.name) | \(points)")
        }
    }
    show("老师记为未完成", report.markedNotDone)
    show("过了截止、没有记录", report.overdue)
    show("今天", report.today)
    show("明天", report.tomorrow)
    show("7 天内", report.within7Days)
    show("更晚", report.later)
    show("等老师登分（课堂表现、考勤、考完的测验、随手填的截止时间）", report.awaitingTeacher)
    show("已交，等批改", report.awaitingGrade)
    print("【已完成】\(report.completed.count) 条（不逐条列出）")
    print("\n菜单栏数字：\(report.urgentCount)")
    // 自检：每个任务必须正好落在一个组里，不能丢、不能重复
    print("分组合计 \(report.totalCount) / 任务总数 \(tasks.count) \(report.totalCount == tasks.count ? "✅" : "❌ 对不上！")")
    let subjects = Set(tasks.map(\.subjectName)).sorted()
    for subject in subjects {
        let all = tasks.filter { $0.subjectName == subject }
        let sub = TodoClassifier.classify(all, now: Date(), selfReported: [])
        print("  \(subject)：共 \(all.count) 条，已完成 \(sub.completed.count)")
    }
    exit(0)
}

// MARK: - 用 App 的快照核对作业对应关系（不联网）

// swift run probe --levers：读 App 存的 snapshot.json，看每个项目「按作业算的分」和学校给的对不对得上，并列出涨分建议
// swift run probe --types
// 用本地快照看每个作业被归到哪一类（不联网）。核对「作业名关键词 + 老师填的类型」的归类规则。
if CommandLine.arguments.contains("--types") {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let snapshot = try? decoder.decode(Snapshot.self, from: Data(contentsOf: AppFiles.snapshot)) else {
        print("读不到快照"); exit(1)
    }
    let groups = Dictionary(grouping: snapshot.tasks, by: \.category)
    for category in TaskCategory.allCases {
        let tasks = groups[category] ?? []
        print("== \(category.title)（\(tasks.count)）")
        for task in tasks.sorted(by: { ($0.typeName, $0.name) < ($1.typeName, $1.name) }) {
            print("   [\(task.typeName)] \(task.subjectName)：\(task.name)")
        }
    }
    let total = groups.values.reduce(0) { $0 + $1.count }
    print(total == snapshot.tasks.count ? "✅ 合计 \(total) = 任务总数" : "❌ 合计 \(total) ≠ 任务总数 \(snapshot.tasks.count)")
    exit(0)
}

if CommandLine.arguments.contains("--levers") {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    guard let snapshot = try? decoder.decode(Snapshot.self, from: Data(contentsOf: AppFiles.snapshot)),
          let grades = snapshot.grades else { print("快照里没有成绩"); exit(1) }
    let taskItems = snapshot.taskItems ?? [:]
    var ok = 0, bad = 0, noTask = 0
    for subject in grades.subjects {
        print("== \(subject.name) \(subject.score.map { String($0) } ?? "-")")
        for leaf in GradeMath.leaves(subject.items) {
            let mine = snapshot.tasks.filter { $0.subjectName == subject.name && (taskItems[String($0.id)] ?? []).contains(leaf.item.id) }
            let graded = mine.filter { $0.learningTaskState == 4 && ($0.totalScore ?? 0) > 0 }
            let earned = graded.reduce(0) { $0 + ($1.score ?? 0) }, possible = graded.reduce(0) { $0 + ($1.totalScore ?? 0) }
            let computed = possible > 0 ? GradeMath.round1(earned / possible * 100) : nil
            let mark: String
            if leaf.item.score == nil { mark = "  " }
            else if graded.isEmpty { mark = "？"; noTask += 1 }
            else if let c = computed, abs(c - leaf.item.score!) <= 0.15 { mark = "✅"; ok += 1 }
            else { mark = "❌"; bad += 1 }
            print("   \(mark) \(leaf.path)：学校 \(leaf.item.score.map { String($0) } ?? "未出分")，按作业算 \(computed.map { String($0) } ?? "-")（\(graded.count) 个已批改作业）")
        }
        for lever in GradeMath.levers(subject, tasks: snapshot.tasks, taskItems: taskItems).prefix(3) {
            print("      ↑ [\(lever.kind)] \(lever.title)：+\(lever.gain)\(lever.loss > 0 ? " / 不交 −\(lever.loss)" : "")")
        }
    }
    print("\n核对结果：对得上 \(ok) 项，对不上 \(bad) 项，有分但没找到作业 \(noTask) 项")
    exit(0)
}

// MARK: - 成绩计算测试（不联网）

// swift run probe --grades [原始数据文件夹] [目标GPA]
// 用探针存下的成绩数据，核对「按规则重算的分」和学校给的是否一致，再算提分方案。
if let flag = CommandLine.arguments.firstIndex(of: "--grades") {
    let rawRoot = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/SchoolisHelper/raw")
    let args = Array(CommandLine.arguments.dropFirst(flag + 1))
    let folder = args.first.map { URL(fileURLWithPath: $0) }
        ?? rawRoot.appendingPathComponent(((try? FileManager.default.contentsOfDirectory(atPath: rawRoot.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted().last ?? "")
    let target = args.count > 1 ? Double(args[1]) ?? 4.0 : 4.0
    func load(_ name: String) -> Any? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object["data"]
    }
    var grades = GradeData.parse(scores: load("subject-scores.json"))
    for i in grades.subjects.indices {
        grades.subjects[i].items = GradeData.parseItems(detail: load("score-detail-\(grades.subjects[i].id).json"))
    }
    print("分数段：", grades.bands.map { "\($0.name)≥\($0.min)" }.joined(separator: " "))
    print("\n【核对：按规则重算的分 vs 学校给的分】")
    for s in grades.subjects {
        let mine = GradeMath.score(s.items)
        let ok = mine.map { abs($0 - (s.score ?? -1)) < 0.05 } ?? false
        let band = s.score.flatMap { GradeMath.band(for: $0, in: grades.bands) }
        print("  \(ok ? "✅" : "❌") \(s.name)：学校 \(s.score.map { String($0) } ?? "-")，重算 \(mine.map { String($0) } ?? "-")，\(band?.name ?? "-") \(band.map { String($0.gpa) } ?? "")\(s.isInGrade ? "" : "（不计入GPA）")")
    }
    let gpa = GradeMath.gpa(grades.subjects, bands: grades.bands) ?? 0
    print("\n我们算的 GPA：\(gpa) → 显示 \(GradeMath.floor2(gpa))")
    if let plan = GradeMath.plan(grades, target: target) {
        print("\n【到 \(target) 的方案】\(plan.alreadyThere ? "已经达到" : "")\(plan.reachable ? "" : "（全部提满也到不了）")")
        for (i, option) in plan.options.enumerated() {
            let steps = option.steps.map { "\($0.subjectName) \($0.currentScore)→\($0.to.min)（\($0.from.name)→\($0.to.name)，+\($0.delta) 分）" }
            print("  方案\(i + 1)：\(steps.joined(separator: " + "))，总共 +\(option.totalDelta) 分 → GPA \(GradeMath.floor2(option.resultingGPA))")
        }
    }
    var tasks: [LearningTask] = []
    for name in ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).filter({ $0.hasPrefix("tasks-page") }).sorted() {
        if let page = try? TaskPage.fromRaw(Data(contentsOf: folder.appendingPathComponent(name))) { tasks += page.list }
    }
    print("\n【各科：剩下没出分的项目要考多少 / 从哪儿涨分】（这里没有作业对应关系，只到项目层面）")
    for s in grades.subjects where s.isInGrade {
        if let need = GradeMath.futureNeed(s, bands: grades.bands) {
            let text = need.needs.map { "\($0.band.name) 需平均 \($0.average.map { String($0) } ?? "满分也不够")" }.joined(separator: "；")
            print("  \(s.name)：没出分的 \(need.items.joined(separator: "、"))（最后占 \(need.share)%）→ \(text)")
        }
        for lever in GradeMath.levers(s, tasks: tasks, taskItems: [:]).prefix(2) {
            print("     ↑ \(lever.path)：+\(lever.gain)。\(lever.detail)")
        }
    }
    exit(0)
}

// MARK: - 准备

// 账号和学校网址：优先用环境变量 SCHOOLIS_URL / SCHOOLIS_ACCOUNT，没有就读 App 的设置文件（设置 → 校宝账号）
let savedSettings = (try? JSONSerialization.jsonObject(with: Data(contentsOf: AppFiles.directory
    .appendingPathComponent("settings.json")))) as? [String: Any] ?? [:]
let env = ProcessInfo.processInfo.environment
let account = env["SCHOOLIS_ACCOUNT"] ?? savedSettings["schoolAccount"] as? String ?? ""
let schoolURL = env["SCHOOLIS_URL"] ?? savedSettings["schoolURL"] as? String ?? ""
guard !account.isEmpty, let schoolBase = URL(string: schoolURL), schoolBase.scheme == "https" else {
    print("❌ 还没有校宝账号：先在 App 的「设置 → 校宝账号」里填，或者设置环境变量 SCHOOLIS_URL 和 SCHOOLIS_ACCOUNT")
    exit(1)
}
let client = SchoolisClient(baseURL: schoolBase)
let beijing = TimeZone(identifier: "Asia/Shanghai")! // 接口里的时间都是北京时间

func formatter(_ pattern: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = beijing
    f.dateFormat = pattern
    return f
}
let dayFormat = formatter("yyyy-MM-dd")
let apiTimeFormat = formatter("yyyy-MM-dd'T'HH:mm:ss")

// 原始数据存放在 ~/Library/Application Support/SchoolisHelper/raw/<时间>/。
// 放这里而不放在项目文件夹里，是因为里面有你的成绩，不能跟着代码一起被分享出去。
let outDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/SchoolisHelper/raw")
    .appendingPathComponent(formatter("yyyyMMdd-HHmmss").string(from: Date()))
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

/// 把接口原样返回的内容排版成好读的格式，存成 JSON 文件。
func save(_ name: String, _ envelope: Envelope) {
    var data = envelope.raw
    if let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
       let pretty = try? JSONSerialization.data(withJSONObject: object,
                                                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
        data = pretty
    }
    try? data.write(to: outDir.appendingPathComponent("\(name).json"))
}

// 学校返回的 JSON 字段类型不固定（有时是数字，有时是字符串，有时是 null），这几个小函数统一处理。
func text(_ value: Any?) -> String {
    if let s = value as? String { return s }
    if let n = value as? NSNumber { return n.stringValue }
    return ""
}
func number(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue ?? Double(text(value)) }
func object(_ value: Any?) -> [String: Any] { value as? [String: Any] ?? [:] }
func objects(_ value: Any?) -> [[String: Any]] { value as? [[String: Any]] ?? [] }
func isNull(_ value: Any?) -> Bool { value == nil || value is NSNull }
func short(_ x: Double) -> String { String(format: "%g", x) }

/// 每一步单独兜底：某个接口出错了就记下来，接着跑后面的，最后统一汇报。
var problems: [String] = []
@MainActor func step(_ title: String, _ body: () async throws -> Void) async {
    print("\n▶ \(title)")
    do { try await body() } catch {
        print("  ⚠️ \(error)")
        problems.append("\(title)：\(error)")
    }
}

// MARK: - 登录

print("schoolis 探针（M1）· 只读，不会提交或修改任何东西")

let password: String
do {
    password = try Keychain.password(account: account)
} catch {
    print("❌ \(error)")
    exit(1)
}

print("\n▶ 登录 \(account)")
do {
    try await client.login(user: account, password: password)
    print("  ✅ 登录成功")
} catch {
    print("  ❌ \(error)")
    exit(1)
}

// MARK: - 学期

var semesterId = ""
var semesterStart = ""
await step("当前学期") {
    let env = try await client.get("/api/School/GetSchoolSemesters")
    save("semesters", env)
    let all = objects(env.data)
    guard let now = all.first(where: { ($0["isNow"] as? Bool) == true }) else {
        throw SchoolisError("在 \(all.count) 个学期里没找到当前学期（isNow=true）")
    }
    semesterId = text(now["id"])
    semesterStart = String(text(now["startDate"]).prefix(10))
    print("  \(text(now["name"]))  semesterId=\(semesterId)  \(semesterStart) ~ \(text(now["endDate"]).prefix(10))")
}
if semesterId.isEmpty {
    await client.logout()
    print("\n❌ 拿不到当前学期，后面的接口都依赖它，先停下。")
    exit(1)
}

// MARK: - GPA 和成绩

await step("GPA") {
    let env = try await client.get("/api/DynamicScore/GetGpa", ["semesterId": semesterId])
    save("gpa", env)
    print("  动态 GPA：\(text(env.data))")
    save("gpa-settings", try await client.get("/api/DynamicScore/ListGpaSettings"))
}

var subjects: [[String: Any]] = []
await step("各科成绩") {
    let env = try await client.get("/api/DynamicScore/GetStuSemesterDynamicScore", ["semesterId": semesterId])
    save("subject-scores", env)
    subjects = objects(object(env.data)["studentSemesterDynamicScoreBasicDtos"])
    print("  共 \(subjects.count) 门（文档里是 11 门）")
    for s in subjects {
        let score = number(s["subjectScore"]).map(short) ?? "未出分"
        let note = (s["isInGrade"] as? Bool) == false ? "（不计入成绩）" : ""
        print("  · \(text(s["subjectName"]))：\(score)\(note)")
    }
}

await step("各科成绩构成") {
    for s in subjects {
        let subjectId = text(s["subjectId"])
        do {
            let env = try await client.get("/api/DynamicScore/GetDynamicScoreDetail",
                                           ["classId": text(s["classId"]), "subjectId": subjectId, "semesterId": semesterId])
            save("score-detail-\(subjectId)", env)
            let parts = objects(object(env.data)["evaluationProjectList"]).map { p -> String in
                let weight = number(p["proportion"]).map { short($0) + "%" } ?? "?"
                let score = (p["scoreIsNull"] as? Bool) == true ? "未出分" : (number(p["score"]).map(short) ?? "?")
                return "\(text(p["evaluationProjectName"])) \(weight)=\(score)"
            }
            print("  · \(text(s["subjectName"]))：\(parts.joined(separator: "；"))")
        } catch {
            print("  ⚠️ \(text(s["subjectName"]))：\(error)")
            problems.append("成绩构成 \(text(s["subjectName"]))：\(error)")
        }
    }
}

// MARK: - 学习任务（作业、测验等）

await step("学习任务（全学期）") {
    var all: [[String: Any]] = []
    var total = 0
    var page = 1
    // 一页一页地拉，直到拉够服务器说的总数。最多拉 30 页兜底，防止死循环。
    repeat {
        let env = try await client.get("/api/LearningTask/GetList",
                                       ["semesterId": semesterId, "pageIndex": String(page), "pageSize": "100"])
        save("tasks-page\(page)", env)
        let data = object(env.data)
        total = Int(number(data["totalCount"]) ?? 0)
        let items = objects(data["list"])
        all += items
        if items.isEmpty { break }
        page += 1
    } while all.count < total && page <= 30
    print("  拉到 \(all.count) 条，服务器说总共 \(total) 条（文档里是 109）")

    // 按「完成状态 + 生命周期状态」分组计数，用来核对文档里的状态对照表
    var groups: [String: Int] = [:]
    for t in all {
        let finish = isNull(t["finishState"]) ? "null" : text(t["finishState"])
        groups["finishState=\(finish), learningTaskState=\(text(t["learningTaskState"]))", default: 0] += 1
    }
    for (key, count) in groups.sorted(by: { $0.key < $1.key }) { print("  · \(key)：\(count) 条") }

    // 还没交的里面，有几条已经过了截止时间
    let now = Date()
    let unfinished = all.filter { isNull($0["finishState"]) }
    let overdue = unfinished.filter { t in
        guard let end = apiTimeFormat.date(from: String(text(t["endTime"]).prefix(19))) else { return false }
        return end < now
    }
    print("  未完成 \(unfinished.count) 条，其中已过截止时间 \(overdue.count) 条")

    // 文档里举的两个例子，逐个核对
    for keyword in ["Quiz04", "National Day HW"] {
        guard let t = all.first(where: { text($0["name"]).contains(keyword) }) else {
            print("  · 没找到「\(keyword)」")
            continue
        }
        let finish = isNull(t["finishState"]) ? "null" : text(t["finishState"])
        print("  · \(text(t["name"]))：得分 \(text(t["score"]))/\(text(t["totalScore"]))，finishState=\(finish)，learningTaskState=\(text(t["learningTaskState"]))，截止 \(text(t["endTime"]))")
    }
}

// MARK: - 考试、课表、考勤

await step("考试") {
    let env = try await client.get("/api/Exam/GetList", ["SemesterId": semesterId, "PageIndex": "1", "PageSize": "100"])
    save("exams", env)
    print("  共 \(text(object(env.data)["totalCount"])) 场（文档写的时候是 0）")
}

await step("本周课表") {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = beijing
    calendar.firstWeekday = 2 // 一周从周一开始
    let monday = calendar.dateInterval(of: .weekOfYear, for: Date())!.start
    let sunday = calendar.date(byAdding: .day, value: 6, to: monday)!
    let body = ["beginTime": dayFormat.string(from: monday), "endTime": dayFormat.string(from: sunday)]
    let env = try await client.post("/api/Schedule/ListScheduleByParent", body: body)
    save("schedule-week", env)
    print("  \(body["beginTime"]!) ~ \(body["endTime"]!)：\(objects(env.data).count) 条日程")
}

await step("考勤（本学期）") {
    // 时间格式和 AttendanceType=7 来自 my-xb：7 对应网页上的「课堂考勤」
    let begin = semesterStart + " 00:00:00"
    let end = dayFormat.string(from: Date()) + " 23:59:59"
    let overall = try await client.get("/api/Attendance/GetAttendanceStatistic",
                                       ["BeginTime": begin, "EndTime": end, "AttendanceType": "7"])
    save("attendance-overall", overall)
    let bySubject = try await client.get("/api/Attendance/GetSubjectAttendanceStatistic",
                                         ["BeginTime": begin, "EndTime": end])
    save("attendance-by-subject", bySubject)
    print("  按课程统计 \(objects(bySubject.data).count) 条（具体字段先存下来，M4 再细看）")
}

// MARK: - 收尾

await client.logout()
print("\n原始数据已存到：\(outDir.path)")
if problems.isEmpty {
    print("✅ 全部接口都通了")
} else {
    print("⚠️ 有 \(problems.count) 处出错：")
    problems.forEach { print("  - \($0)") }
}
