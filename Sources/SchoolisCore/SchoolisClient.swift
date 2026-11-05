import Foundation
import CryptoKit

/// 出错时给人看的一句话（中文，说清楚发生了什么、该怎么办）。
public struct SchoolisError: Error, CustomStringConvertible {
    public let description: String
    /// 能不能过一会儿自动再试。密码错、要验证码、没填账号这类，重试只会更糟（可能锁账号），所以是 false
    public let retryable: Bool
    public init(_ description: String, retryable: Bool = true) {
        self.description = description
        self.retryable = retryable
    }
}

/// 学校接口统一的返回格式：{ "data": ..., "state": 0, "msg": ..., "msgCN": ... }
/// state == 0 才算成功。data 的样子每个接口都不一样，所以先不规定类型。
public struct Envelope {
    public let state: Int
    public let message: String
    public let data: Any?
    /// 服务器原样返回的内容，探针会把它存到硬盘上，方便之后对照。
    public let raw: Data
}

/// 和校宝 schoolis 学生端打交道的客户端：负责登录，以及带着登录状态去调接口。
///
/// 规矩（写在这里提醒以后改代码的人）：
/// - 只读。不调用任何提交、修改类的接口。
/// - 慢慢来。每个请求之间停 0.3 秒，不并发，不给学校服务器添麻烦。
/// - 登录失败不自动重试。重试多了会触发图形验证码，甚至锁账号。
public final class SchoolisClient {
    private let baseURL: URL
    private let session: URLSession

    /// baseURL：你学校的校宝网址，比如 https://xxx.schoolis.cn（在设置里填）
    public init(baseURL: URL) {
        // ephemeral（临时）会话：登录后拿到的 Cookie 只放在内存里，程序一退出就没了，不写到硬盘上。
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
        self.baseURL = baseURL
    }

    // MARK: - 登录

    /// 登录。成功时什么都不返回；失败时抛出一句能看懂的错误。
    public func login(user: String, password: String) async throws {
        // 1. 先问服务器要不要图形验证码。返回一张图片就说明要（通常是之前输错太多次）。
        //    程序不能、也不该替你识别验证码，所以直接停下来。
        let captcha = try await request("GET", "/api/MemberShip/GetStudentCaptchaForLogin")
        if let image = captcha.data as? String, !image.isEmpty {
            throw SchoolisError("学校现在要求输入图形验证码。请先在浏览器里手动登录一次校宝，过一会儿再运行。", retryable: false)
        }

        // 2. 按网页的方式算出密码哈希，然后登录。
        let timestamp = Int(Date().timeIntervalSince1970)
        let body: [String: Any] = [
            "name": user,
            "password": Self.passwordHash(password, timestamp: timestamp),
            "timestamp": timestamp,
            "isWeekPassword": false,
            "LanguageType": 1, // 1 = 中文
        ]
        let result = try await request("POST", "/api/MemberShip/Login", query: ["captcha": ""], body: body)

        // 错误码参考了开源项目 lanbinleo/my-xb 的整理。
        switch result.state {
        case 0:
            return
        case 13, 1010076:
            throw SchoolisError("用户名或密码不对（\(result.message)）。请在设置里重新填一次密码。程序不会自动重试。", retryable: false)
        case 1180038:
            throw SchoolisError("学校要求输入图形验证码。请先在浏览器里手动登录一次校宝。", retryable: false)
        default:
            throw SchoolisError("登录失败（state=\(result.state)）：\(result.message)")
        }
    }

    /// 和学校网页 login.js 里的 passwordHash() 一模一样：
    ///   第一步：MD5(明文密码)，转成大写
    ///   第二步：把当前时间戳（秒）直接拼在后面，再 MD5 一次，转成大写
    /// 每次登录的时间戳都不一样，所以发出去的哈希也每次都不一样，明文密码不会在网上传。
    public static func passwordHash(_ plain: String, timestamp: Int) -> String {
        md5Upper(md5Upper(plain) + String(timestamp))
    }

    static func md5Upper(_ text: String) -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02X", $0) }.joined()
    }

    // MARK: - 调接口

    /// GET 请求，state 不是 0 就抛错。
    public func get(_ path: String, _ query: [String: String] = [:]) async throws -> Envelope {
        try checked(await request("GET", path, query: query), path)
    }

    /// POST 请求（发 JSON），state 不是 0 就抛错。
    public func post(_ path: String, body: [String: Any]) async throws -> Envelope {
        try checked(await request("POST", path, body: body), path)
    }

    /// 退出登录，让学校那边的会话也结束。失败了也无所谓。
    public func logout() async {
        _ = try? await request("GET", "/api/MemberShip/LogOut")
    }

    private func checked(_ envelope: Envelope, _ path: String) throws -> Envelope {
        if envelope.state == 999901 {
            throw SchoolisError("\(path)：登录状态失效了（state=999901）。")
        }
        guard envelope.state == 0 else {
            throw SchoolisError("\(path) 返回错误（state=\(envelope.state)）：\(envelope.message)")
        }
        return envelope
    }

    private func request(_ method: String, _ path: String,
                         query: [String: String] = [:],
                         body: [String: Any]? = nil) async throws -> Envelope {
        // 每个请求前停 0.3 秒：慢一点没关系，别给学校服务器添压力。
        try await Task.sleep(nanoseconds: 300_000_000)

        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        var req = URLRequest(url: components.url!)
        req.httpMethod = method
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await session.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SchoolisError("\(path)：服务器返回 HTTP \(http.statusCode)。")
        }
        guard let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) as? [String: Any] else {
            throw SchoolisError("\(path) 返回的不是预期的格式，学校网站可能改版了。")
        }
        let state = (object["state"] as? NSNumber)?.intValue ?? -1
        let message = [object["msgCN"], object["msg"], object["msgEN"]]
            .compactMap { $0 as? String }
            .first { !$0.isEmpty } ?? ""
        let payload = object["data"] is NSNull ? nil : object["data"]
        return Envelope(state: state, message: message, data: payload, raw: data)
    }
}
