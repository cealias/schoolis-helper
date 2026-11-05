import AppKit
import UserNotifications
import SchoolisCore

// MARK: - 设置

/// 一天中的某个时刻，比如 07:00
struct HourMinute: Codable, Hashable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    init(date: Date) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        hour = parts.hour ?? 0
        minute = parts.minute ?? 0
    }

    /// 今天的这个时刻（给时间选择器用）
    var date: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date()) ?? Date()
    }

    var text: String { String(format: "%02d:%02d", hour, minute) }

    static func < (a: HourMinute, b: HourMinute) -> Bool {
        (a.hour, a.minute) < (b.hour, b.minute)
    }
}

/// 提醒的方式
enum AlertStyle: String, Codable, CaseIterable, Identifiable {
    /// 弹出主窗口，在最上面显示提醒内容，并响一声
    case popup
    /// macOS 系统通知（横幅还是一直停着，由「系统设置 → 通知」决定）
    case system
    /// 什么都不弹，只更新菜单栏上的数字
    case badgeOnly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .popup: return "弹窗（打开主窗口 + 提示音）"
        case .system: return "系统通知"
        case .badgeOnly: return "只更新菜单栏数字"
        }
    }
}

struct AppSettings: Codable, Equatable {
    /// 学校的校宝网址，比如 https://xxx.schoolis.cn（设置 → 校宝账号）
    var schoolURL = ""
    /// 校宝账号（密码不在这里，在钥匙串里）
    var schoolAccount = ""
    /// 首页怎么称呼你，比如「早上好，小明」；空着就叫「同学」
    var nickname = ""
    var autoSync = true
    var syncTimes = [HourMinute(hour: 7, minute: 0), HourMinute(hour: 18, minute: 30)]
    var urgentStyle = AlertStyle.popup
    var summaryStyle = AlertStyle.system
    /// 提分计划的目标 GPA
    var targetGPA = 4.0
    /// 本地模型（离线兜底）：任意 OpenAI 兼容接口，比如 llama.cpp 的 llama-server、Ollama（http://127.0.0.1:11434/v1）
    var localAIURL = "http://127.0.0.1:8080/v1"
    /// 本地模型的名字（Ollama 里的名字，或者 llama-server 的 --alias）；空着就用服务器默认的
    var localAIModel = ""
    /// 本地服务没开时，用来在后台启动它的脚本（可选）；写完总结就关掉
    var localAILaunchScript = ""
    /// 优先用哪家的 AI（默认若本机安装了 agy 则用 agy，免 Key 不卡顿）
    var aiProvider = AgyAI.isAvailable ? AIProvider.agy : AIProvider.gemini
    /// Gemini 用哪个模型（免费层就能用）
    var geminiModel = "gemini-3.8-flash"
    /// 智谱用哪个模型。glm-4.7-flash 免费；glm-5.3-flash 更聪明但要付费（很便宜）
    var zhipuModel = "glm-4.7-flash"
    /// 云端 AI 的思考程度，默认最高
    var aiThinking = ThinkingLevel.high

    /// 当前选的云端 AI 用哪个模型
    var cloudModel: String { aiProvider == .gemini ? geminiModel : zhipuModel }

    init() {}

    // 以后加新设置时，旧的设置文件里没有那一项，就用默认值，不至于整个读不出来
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        schoolURL = (try? c.decodeIfPresent(String.self, forKey: .schoolURL)) ?? defaults.schoolURL
        schoolAccount = (try? c.decodeIfPresent(String.self, forKey: .schoolAccount)) ?? defaults.schoolAccount
        nickname = (try? c.decodeIfPresent(String.self, forKey: .nickname)) ?? defaults.nickname
        localAIURL = (try? c.decodeIfPresent(String.self, forKey: .localAIURL)) ?? defaults.localAIURL
        localAIModel = (try? c.decodeIfPresent(String.self, forKey: .localAIModel)) ?? defaults.localAIModel
        localAILaunchScript = (try? c.decodeIfPresent(String.self, forKey: .localAILaunchScript)) ?? defaults.localAILaunchScript
        autoSync = (try? c.decodeIfPresent(Bool.self, forKey: .autoSync)) ?? defaults.autoSync
        syncTimes = (try? c.decodeIfPresent([HourMinute].self, forKey: .syncTimes)) ?? defaults.syncTimes
        urgentStyle = (try? c.decodeIfPresent(AlertStyle.self, forKey: .urgentStyle)) ?? defaults.urgentStyle
        summaryStyle = (try? c.decodeIfPresent(AlertStyle.self, forKey: .summaryStyle)) ?? defaults.summaryStyle
        targetGPA = (try? c.decodeIfPresent(Double.self, forKey: .targetGPA)) ?? defaults.targetGPA
        aiProvider = (try? c.decodeIfPresent(AIProvider.self, forKey: .aiProvider)) ?? defaults.aiProvider
        zhipuModel = (try? c.decodeIfPresent(String.self, forKey: .zhipuModel)) ?? defaults.zhipuModel
        geminiModel = (try? c.decodeIfPresent(String.self, forKey: .geminiModel)) ?? defaults.geminiModel
        aiThinking = (try? c.decodeIfPresent(ThinkingLevel.self, forKey: .aiThinking)) ?? defaults.aiThinking
    }
}

