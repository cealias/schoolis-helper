import SwiftUI
import SchoolisCore

/// 点开菜单栏图标后看到的小面板：只列还没交的，想看全的点「打开学习助手」。
struct PanelView: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let sections = Sections.build(.smart(.all), store.report)
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("学习助手").font(.headline)
                    Text(store.syncing ? "正在同步…" : store.updatedText)
                        .font(.caption)
                        .foregroundStyle(store.lastError == nil ? Color.secondary : Color.red)
                }
                Spacer()
                if let gpa = store.snapshot?.gpa {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("GPA").font(.caption2).foregroundStyle(.secondary)
                        Text(Format.number(gpa)).font(.title3.weight(.semibold)).monospacedDigit()
                    }
                }
                SyncButton(store: store)
                    .labelStyle(.iconOnly)
                    .buttonStyle(VitraPressStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            if sections.isEmpty {
                ContentUnavailableView(store.snapshot == nil ? "还没有数据" : "没有要交的作业",
                                       systemImage: store.snapshot == nil ? "tray" : "checkmark.circle")
                    .frame(height: 220)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections) { section in
                            Section {
                                ForEach(section.tasks) { task in
                                    TaskRow(store: store, task: task, kind: section.kind, compact: true)
                                        .padding(.horizontal, 14)
                                    Divider().padding(.leading, 46)
                                }
                            } header: {
                                Text("\(section.kind.title) · \(section.tasks.count)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.top, 10)
                                    .padding(.bottom, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.bar)
                            }
                        }
                    }
                }
                .frame(height: 440)
            }

            Divider()

            HStack(spacing: 14) {
                Button("打开学习助手") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                SettingsLink { Text("设置…") }
                Spacer()
                Button("退出") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(VitraPressStyle())
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .frame(width: 400)
        .onAppear { store.openWindowAction = { openWindow(id: "main") } }
    }
}
