import Foundation

/// 通过本机安装的 Google Antigravity 官方命令行（agy），直接调用 Gemini 3.8 Flash。
/// 优点：
/// 1. 使用用户已登录的 Google AI 账号，不需要申请 API Key；
/// 2. 自带网络连接机制，不卡顿、不需要配置 Clash Verge 节点；
/// 3. 原生支持 gemini-3.8-flash，速度极快（通常 5～12 秒完成）。
enum AgyAI {
    struct AgyResponse: Codable {
        let conversation_id: String?
        let status: String?
        let response: String?
        let duration_seconds: Double?
        let error: String?
    }

    /// 检测本机 agy 命令行工具的安装路径
    static var binaryPath: String? {
        if let envBin = ProcessInfo.processInfo.environment["AGY_BIN"],
           FileManager.default.isExecutableFile(atPath: envBin) {
            return envBin
        }
        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/usr/bin/agy"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// 本机是否可用 agy
    static var isAvailable: Bool {
        binaryPath != nil
    }

    /// 运行 agy 的干净工作区（避免扫描用户项目目录导致 token 膨胀和耗时增加）
    private static var workspaceURL: URL {
        let home = NSHomeDirectory()
        let dir = URL(fileURLWithPath: "\(home)/.cache/gemini-agy/workspace")
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// 调用 Gemini 生成内容
    /// - Parameters:
    ///   - model: 模型名，默认 gemini-3.8-flash
    ///   - system: 系统提示词
    ///   - user: 用户输入数据
    ///   - timeout: 超时时间（秒）
    static func chat(model: String = "gemini-3.8-flash",
                     system: String,
                     user: String,
                     timeout: TimeInterval = 120) async throws -> String {
        guard let agy = binaryPath else {
            throw LocalAI.AIError("本机未找到 Antigravity 命令行 agy（~/.local/bin/agy）")
        }

        let prompt = """
        \(system)

        ---
        【今日学生的真实数据 JSON】
        \(user)
        """

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: agy)
                // 不开「跳过所有权限」：作业名、科目这些是从学校系统读来的外部文字，万一里面藏了指令，
                // agy 也没权限动你的电脑（--sandbox 限制命令，没有输入所以任何权限请求都会直接失败）
                process.arguments = [
                    "--sandbox",
                    "--disable-slash-commands",
                    "--output-format", "json",
                    "--model", model,
                    "-p", prompt
                ]
                process.currentDirectoryURL = workspaceURL

                // 注入环境，保证 PATH 包含 ~/.local/bin，禁用控制台修饰符
                var env = ProcessInfo.processInfo.environment
                let home = NSHomeDirectory()
                let existingPath = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
                env["PATH"] = "\(home)/.local/bin:/opt/homebrew/bin:/usr/local/bin:" + existingPath
                env["NO_COLOR"] = "1"
                // agy 不认 Mac 的系统代理：从程序坞 / 定时任务启动的 App 没有 HTTPS_PROXY，
                // agy 就直连 Google，连不上还会误报「登录过期」。所以明确告诉它走 Clash
                let port = ClashProxy.port()
                if ClashProxy.isListening(port) {
                    for key in ["HTTPS_PROXY", "HTTP_PROXY", "https_proxy", "http_proxy"] {
                        env[key] = "http://127.0.0.1:\(port)"
                    }
                    env["NO_PROXY"] = "localhost,127.0.0.1,::1,.local"
                }
                env["AGY_CLI_OSC7501"] = "off"
                process.environment = env

                let outPipe = Pipe()
                let errPipe = Pipe()
                process.standardOutput = outPipe
                process.standardError = errPipe
                // 没有输入：登录过期时 agy 会等人粘贴验证码，给它空输入让它马上失败
                process.standardInput = FileHandle.nullDevice

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: LocalAI.AIError("启动 agy 进程失败：\(error.localizedDescription)"))
                    return
                }

                // 超时保护：先礼貌地结束，3 秒后还没结束就强制结束
                let timeoutWork = DispatchWorkItem {
                    guard process.isRunning else { return }
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                    }
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWork)

                // 两路输出同时读：一路一路读的话，报错输出太多会把管道塞满，两边互相等，永远卡住
                var errData = Data()
                let errDone = DispatchSemaphore(value: 0)
                DispatchQueue.global().async {
                    errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                    errDone.signal()
                }
                let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                _ = errDone.wait(timeout: .now() + 5)
                timeoutWork.cancel()

                if process.terminationStatus != 0 {
                    let errStr = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    let outStr = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    let msg = errStr.isEmpty ? outStr : errStr
                    if msg.lowercased().contains("authentication") || msg.lowercased().contains("login") {
                        continuation.resume(throwing: LocalAI.AIError("Antigravity 登录过期了，在终端里运行一次 agy 重新登录"))
                    } else {
                        continuation.resume(throwing: LocalAI.AIError("agy 出错：\(msg.prefix(120))"))
                    }
                    return
                }

                // 解析 stdout JSON 信封
                guard let decoded = try? JSONDecoder().decode(AgyResponse.self, from: outData),
                      let text = decoded.response?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else {
                    // 如果无法按信封解析，尝试直接读取纯文本
                    let raw = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !raw.isEmpty {
                        continuation.resume(returning: raw)
                    } else {
                        continuation.resume(throwing: LocalAI.AIError("agy 返回了空内容"))
                    }
                    return
                }

                if decoded.status != "SUCCESS" && decoded.status != nil {
                    let errMsg = decoded.error ?? "未成功的状态：\(decoded.status ?? "未知")"
                    continuation.resume(throwing: LocalAI.AIError("agy 返回异常：\(errMsg)"))
                    return
                }

                continuation.resume(returning: text)
            }
        }
    }
}
