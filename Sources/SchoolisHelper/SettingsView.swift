import AppKit
import SwiftUI
import SchoolisCore

/// 设置窗口：按 macOS 的习惯，单独一个窗口，菜单「学习助手 → 设置…」或者按 ⌘, 打开。
struct SettingsView: View {
    @ObservedObject var store: Store

    var body: some View {
        Form {
            Section {
                TextField("学校的校宝网址", text: Binding(
                    get: { store.settings.schoolURL },
                    set: { value in store.updateSettings { $0.schoolURL = value } }),
                          prompt: Text("https://你的学校.schoolis.cn"))
                TextField("账号", text: Binding(
                    get: { store.settings.schoolAccount },
                    set: { value in store.updateSettings { $0.schoolAccount = value } }))
                    .onSubmit { store.refreshSchoolPasswordState() }
                LabeledContent("密码") {
                    HStack {
                        SecureField(store.hasSchoolPassword ? "已保存，想换就重新填" : "填好后点保存",
                                    text: Binding(get: { store.schoolPasswordDraft },
                                                  set: { store.schoolPasswordDraft = $0 }))
                            .frame(width: 200)
                        Button("保存") {
                            if store.saveSchoolPassword(store.schoolPasswordDraft) == nil { store.schoolPasswordDraft = "" }
                        }
                        .disabled(store.schoolPasswordDraft.isEmpty || store.settings.schoolAccount.isEmpty)
                    }
                }
                TextField("首页怎么称呼你", text: Binding(
                    get: { store.settings.nickname },
                    set: { value in store.updateSettings { $0.nickname = value } }),
                          prompt: Text("比如：小明（空着就叫「同学」）"))
            } header: {
                Text("校宝账号")
            } footer: {
                Text("只读：只看作业、成绩、课表、考勤，不会提交或修改任何东西。密码存在 macOS 钥匙串里，不写进任何文件。密码错了或者要验证码时会立刻停下，不自动重试。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Toggle("每天自动同步", isOn: Binding(
                    get: { store.settings.autoSync },
                    set: { value in store.updateSettings { $0.autoSync = value } }))

                if store.settings.autoSync {
                    ForEach(Array(store.settings.syncTimes.enumerated()), id: \.offset) { index, time in
                        HStack {
                            DatePicker("第 \(index + 1) 次", selection: Binding(
                                get: { time.date },
                                set: { date in
                                    store.updateSettings { settings in
                                        if index < settings.syncTimes.count {
                                            settings.syncTimes[index] = HourMinute(date: date)
                                        }
                                    }
                                }), displayedComponents: .hourAndMinute)
                            Button {
                                store.updateSettings { settings in
                                    if index < settings.syncTimes.count { settings.syncTimes.remove(at: index) }
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(VitraPressStyle())
                            .disabled(store.settings.syncTimes.count <= 1)
                            .help("删掉这个时间")
                        }
                    }
                    Button("添加一个时间") {
                        store.updateSettings { $0.syncTimes.append(HourMinute(hour: 12, minute: 0)) }
                    }
                    .disabled(store.settings.syncTimes.count >= 6)
                }
            } header: {
                Text("自动同步")
            } footer: {
                Text(store.scheduleStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Picker("紧急提醒", selection: Binding(
                    get: { store.settings.urgentStyle },
                    set: { value in store.updateSettings { $0.urgentStyle = value } })) {
                    ForEach(AlertStyle.allCases) { Text($0.label).tag($0) }
                }
                Picker("同步后的汇总", selection: Binding(
                    get: { store.settings.summaryStyle },
                    set: { value in store.updateSettings { $0.summaryStyle = value } })) {
                    ForEach(AlertStyle.allCases) { Text($0.label).tag($0) }
                }
                HStack {
                    Button("试一下紧急提醒") { store.testAlert(urgent: true) }
                    Button("试一下汇总") { store.testAlert(urgent: false) }
                }
            } header: {
                Text("提醒方式")
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    Text("紧急提醒：今明两天截止的作业、新出现的作业。汇总：每次自动同步后发一条。")
                    Text("系统通知：\(store.notificationStatus)")
                    Text("横幅（几秒后消失）还是提醒（一直停着），只能在系统设置里改。")
                    Button("打开系统通知设置") { Notifier.openSystemSettings() }
                        .buttonStyle(VitraLinkStyle())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("优先用", selection: Binding(
                    get: { store.settings.aiProvider },
                    set: { value in store.updateSettings { $0.aiProvider = value } })) {
                    ForEach(AIProvider.allCases) { Text($0.title).tag($0) }
                }
                if store.settings.aiProvider.isAgy {
                    LabeledContent("状态") {
                        HStack(spacing: 6) {
                            Image(systemName: AgyAI.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundStyle(AgyAI.isAvailable ? .green : .orange)
                            Text(AgyAI.isAvailable ? "已就绪 · 免 Key 直连 Gemini 3.8 Flash（最稳定神速）" : "未找到 agy 命令行，请在终端运行 agy")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                if store.settings.aiProvider.isCloud {
                    LabeledContent("API Key") {
                        if let hint = store.apiKeyHint {
                            HStack {
                                Text(hint).foregroundStyle(.secondary)
                                Button("删除") { store.deleteAPIKey() }
                            }
                        } else {
                            HStack {
                                SecureField("粘贴到这里", text: Binding(get: { store.apiKeyDraft },
                                                                     set: { store.apiKeyDraft = $0 }))
                                    .frame(width: 220)
                                Button("保存") { store.saveAPIKey() }
                                    .disabled(store.apiKeyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                    }
                    Picker("思考程度", selection: Binding(
                        get: { store.settings.aiThinking },
                        set: { value in store.updateSettings { $0.aiThinking = value } })) {
                        ForEach(ThinkingLevel.allCases) { Text($0.title).tag($0) }
                    }
                    if store.settings.aiProvider == .gemini {
                        Picker("模型", selection: Binding(
                            get: { store.settings.geminiModel },
                            set: { value in store.updateSettings { $0.geminiModel = value } })) {
                            Text("Gemini 3.8 Flash（免费层）").tag("gemini-3.8-flash")
                            Text("Gemini 3.5 Flash-Lite（免费层，更快、额度更多）").tag("gemini-3.5-flash-lite")
                        }
                    } else {
                        Picker("模型", selection: Binding(
                            get: { store.settings.zhipuModel },
                            set: { value in store.updateSettings { $0.zhipuModel = value } })) {
                            Text("GLM-4.7-Flash（免费）").tag("glm-4.7-flash")
                            Text("GLM-5.3-Flash（更聪明，要付费，约 0.6 元/月）").tag("glm-5.3-flash")
                        }
                    }
                }
                HStack {
                    Button("现在重新写一份总结") { Task { await store.generateSummary() } }
                        .disabled(store.aiBusy || store.snapshot == nil)
                    if store.aiBusy { ProgressView().controlSize(.small) }
                    if let status = store.aiStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            } header: {
                Text("AI")
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("顺序：Antigravity（本机装了 agy 命令行就用，免 Key）→ 你选的云端 AI → 另一家填了 Key 的 → 本地模型兜底。API Key 存在钥匙串里。")
                    Text("思考程度：越高越聪明、越慢。智谱只有开 / 关两档，选「低」就是关掉思考。")
                    Text("Gemini：中国大陆要走代理。装了 Clash Verge 会自动走它（没开会在后台打开）；没装就直连或走系统代理。")
                    Text("用云端 AI 时，作业名、分数、课表会发给对应的公司用来写总结；用第三方云端模型要遵守对应平台的服务条款（包括年龄要求），未成年人请在监护人指导下使用，或者选「本地模型」。")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                TextField("地址", text: Binding(
                    get: { store.settings.localAIURL },
                    set: { value in store.updateSettings { $0.localAIURL = value } }),
                          prompt: Text("http://127.0.0.1:8080/v1"))
                TextField("模型名", text: Binding(
                    get: { store.settings.localAIModel },
                    set: { value in store.updateSettings { $0.localAIModel = value } }),
                          prompt: Text("空着就用服务器默认的"))
                TextField("启动脚本（可选）", text: Binding(
                    get: { store.settings.localAILaunchScript },
                    set: { value in store.updateSettings { $0.localAILaunchScript = value } }),
                          prompt: Text("~/models/start-server.sh"))
            } header: {
                Text("本地模型（离线兜底）")
            } footer: {
                Text("任意 OpenAI 兼容接口都行：llama.cpp 的 llama-server、Ollama（http://127.0.0.1:11434/v1）、LM Studio 等。服务没开时，如果填了启动脚本，App 会在后台运行它，写完总结再关掉。在上面选「本地模型」时，数据不会离开这台电脑。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                LabeledContent("数据存放位置") {
                    Button("在访达中显示") {
                        NSWorkspace.shared.activateFileViewerSelecting([AppFiles.directory])
                    }
                }
            } header: {
                Text("其他")
            } footer: {
                Text("关掉「每天自动同步」会同时删除定时任务。完整的卸载方法写在项目的 README 里。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background { VitraBackground() }
        .buttonStyle(VitraSoftStyle())
        .frame(width: 540)
        .frame(minHeight: 580)
        .task {
            store.refreshSchoolPasswordState()
            await store.refreshNotificationStatus()
        }
    }
}
