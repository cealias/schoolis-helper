import Foundation

/// 本地文件放在哪、怎么读写。
public enum AppFiles {
    /// 数据放在哪：平时是 ~/Library/Application Support/SchoolisHelper/；
    /// 启动时带 `--data-dir 文件夹` 就用那个文件夹（演示模式：读一套虚构数据，不登录、不联网、不装定时任务）
    public static let directory: URL = {
        let args = CommandLine.arguments
        if let flag = args.firstIndex(of: "--data-dir"), flag + 1 < args.count {
            return URL(fileURLWithPath: (args[flag + 1] as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/SchoolisHelper")
    }()

    /// 是不是演示模式（用 --data-dir 打开的）
    public static var isDemo: Bool { CommandLine.arguments.contains("--data-dir") }

    /// 建数据文件夹，权限 700：里面有成绩和考勤，同一台电脑的其他用户不能读
    public static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }
    /// 最近一次同步的结果
    public static let snapshot = directory.appendingPathComponent("snapshot.json")
    /// 你点过「我交了」的任务 id
    public static let selfReported = directory.appendingPathComponent("self-reported.json")

    public static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(T.self, from: data)
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else { return }
        ensureDirectory()
        // atomic：先写到临时文件再替换，写到一半断电也不会把旧数据弄坏
        try? data.write(to: url, options: .atomic)
    }
}

/// 一次完整的同步：登录 → 当前学期 → GPA → 全学期任务 → 成绩构成 → 课表 → 考勤 → 退出登录。
public enum SyncEngine {
    /// schoolURL、account：在设置里填的学校校宝网址和账号（密码在钥匙串里）。
    /// previous：上一次的快照。成绩、课表、考勤哪一项这次没拉到，就沿用上一次的；作业详情也只读新作业。
    public static func run(schoolURL: String, account: String, previous: Snapshot? = nil) async throws -> Snapshot {
        let account = account.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !account.isEmpty, let base = URL(string: schoolURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              base.scheme == "https", base.host != nil else {
            throw SchoolisError("还没填校宝账号：请在「设置 → 校宝账号」里填学校的校宝网址、账号和密码。", retryable: false)
        }
        let password = try Keychain.password(account: account)
        let client = SchoolisClient(baseURL: base)
        try await client.login(user: account, password: password)
        do {
            let snapshot = try await fetch(client, previous: previous)
            await client.logout()
            return snapshot
        } catch {
            await client.logout()
            throw error
        }
    }

    private static func fetch(_ client: SchoolisClient, previous: Snapshot?) async throws -> Snapshot {
        // 学期每学期都会变，所以每次都现查，不写死
        let semesters = try await client.get("/api/School/GetSchoolSemesters").decoded([Semester].self)
        guard let current = semesters.first(where: \.isNow) else {
            throw SchoolisError("没找到当前学期（可能正在放假）。")
        }
        let semesterId = String(current.id)

        // GPA 拿不到不影响作业，所以失败了就留空
        let gpaEnvelope = try? await client.get("/api/DynamicScore/GetGpa", ["semesterId": semesterId])
        let gpa = (gpaEnvelope?.data as? NSNumber)?.doubleValue ?? Double(gpaEnvelope?.data as? String ?? "")

        var tasks: [LearningTask] = []
        var skipped = 0
        var total = 0
        var page = 1
        repeat {
            let envelope = try await client.get("/api/LearningTask/GetList",
                                                ["semesterId": semesterId, "pageIndex": String(page), "pageSize": "100"])
            let result = try envelope.decoded(TaskPage.self)
            total = result.totalCount
            tasks += result.list
            skipped += result.skipped
            if result.list.isEmpty && result.skipped == 0 { break }
            page += 1
        } while tasks.count + skipped < total && page <= 30

        // 防漏：拉到的比服务器说的少，就把这次同步作废。
        // 宁可报错让你知道，也不能悄悄少显示几个作业。
        if tasks.count + skipped < total {
            throw SchoolisError("作业只拉到 \(tasks.count + skipped) 条，服务器说有 \(total) 条。这次同步作废，显示的仍是上次的数据。")
        }

        // 下面这些拿不到不影响作业：失败了就沿用上一次的，不让整次同步作废
        let grades = (try? await fetchGrades(client, semesterId: semesterId)) ?? previous?.grades
        let schedule = (try? await fetchSchedule(client)) ?? previous?.schedule
        let attendance = (try? await fetchAttendance(client, from: current.startDate)) ?? previous?.attendance
        let taskItems = await fetchTaskItems(client, tasks: tasks, known: previous?.taskItems ?? [:])

        return Snapshot(syncedAt: Date(), semesterName: current.name, gpa: gpa,
                        tasks: tasks, unreadableTasks: skipped,
                        grades: grades, schedule: schedule, attendance: attendance, taskItems: taskItems)
    }

    /// 各科成绩 + 每科的成绩构成（一科一个请求）
    private static func fetchGrades(_ client: SchoolisClient, semesterId: String) async throws -> GradeData {
        let envelope = try await client.get("/api/DynamicScore/GetStuSemesterDynamicScore", ["semesterId": semesterId])
        var grades = GradeData.parse(scores: envelope.data)
        guard !grades.subjects.isEmpty else { throw SchoolisError("成绩接口没返回科目") }
        for i in grades.subjects.indices {
            let subject = grades.subjects[i]
            let detail = try await client.get("/api/DynamicScore/GetDynamicScoreDetail",
                                              ["classId": String(subject.classId), "subjectId": String(subject.id),
                                               "semesterId": semesterId])
            grades.subjects[i].items = GradeData.parseItems(detail: detail.data)
        }
        return grades
    }

    /// 本周和下周的课表（一周从周一开始）
    private static func fetchSchedule(_ client: SchoolisClient) async throws -> [ScheduleEntry] {
        let calendar = SchoolTime.calendar
        guard let monday = calendar.dateInterval(of: .weekOfYear, for: Date())?.start,
              let nextSunday = calendar.date(byAdding: .day, value: 13, to: monday) else { return [] }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = SchoolTime.zone
        day.dateFormat = "yyyy-MM-dd"
        let envelope = try await client.post("/api/Schedule/ListScheduleByParent",
                                             body: ["beginTime": day.string(from: monday), "endTime": day.string(from: nextSunday)])
        return ScheduleEntry.parse(envelope.data).sorted { $0.begin < $1.begin }
    }

    /// 本学期（开学到今天）的考勤
    private static func fetchAttendance(_ client: SchoolisClient, from start: String) async throws -> AttendanceSummary {
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = SchoolTime.zone
        day.dateFormat = "yyyy-MM-dd"
        let today = day.string(from: Date())
        let begin = (start.isEmpty ? today : start) + " 00:00:00"
        let end = today + " 23:59:59"
        // AttendanceType=7 对应网页上的「上课」考勤（来自开源项目 my-xb）
        let overall = try await client.get("/api/Attendance/GetAttendanceStatistic",
                                           ["BeginTime": begin, "EndTime": end, "AttendanceType": "7"])
        let bySubject = try await client.get("/api/Attendance/GetSubjectAttendanceStatistic",
                                             ["BeginTime": begin, "EndTime": end])
        return AttendanceSummary.parse(overall: overall.data, bySubject: bySubject.data,
                                       range: "\(start.isEmpty ? today : start) ~ \(today)")
    }

    /// 每个作业算在成绩构成的哪个项目里。这个只能从作业详情里读，一个作业一个请求，
    /// 所以读过的存起来，以后只读新出现的作业（第一次大约 100 个请求，以后每次只有几个）。
    private static func fetchTaskItems(_ client: SchoolisClient, tasks: [LearningTask],
                                       known: [String: [Int]]) async -> [String: [Int]] {
        var result = known.filter { key, _ in tasks.contains { String($0.id) == key } } // 删掉已经不存在的作业
        var fetched = 0
        var failuresInARow = 0
        for task in tasks where result[String(task.id)] == nil {
            guard fetched < 150 else { break } // 一次最多读 150 个，剩下的下次同步再读
            fetched += 1
            guard let detail = try? await client.get("/api/LearningTask/GetDetail", ["learningTaskId": String(task.id)]) else {
                // 连着出错（登录过期、被限流……）就停下，别对着学校服务器一直发请求，剩下的下次再读
                failuresInARow += 1
                if failuresInARow >= 2 { break }
                continue
            }
            failuresInARow = 0
            result[String(task.id)] = J.array(J.dict(detail.data)["evaProjects"]).compactMap { J.int($0["id"]) }
        }
        return result
    }
}
