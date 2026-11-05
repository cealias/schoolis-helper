import AppKit
import Foundation
import SchoolisCore

/// AI 出错时给人看的一句话（云端、本地模型、Antigravity 共用）。
/// 本地模型的代码在 LocalLLM.swift（任意 OpenAI 兼容接口）。
enum LocalAI {
    struct AIError: Error, CustomStringConvertible {
        let description: String
        /// 是不是「对方太忙 / 暂时超额」这类等一下、换个模型就可能好的错误
        let busy: Bool
        /// 是不是等太久超时了（思考程度开太高时可能发生）
        let timedOut: Bool
        init(_ description: String, busy: Bool = false, timedOut: Bool = false) {
            self.description = description
            self.busy = busy
            self.timedOut = timedOut
        }
    }
}

// MARK: - 用哪家的 AI

/// 能选的 AI（按顺序自动接力，前一个不行就换下一个）：
/// - Antigravity CLI（agy）：本机装了就用，免 Key。
/// - Gemini：API 有免费层；中国大陆要走代理，App 会自动走 Clash Verge（见 ClashProxy）。
/// - 智谱 GLM：国内直接能用，GLM-4.7-Flash 免费。
/// - 本地模型：在自己电脑上跑，不联网、免费，但慢，作为兜底。
/// 用第三方云端模型要遵守对应平台的服务条款（包括年龄要求）；未成年人请在监护人指导下使用，或者用本地模型。
/// 云端 AI 的「思考程度」：想得越多越聪明，但越慢。默认最高（Gemini 3.8 Flash 本来就快，开到高也只要十几秒）
enum ThinkingLevel: String, Codable, CaseIterable, Identifiable {
    case high, medium, low

    var id: String { rawValue }

    var title: String {
        switch self {
        case .high: return "高（最聪明）"
        case .medium: return "中"
        case .low: return "低（最快）"
        }
    }
}

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case agy, gemini, zhipu, ollama

    var id: String { rawValue }

    var title: String {
        switch self {
        case .agy: return "Antigravity Gemini（本机 3.8 Flash · 免 Key 最稳）"
        case .gemini: return "Google Gemini（API Key）"
        case .zhipu: return "智谱 GLM（国内直连）"
        case .ollama: return "本地模型（离线，数据不出电脑）"
        }
    }

    var isCloud: Bool { self == .gemini || self == .zhipu }
    var isAgy: Bool { self == .agy }

    /// 钥匙串里存 API Key 用的账号名
    var keyAccount: String { rawValue }
}

/// API Key 存在钥匙串里（不写进普通文件）。和校宝密码一样，通过系统自带的 security 命令存取，
/// 这样重新打包 App 后不会一遍遍弹窗要权限。
enum APIKeyStore {
    static let service = "schoolis-helper-ai"

    static func get(_ account: String) -> String? {
        let (status, output) = run(["find-generic-password", "-s", service, "-a", account, "-w"])
        guard status == 0 else { return nil }
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 已经有了就更新。Key 从标准输入传给 security 命令，不出现在命令行参数里（本机别的程序看得见命令行参数）
    static func set(_ account: String, _ key: String) {
        try? Keychain.save(service: service, account: account, secret: key)
    }

    static func delete(_ account: String) {
        Keychain.delete(service: service, account: account)
    }

    private static func run(_ arguments: [String]) -> (Int32, String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return (-1, "") }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}

/// 云端 AI（Gemini、智谱都提供和 OpenAI 一样的接口格式，所以共用一套代码）
enum CloudAI {
    static func endpoint(_ provider: AIProvider) -> URL {
        switch provider {
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
        default: return URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
        }
    }

