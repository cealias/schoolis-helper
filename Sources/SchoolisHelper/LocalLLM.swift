import Foundation
import SchoolisCore

/// 本地模型（离线兜底）：任意 OpenAI 兼容接口——llama.cpp 的 llama-server、Ollama（http://127.0.0.1:11434/v1）、LM Studio 等。
/// 地址、模型名、启动脚本都在「设置 → AI → 本地模型」里填。
/// - 服务已经开着：直接用，用完不关。
/// - 没开、但填了启动脚本：在后台运行脚本，等服务准备好再用，写完总结就关掉（大模型很占内存）。
enum LocalLLM {
    struct Config {
        let baseURL: URL
        let model: String
        let launchScript: String
    }

    static func config(from settings: AppSettings) -> Config? {
        let text = settings.localAIURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text.hasSuffix("/") ? String(text.dropLast()) : text), url.scheme != nil else { return nil }
        return Config(baseURL: url,
                      model: settings.localAIModel.trimmingCharacters(in: .whitespacesAndNewlines),
                      launchScript: (settings.localAILaunchScript.trimmingCharacters(in: .whitespacesAndNewlines)
                                     as NSString).expandingTildeInPath)
    }

    /// 连本机不走代理；大模型读得慢，多等一会儿
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        configuration.timeoutIntervalForRequest = 600
        configuration.timeoutIntervalForResource = 900
        return URLSession(configuration: configuration)
    }()

    static func isRunning(_ config: Config) async -> Bool {
        var request = URLRequest(url: config.baseURL.appendingPathComponent("models"))
        request.timeoutInterval = 3
        guard let (_, response) = try? await session.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    /// 写一份总结，返回写好的文字
    @MainActor
    static func chat(_ config: Config, system: String, user: String,
                     status: @MainActor (String) -> Void) async throws -> String {
        var started: Process?
        if !(await isRunning(config)) {
            guard !config.launchScript.isEmpty, FileManager.default.isExecutableFile(atPath: config.launchScript) else {
                throw LocalAI.AIError("本地模型没开（\(config.baseURL.absoluteString)）。先把它打开，或者在设置里填一个启动脚本")
            }
            status("正在后台启动本地模型（第一次大约半分钟）…")
            started = try launch(config.launchScript)
            LocalLLMProcess.shared.process = started
            var ready = false
            for _ in 0..<90 { // 最多等 3 分钟
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                if await isRunning(config) { ready = true; break }
                if started?.isRunning == false { break }
            }
            guard ready else {
                LocalLLMProcess.shared.stop()
                throw LocalAI.AIError("本地模型没能启动起来，检查一下启动脚本")
            }
        }
        defer { if started != nil { LocalLLMProcess.shared.stop() } } // 是我们开的就关掉；你自己开的不动

        status("本地模型正在写总结（大约 1～3 分钟，可以先去干别的）…")
        var request = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = [
            "temperature": 0.3,
            "max_tokens": 1500,
            // 不要先「思考」：本地模型慢，先想一大段的话 10 分钟都写不完（llama.cpp 认这个参数，别的服务会忽略）
            "chat_template_kwargs": ["enable_thinking": false],
            "messages": [["role": "system", "content": system], ["role": "user", "content": user]],
        ]
        if !config.model.isEmpty { body["model"] = config.model }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw LocalAI.AIError("本地模型出错：\(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        var text = (((object?["choices"] as? [[String: Any]])?.first?["message"] as? [String: Any])?["content"] as? String) ?? ""
        if let range = text.range(of: "</think>") { text = String(text[range.upperBound...]) }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw LocalAI.AIError("本地模型返回了空内容") }
        return text
    }

    /// 用 zsh 在后台运行启动脚本（不弹窗口）
    private static func launch(_ script: String) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [script]
        process.currentDirectoryURL = URL(fileURLWithPath: script).deletingLastPathComponent()
        var env = ProcessInfo.processInfo.environment
        env["NO_PROXY"] = "127.0.0.1,localhost" // 本地服务别走代理
        process.environment = env
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process
    }
}

/// App 自己开的本地模型进程。只在主线程读写；App 退出（包括被 pkill 结束）时也要关掉它，不然会一直占着很多内存
@MainActor
final class LocalLLMProcess {
    static let shared = LocalLLMProcess()
    var process: Process?
    private var signalSource: DispatchSourceSignal?

    private init() {
        // build-app.sh 重新安装时会用 pkill 结束 App，那时 applicationWillTerminate 不会被调用，所以单独接住 SIGTERM
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { LocalLLMProcess.shared.stop() }
            exit(0)
        }
        source.resume()
        signalSource = source
    }

    func stop() {
        if let process, process.isRunning { process.terminate() }
        process = nil
    }
}
