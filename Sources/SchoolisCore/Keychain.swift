import Foundation
import Security

/// 从 macOS 钥匙串里读密码。
///
/// 为什么用钥匙串：钥匙串是系统加密保存的，代码里、日志里、硬盘上的普通文件里都不会出现明文密码。
/// 密码在「设置 → 校宝账号」里填，App 交给系统的 `security` 命令存进钥匙串。
///
/// 为什么通过系统自带的 `/usr/bin/security` 命令来读，而不是 App 自己直接读：
/// 这条钥匙串记录是 `security` 命令创建的，所以钥匙串一直信任它。
/// 如果 App 自己直接读，钥匙串认的是 App 的「签名」，而我们每次重新打包签名都会变，
/// 系统就会一遍遍地弹窗要开机密码、要点「始终允许」。
/// 这样做不会降低安全性：这条记录本来就允许 `security` 命令读取。
public enum Keychain {
    /// 钥匙串条目的「服务名」，存密码时 `-s` 后面填的就是它，两边必须一致。
    public static let service = "schoolis-helper"

    public static func password(account: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", account, "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice // 错误信息里可能带条目详情，不要
        do {
            try process.run()
        } catch {
            return try passwordDirectly(account: account) // 万一 security 命令不能用，退回老办法
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        switch process.terminationStatus {
        case 0:
            // 输出的最后有一个换行，去掉。密码本身不打印、不记日志。
            var text = String(decoding: data, as: UTF8.self)
            if text.hasSuffix("\n") { text.removeLast() }
            guard !text.isEmpty else { throw SchoolisError("钥匙串里的密码是空的，请重新存一次。") }
            return text
        case 44: // security 命令约定：44 = 找不到这一条
            throw SchoolisError("钥匙串里没找到密码（账号 \(account)）。请在「设置 → 校宝账号」里填一次密码。", retryable: false)
        default:
            return try passwordDirectly(account: account)
        }
    }

    /// 存密码（已有就覆盖）。交给系统的 `security` 命令来存，这样以后读的时候不会一遍遍弹窗；
    /// 密码从标准输入传过去（要输两遍），不写在命令行参数里——命令行参数本机别的程序看得见。
    public static func save(service: String = Keychain.service, account: String, secret: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["add-generic-password", "-U", "-s", service, "-a", account, "-w"]
        let input = Pipe()
        process.standardInput = input
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        input.fileHandleForWriting.write(Data("\(secret)\n\(secret)\n".utf8))
        try? input.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SchoolisError("存进钥匙串失败（代码 \(process.terminationStatus)）。", retryable: false)
        }
    }

    /// 删掉一条（找不到也不报错）
    public static func delete(service: String = Keychain.service, account: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["delete-generic-password", "-s", service, "-a", account]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }

    /// 老办法：App 自己直接读钥匙串（可能会弹窗要权限）。
    private static func passwordDirectly(account: String) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            throw SchoolisError("钥匙串里没找到密码（账号 \(account)）。请在「设置 → 校宝账号」里填一次密码。", retryable: false)
        }
        guard status == errSecSuccess,
              let data = item as? Data,
              let password = String(data: data, encoding: .utf8) else {
            let reason = SecCopyErrorMessageString(status, nil) as String? ?? "未知原因"
            throw SchoolisError("读取钥匙串失败（\(status)：\(reason)）。")
        }
        return password
    }
}