    /// 写总结：遇到「太忙」先等几秒重试一次，还不行就换同一家的下一个免费模型。
    /// Key 不对、地区不支持这类错误换模型也没用，直接报出来。
    /// 返回：写好的文字、实际用的模型、过程中的小插曲（比如「3.8 Flash 太忙，换了 3.6 Flash」）
    static func summarize(provider: AIProvider, key: String, preferredModel: String, thinking: ThinkingLevel,
                          system: String, user: String) async throws -> (text: String, model: String, note: String?) {
        var models = [preferredModel]
        if provider == .gemini {
            // 都是免费层能用的 Flash 模型，从聪明到省额度排
            for backup in ["gemini-3.7-flash", "gemini-3.6-flash", "gemini-3.5-flash-lite"] where !models.contains(backup) { models.append(backup) }
        }
        var problems: [String] = []
        for model in models {
            for attempt in 0..<2 {
                do {
                    let text = try await chat(provider: provider, key: key, model: model, thinking: thinking,
                                              system: system, user: user)
                    let note = problems.isEmpty ? nil : problems.joined(separator: "；") + "，这次用的是 \(model)。"
                    return (text, model, note)
                } catch let error as LocalAI.AIError where error.timedOut && thinking != .low {
                    // 想太久超时了：同一个模型用「低」档再写一次（低档一般十几秒）
                    if let text = try? await chat(provider: provider, key: key, model: model, thinking: .low,
                                                  system: system, user: user) {
                        problems.append("「\(thinking.title)」思考档等太久，这次改用「低」档")
                        return (text, model, problems.joined(separator: "；") + "。")
                    }
                    problems.append("\(model) 超时")
                    break
                } catch let error as LocalAI.AIError where error.busy {
                    if attempt == 0 {
                        try? await Task.sleep(nanoseconds: 4_000_000_000) // 等 4 秒再试一次
                    } else {
                        problems.append("\(model) 太忙")
                    }
                } catch where model != preferredModel {
                    // 备用模型出别的错（比如被 Google 下架了），跳过它试下一个；
                    // 设置里选的那个模型出错（Key 不对、地区不支持……）就直接报出来，换别的模型也没用
                    problems.append("\(model) 用不了（\(String(describing: error).prefix(40))）")
                    break
                }
            }
        }
        throw LocalAI.AIError("\(provider.title) 的几个模型都太忙（\(problems.joined(separator: "、"))）", busy: true)
    }

    static func chat(provider: AIProvider, key: String, model: String, thinking: ThinkingLevel,
                     system: String, user: String) async throws -> String {
        do {
            return try await send(provider: provider, key: key, model: model, thinking: thinking, system: system, user: user)
        } catch let error as LocalAI.AIError
                    where error.description.lowercased().contains("thinking") || error.description.lowercased().contains("reasoning") {
            // 有的模型不认识「思考程度」这个参数（或者不支持「中」），去掉再试一次，用它自己的默认值
            return try await send(provider: provider, key: key, model: model, thinking: nil, system: system, user: user)
        }
    }