/// 定时同步的进度：最近一个已经处理过的同步时间点
struct SyncState: Codable {
    var lastSlotHandled: Date?
}

extension AppFiles {
    static let settings = directory.appendingPathComponent("settings.json")
    static let syncState = directory.appendingPathComponent("sync-state.json")
    static let aiAdvice = directory.appendingPathComponent("ai-advice.json")
    /// AI 提过哪些事（过期的事只提一次，见 AIReminders）
    static let aiReminders = directory.appendingPathComponent("ai-reminders.json")
    static let gpaHistory = directory.appendingPathComponent("gpa-history.json")
}

/// 一次同步时的 GPA 记录
struct GPARecord: Codable {
    let date: Date
    let official: Double?
    let computed: Double?
    let points: [String: Double]
}

// MARK: - 同步时间点

enum Schedule {
    /// 在 date 之前（含）最近的一个同步时间点。
    /// 比如设置了 07:00 和 18:30：现在 20:15 → 今天 18:30；现在 06:00 → 昨天 18:30。
    static func latestSlot(_ times: [HourMinute], atOrBefore date: Date) -> Date? {
        let calendar = Calendar.current
        var best: Date?
        for dayOffset in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: date) else { continue }
            for time in times {
                guard let slot = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: day),
                      slot <= date else { continue }
                if best.map({ slot > $0 }) ?? true { best = slot }
            }
        }
        return best
    }
}

// MARK: - 定时任务（LaunchAgent）

/// macOS 自带的定时机制。装好之后，就算 App 退出了，到点也会在后台把它启动起来。
///
/// 文件位置：~/Library/LaunchAgents/io.github.cealias.schoolishelper.plist
/// 手动卸载（README 里也写了）：
///   launchctl bootout gui/$(id -u)/io.github.cealias.schoolishelper
///   rm ~/Library/LaunchAgents/io.github.cealias.schoolishelper.plist
enum LaunchAgent {
    static let label = "io.github.cealias.schoolishelper"

    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }

    static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

    static func install(times: [HourMinute], appPath: String) throws {
        // 到点时执行的命令：
        //   App 已经在运行 → 什么都不做（App 自己每分钟检查，会在这一分钟内同步）
        //   App 没在运行   → 在后台启动它（不弹窗口），它启动后会自己同步
        // 为什么不让定时任务直接运行 App：那样 App 会变成定时任务的「子进程」，
        // 以后改时间、重新装定时任务时，系统会把正在运行的 App 一起关掉。
        let quotedPath = appPath.replacingOccurrences(of: "'", with: "'\\''")
        let command = "pgrep -x SchoolisHelper >/dev/null || open -g '\(quotedPath)' --args --background"
        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": ["/bin/sh", "-c", command],
            "StartCalendarInterval": times.map { ["Hour": $0.hour, "Minute": $0.minute] },
            // 登录（开机）时也执行一次：把关机期间错过的同步补上
            "RunAtLoad": true,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)

        // 内容没变、而且已经装载着，就不用重装
        if let old = try? Data(contentsOf: plistURL), old == data, isLoaded { return }

        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: plistURL, options: .atomic)
        launchctl(["bootout", "gui/\(getuid())/\(label)"]) // 先把旧的卸掉，没有也没关系
        let status = launchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        if status != 0 {
            throw SchoolisError("launchctl 装载失败（返回 \(status)）")
        }
    }

    static func uninstall() {
        launchctl(["bootout", "gui/\(getuid())/\(label)"])
        try? FileManager.default.removeItem(at: plistURL)
    }

    static var isLoaded: Bool {
        launchctl(["print", "gui/\(getuid())/\(label)"]) == 0
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            return -1
        }
    }
}

// MARK: - 系统通知

@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    /// 点了通知之后做什么（由 AppDelegate 设置：打开主窗口）
    var onClick: () -> Void = {}

    func setUp() {
        UNUserNotificationCenter.current().delegate = self
    }

    /// 第一次会弹出系统询问「学习助手 想给你发送通知」
    func requestAuthorization() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func statusText() async -> String {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return settings.alertStyle == .alert
                ? "已允许 · 现在是「提醒」样式：通知会一直停在屏幕上，直到你点掉"
                : "已允许 · 现在是「横幅」样式：通知几秒后自动消失"
        case .denied:
            return "被关掉了 · 要收到系统通知，去「系统设置 → 通知 → 学习助手」打开"
        case .notDetermined:
            return "还没决定"
        @unknown default:
            return "状态未知"
        }
    }

    /// 发一条系统通知。同一个 id 会替换掉旧的那条，免得通知中心里堆一大串。
    func post(id: String, title: String, body: String, sound: Bool) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if sound { content.sound = .default }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    /// App 在前台时也照样显示通知
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// 点通知 → 打开主窗口
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { Notifier.shared.onClick() }
    }

    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
