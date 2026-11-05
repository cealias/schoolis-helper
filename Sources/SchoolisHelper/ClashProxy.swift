import AppKit
import Foundation

/// 连 Google（Gemini）要走代理。以前得手动打开 Clash Verge 的「系统代理」，现在 App 自己处理：
/// 1. 读 Clash Verge 的配置，找到它的代理端口（默认 7897）；
/// 2. Clash 没在运行，就在后台把它打开（不弹窗口），等端口能连上；
/// 3. 只有发给 Gemini 的请求走这个端口。系统代理开不开都没关系，App 也不改任何系统设置。
/// 智谱在国内，照常直连。
enum ClashProxy {
    static let bundleID = "io.github.clash-verge-rev.clash-verge-rev"

    private static var configFile: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(bundleID)/config.yaml")
    }

    /// 这台电脑装没装 Clash Verge
    @MainActor
    static var isInstalled: Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil }

    /// Clash 的混合代理端口（配置里的 mixed-port，HTTP 和 SOCKS 都能用）
    static func port() -> Int {
        guard let text = try? String(contentsOf: configFile, encoding: .utf8) else { return 7897 }
        for line in text.split(separator: "\n") where line.hasPrefix("mixed-port:") {
            if let number = Int(line.dropFirst("mixed-port:".count).trimmingCharacters(in: .whitespaces)) {
                return number
            }
        }
        return 7897
    }

    /// 端口能不能连上，也就是 Clash 在不在运行。连本机要么马上连上、要么马上被拒绝，不会卡住
    static func isListening(_ port: Int) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(clamping: port).bigEndian)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    /// 准备好代理，返回端口。没装 Clash Verge、或者等了 15 秒还打不开时返回 nil
    @MainActor
    static func prepare() async -> Int? {
        let port = port()
        if isListening(port) { return port }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false // 不抢到最前面
        configuration.hides = true // 打开后藏起来，不弹窗口
        _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        for _ in 0..<30 {
            try? await Task.sleep(nanoseconds: 500_000_000)
            if isListening(port) { return port }
        }
        return nil
    }

    /// 只走 Clash 代理的网络连接（用完记得 finishTasksAndInvalidate）
    static func session(port: Int) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        // 新建的连接默认只等 60 秒。Gemini 开高档思考时会先想一阵子、不传数据，60 秒不够
        configuration.timeoutIntervalForRequest = 150
        configuration.timeoutIntervalForResource = 300
        configuration.connectionProxyDictionary = [
            "HTTPEnable": 1, "HTTPProxy": "127.0.0.1", "HTTPPort": port,
            "HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": port,
        ]
        return URLSession(configuration: configuration)
    }
}