    private static func send(provider: AIProvider, key: String, model: String, thinking: ThinkingLevel?,
                             system: String, user: String) async throws -> String {
        var request = URLRequest(url: endpoint(provider))
        request.httpMethod = "POST"
        // 思考程度开到高时，它会先想一阵子，这段时间网络上一个字都不传，所以要多等一会儿
        request.timeoutInterval = 150
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        var body: [String: Any] = [
            "model": model,
            "stream": false,
            "temperature": 0.3,
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        // 思考程度（设置里可以改，默认最高）。Gemini 用 reasoning_effort（high / medium / low，3 系列关不掉思考）；
        // 智谱只有开 / 关两档：选「低」就关掉思考，否则打开
        if let thinking {
            switch provider {
            case .gemini: body["reasoning_effort"] = thinking.rawValue
            default: body["thinking"] = ["type": thinking == .low ? "disabled" : "enabled"]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        // Gemini 走 Clash 代理（没开会自动在后台打开），智谱直连
        var session = URLSession.shared
        var proxyPort: Int?
        if provider == .gemini {
            proxyPort = await ClashProxy.prepare()
            if let proxyPort { session = ClashProxy.session(port: proxyPort) }
        }
        defer { if session !== URLSession.shared { session.finishTasksAndInvalidate() } }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            if (error as? URLError)?.code == .timedOut {
                throw LocalAI.AIError("\(provider.title) 想太久，等了 2 分半还没写完", timedOut: true)
            }
            if provider != .gemini { throw LocalAI.AIError("连不上智谱，检查一下网络") }
            throw LocalAI.AIError(proxyPort == nil
                ? "连不上 Google：没找到 Clash Verge，或者等了 15 秒还没打开。手动打开 Clash Verge 再试一次"
                : "连不上 Google：Clash 已经开了，可能是节点不行。在 Clash Verge 里换香港 / 日本 / 新加坡 / 美国节点（台湾不行），并且不要选「直连」模式")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard status == 200 else {
            // Gemini 有时把错误包在一个数组里：[{"error": {...}}]
            let errorObject = (object?["error"] as? [String: Any])
                ?? ((try? JSONSerialization.jsonObject(with: data) as? [[String: Any]])?.first?["error"] as? [String: Any])
            let message = (errorObject?["message"] as? String) ?? String(decoding: data.prefix(200), as: UTF8.self)
            let busy = status == 429 || status == 500 || status == 502 || status == 503 || status == 504
            throw LocalAI.AIError(explain(provider: provider, status: status, message: message), busy: busy)
        }
        let choices = object?["choices"] as? [[String: Any]]
        var text = ((choices?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
        if let range = text.range(of: "</think>") { text = String(text[range.upperBound...]) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalAI.AIError("\(provider.title) 返回了空内容") }
        return text
    }

    /// 把错误翻译成人话
    private static func explain(provider: AIProvider, status: Int, message: String) -> String {
        let lower = message.lowercased()
        if lower.contains("location") && lower.contains("not supported") {
            return "Gemini 不支持你现在的网络地区。在 Clash Verge 里把节点换成香港 / 日本 / 新加坡 / 美国（台湾不行）"
        }
        if status == 401 || status == 403 || lower.contains("api key") {
            return "API Key 不对或者已经失效，请重新复制一次（\(message)）"
        }
        if status == 429 {
            return "免费额度暂时用完了（每分钟或每天有上限），过一会儿再试，不会扣钱"
        }
        if status == 503 || status == 500 || status == 502 || status == 504 {
            return "\(provider.title) 那边这会儿太忙（服务器临时过载，不是你的问题），过一会儿再试"
        }
        if message.contains("余额") || message.contains("欠费") {
            return "账户余额不足：选的模型要付费。智谱免费的是 glm-4.7-flash（\(message)）"
        }
        return "\(provider.title) 返回错误 \(status)：\(message)"
    }
}

// MARK: - 交给 AI 的全局数据

/// AI 总结支持的动态组件类型
enum AISummaryBlockType: String, Codable, Equatable {
    case alert       // 紧急警报（逾期作业、未完成标记、缺勤预警）
    case todo        // 待办/任务清单（支持 1~3 条，包含动作、科目、作业名、截止时间、扣分涨分原因）
    case boost       // 提分捷径（GPA 涨幅最大的杠杆动作）
    case schedule    // 日程/课程预告（明天或下一次上课安排）
    case tip         // 学习学长贴士/复习建议/好习惯
}

/// AI 总结的单个卡片组件
struct AISummaryBlock: Codable, Equatable, Identifiable {
    var id: String {
        "\(type.rawValue)-\(title ?? "")-\(action ?? "")-\(items?.first?.action ?? "")-\(detail ?? "")"
    }

    var type: AISummaryBlockType
    var title: String?
    var level: String?   // "urgent", "warning", "info"
    var action: String?
    var detail: String?
    var result: String?
    var subject: String?
    var time: String?
    var items: [TodoItem]?

    struct TodoItem: Codable, Equatable, Identifiable {
        var id: String { "\(action)-\(task ?? "")-\(due ?? "")" }
        var action: String
        var task: String?
        var subject: String?
        var due: String?
        var why: String?
    }
}

/// AI 写的结构化总结：
/// 顶层一句话大字（headline）+ AI 自主决定的动态卡片列表（blocks）。
/// 客户端做统一的高质感接口与渲染，由 AI 根据当天真实数据自主编排。
struct AISummary: Codable, Equatable {
    typealias Todo = AISummaryBlock.TodoItem
    struct Boost: Codable, Equatable {
        var action: String
        var result: String?
    }

    var headline: String
    var blocks: [AISummaryBlock]

    // 便捷属性，兼容老调用
    var todo: [Todo] {
        blocks.first(where: { $0.type == .todo })?.items ?? []
    }
    var boost: Boost? {
        guard let b = blocks.first(where: { $0.type == .boost }), let act = b.action, !act.isEmpty else { return nil }
        return Boost(action: act, result: b.result)
    }
    var tomorrow: String? {
        blocks.first(where: { $0.type == .schedule })?.detail
    }

    private enum CodingKeys: String, CodingKey {
        case headline, blocks, todo, boost, tomorrow
    }

    init(headline: String, blocks: [AISummaryBlock]) {
        self.headline = headline
        self.blocks = blocks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        headline = (try? c.decode(String.self, forKey: .headline)) ?? ""
        if let decodedBlocks = try? c.decodeIfPresent([AISummaryBlock].self, forKey: .blocks), !decodedBlocks.isEmpty {
            blocks = decodedBlocks
        } else {
            // 向后兼容旧格式
            var converted: [AISummaryBlock] = []
            if let oldTodo = try? c.decodeIfPresent([Todo].self, forKey: .todo), !oldTodo.isEmpty {
                converted.append(AISummaryBlock(type: .todo, title: "今日必做", items: oldTodo))
            }
            if let oldBoost = try? c.decodeIfPresent(Boost.self, forKey: .boost), !oldBoost.action.isEmpty {
                converted.append(AISummaryBlock(type: .boost, title: "提分捷径", action: oldBoost.action, result: oldBoost.result))
            }
            if let oldTomorrow = try? c.decodeIfPresent(String.self, forKey: .tomorrow), !oldTomorrow.isEmpty {
                converted.append(AISummaryBlock(type: .schedule, title: "下次上课", detail: oldTomorrow))
            }
            blocks = converted
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(headline, forKey: .headline)
        try c.encode(blocks, forKey: .blocks)
    }

    /// 从 AI 的回答里找出 JSON。偶尔它会在前后多说几句、或者包一层 ```json，都能处理；实在读不出来返回 nil
    static func parse(_ text: String) -> AISummary? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              var summary = try? JSONDecoder().decode(AISummary.self, from: Data(text[start...end].utf8)) else { return nil }
        summary.headline = summary.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.headline.isEmpty else { return nil }
        return summary
    }
}

/// AI 提过哪些事、哪几天提的（存在 ai-reminders.json）。
/// 用户嫌总结「每天都说同一件事，跟个傻子一样」，所以：过了截止的事提一次就不再提；提分建议最多提两天。
struct AIReminders: Codable {
    /// 「task:作业 id」或「item:科目 id:项目路径」→ 提过的日子（2026-10-17）
    var days: [String: [String]] = [:]

    static func dayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = SchoolTime.zone
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// 今天以前提过几天（同一天重写几次只算一天）
    func daysBefore(_ key: String, today: String) -> Int {
        Set((days[key] ?? []).filter { $0 < today }).count
    }

    /// 记下今天提过哪些事，顺便删掉 60 天以前的记录
    mutating func record(_ keys: [String], now: Date) {
        let today = Self.dayKey(now)
        for key in keys where !(days[key] ?? []).contains(today) { days[key, default: []].append(today) }
        let cutoff = Self.dayKey(now.addingTimeInterval(-60 * 24 * 3600))
        days = days.compactMapValues { list in
            let kept = list.filter { $0 >= cutoff }
            return kept.isEmpty ? nil : kept
        }
    }
}

/// 交给 AI 的数据，外加「哪些事可以记进提醒记录」
struct SummaryInput {
    let text: String
    /// （提醒记录里的键，在 AI 的回答里找的字）：回答里出现了这个作业名 / 项目名，就算提过了
    let trackable: [(key: String, needle: String)]

    /// 从 AI 的回答里找出这次提了哪些事
    func mentionedKeys(in summary: AISummary) -> [String] {
        var texts: [String] = []
        for block in summary.blocks {
            if let a = block.action { texts.append(a) }
            if let d = block.detail { texts.append(d) }
            if let items = block.items {
                for item in items {
                    texts.append(item.action)
                    if let t = item.task { texts.append(t) }
                }
            }
        }
        return trackable.filter { item in
            item.needle.count >= 4 && texts.contains { $0.contains(item.needle) }
        }.map(\.key)
    }
}

/// 交给 AI 的「事实」：作业、成绩、课表、考勤全部放进来，每一条都是程序算好的。
/// AI 只负责挑重点、排先后、把话说顺，不许自己编。
enum SummaryFacts {
    static let systemPrompt = """
    你是一位初中生的专属学习顾问兼贴心学长，说话亲切、务实、具体，一句废话都没有。
    下面会给你一份 JSON，是这个学生今天的真实数据：作业、成绩、课表、考勤，每一条都是程序预先算好的事实。
    你的任务：帮他理清节奏，让他一眼明白今天该关注什么、怎么做。宁可精炼，绝不堆砌。

    【核心能力：自主决定展示卡片】
    我们为你提供了 5 种结构化卡片（blocks）。请你根据今日真实情况的紧急程度与需要，自主决定输出哪些卡片及先后顺序（不需要每样都出，没有就绝对不硬凑！）：

    1. "alert"（紧急警报）：
       - 何时使用：有「老师记为未完成」的作业、有即将大扣分的已逾期作业、或缺勤/早退异常时使用。
       - 字段：
         "type": "alert",
         "level": "urgent"（严重/高危）或 "warning"（注意/警告）或 "info"（提醒）,
         "title": "简短醒目标题（如「未完成作业补救」或「出勤预警」）",
         "detail": "具体说明与一句话动作指引，照抄作业名"
       - 规则：如果今天没有任何紧急警告，绝对不输出 alert 卡片！

    2. "todo"（任务清单）：
       - 何时使用：有今天截止、明天截止或 7 天内需要提前准备（课上考、展示）的作业时使用。
       - 字段：
         "type": "todo",
         "title": "清单标题，如「今日必做」或「今晚复习」",
         "items": [
           {
             "action": "动词开头的具体小动作，不超过 12 个字，比如「复习第 7 章词汇」「整理科学笔记本」",
             "task": "作业名，原样照抄",
             "subject": "科目，原样照抄",
             "due": "截止时间，照抄（比如「今天 17:00」）；已经过了截止的写「已过期」",
             "why": "不超过 12 个字，带一个具体数字，比如「满分这科 +3.9」「0 分这科掉到 A-」"
           }
         ]
       - 规则：items 最多 3 条。如果今天没有任何作业要赶，不要输出 todo 卡片。

    3. "boost"（提分捷径）：
       - 何时使用：能算出让 GPA 最快上涨的具体动作时使用。
       - 字段：
         "type": "boost",
         "title": "提分捷径",
         "action": "具体提分动作，不超过 20 个字，作业名原样照抄",
         "result": "GPA 变化，原样照抄，比如「GPA 3.86 → 3.92」"
       - 规则：如果该动作已在 todo 里，选下一条能涨 GPA 的事；没有可行的提分动作则不输出 boost。

    4. "schedule"（日程/课程预告）：
       - 何时使用：预告下一个上学日或明天的第一节课。
       - 字段：
         "type": "schedule",
         "title": "明天上学写「明日首堂课」，明天不上学写具体哪天（如「周一首堂课」）",
         "time": "时间，如「08:30」",
         "detail": "课名与教室，照抄，如「历史（A101）」"

    5. "tip"（学长贴士/好习惯）：
       - 何时使用：根据当前考勤、弱科突破、复习方法或周末放松节奏，给一句亲切务实的学长经验点拨（不超过 25 个字）。
       - 字段：
         "type": "tip",
         "title": "贴士",
         "detail": "简短务实的一句话建议"

    【铁律】
    1. 作业名、科目、截止时间、分数、GPA，必须原样照抄 JSON 事实，绝对不许编造或互相拼接。
    2. 分清单位：「这科 86.0 → 92.5」是科目百分制分数；GPA 只看「GPA x → y」。
    3. 动作要与作业类型对齐（括号里写完成方式）：要交的才说「交/写完」，课上考是「复习」，课上检查是「整理本子」，课上展示是「准备/排练」。
    4. 「今天上不上学」写着不上学时，不许说「今天找老师」「今天交」，要说「周一」或「下一个上学日」。

    【输出格式】
    只输出一个 JSON 对象，不要 Markdown 代码块，不要任何多余文字：
    {
      "headline": "一句话，不超过 22 个字：今天最核心的节奏或重点，可带一点鼓励",
      "blocks": [
        ...你自主决定的卡片列表，顺序由你按紧急程度决定...
      ]
    }
    """

    static func build(snapshot: Snapshot, derived: Derived, target: Double, now: Date,
                      reminders: AIReminders = AIReminders()) -> SummaryInput {
        func f(_ x: Double) -> String { Format.number(GradeMath.round1(x)) }
        func g(_ x: Double) -> String { String(format: "%.2f", x) }
        let report = derived.report
        let calendar = SchoolTime.calendar
        let today = AIReminders.dayKey(now)
        var trackable: [(key: String, needle: String)] = []

        // 作业 id → 它的涨分 / 掉分（只有能算出来的作业才有）
        var leverByTask: [Int: GradeMath.Lever] = [:]
        for levers in derived.levers.values {
            for lever in levers { if let id = lever.taskId, leverByTask[id] == nil { leverByTask[id] = lever } }
        }
        // 涨 / 掉以后这科变成多少分、什么等级，也替 AI 算好（不然小模型会自己瞎推等级）
        var gradeBySubject: [String: SubjectGrade] = [:]
        for subject in snapshot.grades?.subjects ?? [] { gradeBySubject[subject.name] = subject }
        func outcome(_ subjectName: String, _ delta: Double) -> String {
            guard let bands = snapshot.grades?.bands, let subject = gradeBySubject[subjectName],
                  let score = subject.score, let band = GradeMath.band(for: score, in: bands) else { return "" }
            let newScore = GradeMath.round1(score + delta)
            let newBand = GradeMath.band(for: newScore, in: bands) ?? band
            return "（这科 \(f(score)) → \(f(newScore))，" + (newBand == band ? "等级不变，还是 \(band.name)" : "等级 \(band.name) → \(newBand.name)") + "）"
        }
        func taskLines(_ tasks: [LearningTask], limit: Int) -> [String] {
            tasks.prefix(limit).map { task in
                trackable.append((key: "task:\(task.id)", needle: task.name))
                // 括号里写它是怎么完成的：AI 据此说「复习」「整理本子」「准备展示」还是「写完交」
                var text = "「\(task.name)」\(task.subjectName)，\(Format.shortDeadline(task)) 截止（\(task.mode.hint)）"
                if let total = task.totalScore, total > 0 { text += "，满分 \(Format.number(total))" }
                if let lever = leverByTask[task.id] {
                    let zero = task.mode == .submit ? "没交或 0 分" : "0 分"
                    if lever.gain > 0 { text += "；拿满分这科 +\(f(lever.gain))\(outcome(task.subjectName, lever.gain))" }
                    if lever.loss > 0 { text += "；\(zero)这科 −\(f(lever.loss))\(outcome(task.subjectName, -lever.loss))" }
                } else {
                    text += "；（算不出对成绩的影响）"
                }
                return text
            }
        }

        // 过了截止的：已经提醒过的就不再给 AI（每天说同一件事像个傻子）；老师记「未完成」但不计分的也不提
        let freshOverdue = report.overdue.filter { reminders.daysBefore("task:\($0.id)", today: today) == 0 }
        let freshNotDone = report.markedNotDone.filter {
            ($0.totalScore ?? 0) > 0 && reminders.daysBefore("task:\($0.id)", today: today) == 0
        }

        var facts: [String: Any] = [
            "现在": dayText(now) + " " + Format.syncTime.string(from: now).suffix(5),
            "今天截止": taskLines(report.today, limit: 8),
            "明天截止": taskLines(report.tomorrow, limit: 8),
            "7 天内截止": taskLines(report.within7Days, limit: 8),
            "过了截止还没记录（要交的作业：可能交了纸质版老师还没登，也可能真忘了）": taskLines(freshOverdue, limit: 3),
            "老师记为未完成（老师已经登记没交，这个才需要找老师）": taskLines(freshNotDone, limit: 3),
        ]

        // 成绩
        if let grades = snapshot.grades, let plan = derived.gradePlan {
            let current = snapshot.gpa ?? GradeMath.floor2(plan.currentGPA)
            facts["官网动态 GPA"] = g(current)
            facts["目标 GPA"] = g(target)
            facts["离目标还差"] = plan.alreadyThere ? "已经达到目标" : g(max(0, target - current))
            facts["最省力的提分方案"] = plan.options.isEmpty ? ["没有 3 科以内能做到的方案"] : plan.options.map { option in
                option.steps.map { "\($0.subjectName) \(f($0.currentScore)) → \(f($0.to.min))（\($0.from.name) → \($0.to.name)）" }
                    .joined(separator: " + ") + "，总共提 \(f(option.totalDelta)) 分，GPA 变成 \(g(GradeMath.floor2(option.resultingGPA)))"
            }
            facts["各科现在"] = grades.subjects.filter(\.isInGrade).compactMap { subject -> String? in
                guard let score = subject.score, let band = GradeMath.band(for: score, in: grades.bands) else { return nil }
                var text = "\(subject.name)：\(f(score)) 分，\(band.name)（绩点 \(Format.number(band.gpa))）"
                if let next = GradeMath.steps(for: subject, bands: grades.bands, maxSteps: 1).first {
                    text += "，离 \(next.to.name) 还差 \(f(next.delta)) 分"
                } else {
                    text += "，已经是最高等级"
                }
                return text
            }

            // 能涨 GPA 的事：按「GPA 能涨多少、这科能涨多少」排好
            func gpaIf(_ subject: SubjectGrade, _ newScore: Double) -> Double {
                GradeMath.floor2(GradeMath.gpa(grades.subjects, bands: grades.bands, scores: [subject.id: newScore]) ?? plan.currentGPA)
            }
            var tasksById: [Int: LearningTask] = [:]
            for task in snapshot.tasks { tasksById[task.id] = task }
            struct Candidate { let gpaGain: Double; let gain: Double; let text: String; let key: String; let needle: String }
            var candidates: [Candidate] = []
            for subject in grades.subjects where subject.isInGrade {
                guard let score = subject.score, let band = GradeMath.band(for: score, in: grades.bands) else { continue }
                let all = (derived.levers[subject.id] ?? []).filter { $0.gain > 0 }
                // 同一个项目里已经有具体作业可做时，就不再单独列「把这个项目提到满分」，免得一件事说两遍
                let pathsWithTasks = Set(all.filter { $0.kind != .weakItem }.map(\.path))
                for lever in all where !(lever.kind == .weakItem && pathsWithTasks.contains(lever.path)) {
                    let newScore = GradeMath.round1(score + lever.gain)
                    let newBand = GradeMath.band(for: newScore, in: grades.bands) ?? band
                    let newGPA = gpaIf(subject, newScore)
                    let action: String
                    switch lever.kind {
                    case .weakItem: action = "把「\(lever.path)」这一项提到满分"
                    case .redoTask: action = "补交或重做「\(lever.title)」拿满分（要先问老师能不能）"
                    case .pendingTask: action = "认真完成「\(lever.title)」拿满分"
                    }
                    var deadline = ""
                    if let id = lever.taskId, let task = tasksById[id], lever.kind == .pendingTask {
                        deadline = "（\(Format.shortDeadline(task)) 截止）"
                    }
                    var text = "\(subject.name)：\(action)\(deadline) → 这科 \(f(score)) → \(f(newScore))，"
                    text += newBand == band ? "等级不变（\(band.name)）" : "等级 \(band.name) → \(newBand.name)"
                    text += "，GPA \(g(current)) → \(g(newGPA))"
                    let key = lever.taskId.map { "task:\($0)" } ?? "item:\(subject.id):\(lever.path)"
                    // 同一条提分建议已经连着提过两天了，换别的说（不然每天都是同一句「补交某某作业」）
                    if lever.kind != .pendingTask && reminders.daysBefore(key, today: today) >= 2 { continue }
                    candidates.append(Candidate(gpaGain: newGPA - current, gain: lever.gain, text: text, key: key,
                                                needle: lever.kind == .weakItem ? lever.path : lever.title))
                }
            }
            candidates.sort { ($0.gpaGain, $0.gain) > ($1.gpaGain, $1.gain) }
            let top = candidates.prefix(8)
            trackable += top.map { (key: $0.key, needle: $0.needle) }
            facts["能涨 GPA 的事（已经排好序，越靠前越值得做）"] = top.map(\.text)
        }

        // 课表
        let schedule = snapshot.schedule ?? []
        func classLines(on day: Date, after: Date? = nil) -> [String] {
            schedule.filter { entry in
                guard let begin = entry.beginDate, calendar.isDate(begin, inSameDayAs: day) else { return false }
                return after.map { (entry.endDate ?? begin) > $0 } ?? true
            }
            .sorted { $0.begin < $1.begin }
            .map { entry in
                let time = [entry.beginDate, entry.endDate].compactMap { $0 }.map { Format.syncTime.string(from: $0).suffix(5) }.joined(separator: "–")
                return "\(time) \(entry.name)" + (entry.room.isEmpty ? "" : "（\(entry.room)）")
            }
        }
        func hasClasses(_ day: Date) -> Bool {
            schedule.contains { $0.beginDate.map { calendar.isDate($0, inSameDayAs: day) } ?? false }
        }
        // 周末找不到老师，AI 不能说「今天找老师 / 今天交」
        facts["今天上不上学"] = hasClasses(now) ? "上学" : "今天不上学（周末或放假），找不到老师"
        let todayLeft = classLines(on: now, after: now)
        facts["今天还没上的课"] = todayLeft.isEmpty ? ["今天的课已经上完了（或者今天没课）"] : todayLeft
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) {
            let lines = classLines(on: tomorrow)
            facts["明天的课"] = lines.isEmpty ? ["明天不上学"] : lines
            if lines.isEmpty,
               let next = (2...10).lazy.compactMap({ calendar.date(byAdding: .day, value: $0, to: now) }).first(where: hasClasses) {
                facts["下一个上学日"] = dayText(next)
                facts["下一个上学日的课"] = classLines(on: next)
            }
        }

        // 考勤
        if let attendance = snapshot.attendance {
            var text = "本学期出勤率 \(attendance.rate.map { String(format: "%.2f%%", $0) } ?? "未知")，迟到 \(attendance.late) 次，早退 \(attendance.earlyLeave) 次，缺勤 \(attendance.absent) 次"
            if let worst = attendance.subjects.filter({ $0.absent > 0 }).max(by: { $0.absent < $1.absent }) {
                text += "；缺勤最多的是「\(worst.name)」\(worst.absent) 次"
            }
            facts["考勤"] = text
        }

        let data = (try? JSONSerialization.data(withJSONObject: facts, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return SummaryInput(text: String(decoding: data, as: UTF8.self), trackable: trackable)
    }

    private static func dayText(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.timeZone = SchoolTime.zone
        f.dateFormat = "M月d日 EEEE"
        return f.string(from: date)
    }
}
