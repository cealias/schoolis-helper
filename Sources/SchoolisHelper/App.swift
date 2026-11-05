import SwiftUI
import SchoolisCore

/// App 的入口。能在四个地方看到它：
/// 1. 主窗口：侧边栏 + 作业列表，可以拉大、全屏；
/// 2. 设置窗口：菜单「学习助手 → 设置…」或者 ⌘,；
/// 3. 屏幕顶部菜单栏的小图标，旁边的数字是「需要你马上处理」的件数，点开是一个小面板；
/// 4. Dock 里的图标。
@main
struct SchoolisHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("学习助手", id: "main") {
            MainView(store: appDelegate.store)
        }
        .defaultSize(width: 1100, height: 720)
        // 启动时先不开窗口，由 AppDelegate 决定：定时任务在后台启动时不弹窗口
        .defaultLaunchBehavior(.suppressed)
        // 也不让系统「恢复上次没关的窗口」，不然 App 被强行关掉后，后台启动时窗口还是会弹出来
        .restorationBehavior(.disabled)

        Settings {
            SettingsView(store: appDelegate.store)
        }

        MenuBarExtra {
            PanelView(store: appDelegate.store)
        } label: {
            MenuBarLabel(store: appDelegate.store)
        }
        // .window：点开后是一个可以滚动的小面板，而不是普通的下拉菜单
        .menuBarExtraStyle(.window)
    }
}

/// 菜单栏上的图标和数字。它一启动就存在，所以顺便把「打开主窗口」的动作交给 Store。
struct MenuBarLabel: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let count = store.report.urgentCount
        HStack(spacing: 3) {
            Image(systemName: store.lastError == nil ? "checklist" : "exclamationmark.triangle")
            if count > 0 { Text("\(count)") }
        }
        .onAppear { store.openWindowAction = { openWindow(id: "main") } }
    }
}

/// 管启动流程
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let store = Store()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 图标跟着深浅色自动换：交给系统了（Assets.car 里有浅色、深色两套，见 build-app.sh），App 不用管。

        _ = LocalLLMProcess.shared // 接住 SIGTERM，被 pkill 结束时也能关掉自己开的本地模型
        Notifier.shared.setUp()
        Notifier.shared.onClick = { [weak self] in self?.store.requestOpenWindow() }

        // 定时任务在后台启动 App 时会带上 --background，那时不弹窗口，只同步
        if !CommandLine.arguments.contains("--background") {
            store.requestOpenWindow()
        }
        // 调试用：--appearance dark / light 只让这个 App 用深色 / 浅色（截图检查界面用，不改系统设置）
        if let flag = CommandLine.arguments.firstIndex(of: "--appearance"), flag + 1 < CommandLine.arguments.count {
            NSApp.appearance = NSAppearance(named: CommandLine.arguments[flag + 1] == "dark" ? .darkAqua : .aqua)
        }
        // 调试用：open 学习助手.app --args --mode tasks（today / tasks / grades / schedule），直接打开某一页，方便截图检查界面
        if let flag = CommandLine.arguments.firstIndex(of: "--mode"), flag + 1 < CommandLine.arguments.count,
           let mode = AppMode(rawValue: CommandLine.arguments[flag + 1]) {
            store.mode = mode
        }
        store.start()
    }

    /// App 已经在运行时，再双击它 / 点 Dock 图标 / 从聚焦搜索打开 → 把窗口拿出来
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        store.requestOpenWindow()
        return false
    }

    /// 退出时把 App 自己开的本地模型也关掉
    func applicationWillTerminate(_ notification: Notification) {
        LocalLLMProcess.shared.stop()
    }

    /// 关掉窗口不退出：菜单栏图标和定时同步还要继续工作
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
