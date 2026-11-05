import AppKit
import SwiftUI
import SchoolisCore

/// 主窗口：照着「提醒事项」的样子——左边侧边栏，右边列表，同步按钮在窗口工具栏里。
/// 在 macOS 26 以后，侧边栏和工具栏会自动变成 Liquid Glass。
struct MainView: View {
    @ObservedObject var store: Store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 300, ideal: 310, max: 380)
        } detail: {
            // 切换时淡入淡出，看起来更顺
            ZStack {
                switch store.mode {
                case .today: TodayView(store: store).transition(.opacity)
                case .tasks: TaskListView(store: store, item: store.selection).transition(.opacity)
                case .grades: GradesDetailView(store: store).transition(.opacity)
                case .schedule: ScheduleDetailView(store: store).transition(.opacity)
                }
            }
            .animation(.snappy(duration: 0.25), value: store.mode)
        }
        .frame(minWidth: 780, minHeight: 520)
        // VITRA 画布：淡紫蓝底 + 慢慢飘的光球，两栏都透出来
        .background { VitraBackground() }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // 注册全局窗口光学空间，协同全屏一级卡片与二级卡片的光源
        .coordinateSpace(name: "VitraWindow")
        .onContinuousHover(coordinateSpace: .named("VitraWindow")) { phase in
            switch phase {
            case .active(let loc): VitraLightCenter.shared.update(windowPoint: loc)
            case .ended: VitraLightCenter.shared.update(windowPoint: nil)
            }
        }
        // 「弹窗」方式的提醒：一个标准的系统弹出面板
        .sheet(isPresented: Binding(
            get: { !store.alertMessages.isEmpty },
            set: { if !$0 { store.dismissAlerts() } })) {
            AlertSheet(store: store)
        }
        .onAppear {
            VitraLightCenter.shared.startMonitor()
            store.openWindowAction = { openWindow(id: "main") }
        }
    }
}

// MARK: - 侧边栏

/// 左栏：顶上切换「作业 / 成绩 / 课表」，下面是对应的内容。
/// 要求：字够大，而且所有内容不用滑动就能一屏看完。所以不用系统 List 的默认行高（太高），自己排得紧凑一点。
/// 窗口够高时把行放大（roomy），矮的时候收紧；窗口实在太矮时，外面的 ScrollView 兜底还能滚动。
struct SidebarView: View {
    @ObservedObject var store: Store

    var body: some View {
        GeometryReader { geo in
            let roomy = geo.size.height > 760
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ModeSwitcher(store: store)
                        .padding(.bottom, 12)

                    switch store.mode {
                    case .today: TodaySidebar(store: store)
                    case .tasks: TasksSidebar(store: store, roomy: roomy)
                    case .grades: GradesSidebar(store: store, roomy: roomy)
                    case .schedule: ScheduleSidebar(store: store)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
        }
    }
}

/// 左栏顶上的模式切换：整条串通一体的 VITRA 液态分段栏。
/// 四个 Tab 之间完全串通连贯，没有任何生硬的各自边缘；
/// 整条大圆角导航轨道的边缘流光与内部高光随着鼠标整体无缝流动。
struct ModeSwitcher: View {
    @ObservedObject var store: Store
    @Namespace private var selection
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(spacing: 0) {
            ForEach(AppMode.allCases, id: \.self) { mode in
                let selected = store.mode == mode
                Button {
                    store.switchMode(mode)
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: mode.icon).font(.system(size: 14, weight: .semibold))
                        Text(mode.title).font(.system(size: 11.5, weight: .bold))
                    }
                    .foregroundStyle(selected ? p.solidText : p.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        if selected {
                            Capsule()
                                .fill(p.solid)
                                .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                                .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.12), radius: 5, y: 2)
                                .matchedGeometryEffect(id: "selection", in: selection)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(VitraPressStyle())
                .help(mode.title)
            }
        }
        .padding(5)
        .vitraGlass(.widget, radius: 27)
    }
}

/// 作业模式的左栏：一排四个智能列表 → 一条 GPA → 科目（一行一个）→「其他」（两行两个）
struct TasksSidebar: View {
    @ObservedObject var store: Store
    let roomy: Bool

    var body: some View {
        let report = store.report
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                ForEach(SmartList.allCases, id: \.self) { list in
                    SmartTile(list: list,
                              count: Sections.count(.smart(list), report),
                              selected: store.selection == .smart(list)) {
                        store.selection = .smart(list)
                    }
                }
            }

            GPABar(store: store)
                .padding(.top, 8)

            if !store.subjects.isEmpty {
                GroupingPicker(store: store)
                VStack(spacing: 1) {
                    switch store.taskGrouping {
                    case .subject:
                        ForEach(store.subjects, id: \.self) { subject in
                            SubjectRow(name: subject,
                                       count: Sections.pendingCount(subject: subject, report),
                                       selected: store.selection == .subject(subject),
                                       roomy: roomy) {
                                store.selection = .subject(subject)
                            }
                        }
                    case .category:
                        ForEach(store.categories, id: \.self) { category in
                            SubjectRow(name: category.title,
                                       count: Sections.pendingCount(.category(category), report),
                                       selected: store.selection == .category(category),
                                       roomy: roomy,
                                       icon: category.icon,
                                       tint: category.tint) {
                                store.selection = .category(category)
                            }
                        }
                    }
                }
            }

            SidebarHeader(title: "其他")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
                ForEach(WaitingList.allCases, id: \.self) { list in
                    WaitingChip(list: list,
                                count: Sections.count(.waiting(list), report),
                                selected: store.selection == .waiting(list)) {
                        store.selection = .waiting(list)
                    }
                }
            }
        }
    }
}

/// 「科目 | 类型」切换：左栏按科目列，还是按作业类型列。
/// 切过去时，如果右边正开着某一科（或某一类），就换成新分法的第一项，让右边跟着变。
struct GroupingPicker: View {
    @ObservedObject var store: Store

    var body: some View {
        HStack {
            VitraSegmented(options: TaskGrouping.allCases.map { (title: $0.title, value: $0) },
                           selection: store.taskGrouping) { grouping in
                store.taskGrouping = grouping
                switch (grouping, store.selection) {
                case (.category, .subject):
                    if let first = store.categories.first { store.selection = .category(first) }
                case (.subject, .category):
                    if let first = store.subjects.first { store.selection = .subject(first) }
                default: break
                }
            }
            .help("左栏按科目列，还是按作业类型（测验、作业、项目……）列")
            Spacer()
        }
        .padding(.leading, 4)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }
}

/// 侧边栏里的小标题：「科目」「其他」
struct SidebarHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 6)
            .padding(.top, 16)
            .padding(.bottom, 4)
    }
}

/// 顶部一排四个的智能列表方块：一块小玻璃，左上图标舱、右上数字、下面名字。选中时整块变成有颜色的玻璃。
struct SmartTile: View {
    let list: SmartList
    let count: Int
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 2) {
                    VitraPod(icon: list.icon,
                             fill: selected ? LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.18)],
                                                             startPoint: .top, endPoint: .bottom) : Vitra.gradient(list.tint),
                             size: 22)
                    Spacer(minLength: 2)
                    Text("\(count)")
                        .font(.system(size: 19, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(selected ? Color.white : p.display)
                }
                Text(list.title)
                    .font(.system(size: 12.5, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundStyle(selected ? Color.white.opacity(0.92) : p.secondary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .vitraGlass(selected ? .tinted(Vitra.gradient(list.tint),
                                           glow: LinearGradient(colors: [list.tint.opacity(0.55), list.tint.opacity(0.4)],
                                                                startPoint: .leading, endPoint: .trailing))
                                 : .widget, radius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(VitraPressStyle())
    }
}

/// 一条细横条：GPA + 数据更新时间（玻璃胶囊，左边等宽小标签）
struct GPABar: View {
    @ObservedObject var store: Store
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VitraCaption("GPA")
            Text(store.snapshot?.gpa.map(Format.number) ?? "–")
                .font(.system(size: 21, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(p.display)
            Spacer(minLength: 4)
            Text(store.syncing ? "正在同步…" : store.updatedText)
                .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(store.lastError == nil ? p.muted : Color.red)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .vitraGlass(.widget, radius: 16)
    }
}

/// 科目一行：彩色圆点 + 科目名 + 还没交的件数。
/// 按类型列的时候也用它：圆点换成一个带颜色的小图标（像「提醒事项」的列表图标）。
struct SubjectRow: View {
    let name: String
    let count: Int
    let selected: Bool
    var roomy = false
    var icon: String? = nil
    var tint: Color? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        Button(action: action) {
            HStack(spacing: 10) {
                if let icon {
                    ZStack {
                        Circle().fill(tint ?? .accentColor)
                        Image(systemName: icon)
                            .font(.system(size: 10.5, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: 22, height: 22)
                } else {
                    Circle()
                        .fill(SubjectColor.of(name))
                        .frame(width: 10, height: 10)
                }
                Text(name)
                    .font(.system(size: roomy ? 16 : 15, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? p.display : p.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 6)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: roomy ? 14 : 13, weight: .semibold, design: .monospaced))
                        .monospacedDigit()
                        .foregroundStyle(selected ? p.display : p.muted)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(selected ? p.solid.opacity(0.35) : Color.primary.opacity(0.06)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, roomy ? 8 : 6)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(p.widget)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11, style: .continuous)
                                .strokeBorder(LinearGradient(colors: [p.borderTop, p.borderRB], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                        )
                        .shadow(color: p.shadow, radius: 4, y: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(VitraPressStyle())
        .help(count > 0 ? "\(name)：还有 \(count) 项要处理" : name)
    }
}

/// 「其他」里的小方块：图标 + 名字 + 件数
struct WaitingChip: View {
    let list: WaitingList
    let count: Int
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: list.icon)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(selected ? p.display : p.secondary)
                    .frame(width: 16)
                Text(list.title)
                    .font(.system(size: 13, weight: selected ? .bold : .regular))
                    .foregroundStyle(selected ? p.display : p.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 2)
                Text("\(count)")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(selected ? p.display : p.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .vitraGlass(selected ? .widget : .widget, radius: 12)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(VitraPressStyle())
    }
}

// MARK: - 右边的作业列表

struct TaskListView: View {
    @ObservedObject var store: Store
    let item: SidebarItem
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        let sections = Sections.build(item, store.report)
        let total = sections.reduce(0) { $0 + $1.tasks.count }
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if store.snapshot == nil {
                    VStack(spacing: 12) {
                        Image(systemName: store.syncing ? "arrow.triangle.2.circlepath" : "tray")
                            .font(.system(size: 38))
                            .foregroundStyle(p.muted)
                        Text(store.syncing ? "正在同步…" : "还没有数据")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(p.display)
                        Text(store.syncing ? "第一次同步大约要 10 秒。" : "点工具栏右边的同步按钮拉一次数据。")
                            .font(.system(size: 13))
                            .foregroundStyle(p.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .vitraGlass(.board, radius: 24)
                } else if sections.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 38))
                            .foregroundStyle(Color.green)
                        Text(emptyTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(p.display)
                        Text("「\(item.title)」里现在没有作业。")
                            .font(.system(size: 13))
                            .foregroundStyle(p.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .vitraGlass(.board, radius: 24)
                } else {
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                VitraPod(icon: section.kind.icon, fill: Vitra.gradient(section.kind.tint), size: 28)
                                VStack(alignment: .leading, spacing: 1) {
                                    VitraCaption(section.kind.caption)
                                    Text(section.kind.title)
                                        .font(.system(size: 15, weight: .heavy))
                                        .foregroundStyle(p.display)
                                }
                                VitraCode("\(section.tasks.count)", tint: section.kind.tint)
                                Spacer()
                            }

                            VStack(spacing: 0) {
                                ForEach(Array(section.tasks.enumerated()), id: \.element.id) { index, task in
                                    if index > 0 {
                                        Divider()
                                            .opacity(0.3)
                                            .padding(.leading, 38)
                                    }
                                    TaskRow(store: store, task: task, kind: section.kind)
                                        .padding(.horizontal, 4)
                                }
                            }

                            if let footer = section.kind.footer {
                                Text(footer)
                                    .font(.system(size: 12))
                                    .foregroundStyle(p.muted)
                                    .padding(.top, 4)
                                    .padding(.leading, 4)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(18)
                        .vitraGlass(.board, radius: 24)
                    }
                }
            }
            .padding(20)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            StatusBanner(store: store)
        }
        .navigationTitle(item.title)
        .navigationSubtitle(store.snapshot == nil ? "" : subtitle(sections, total: total))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    store.openSchoolWebsite()
                } label: {
                    Label("校宝网页", systemImage: "safari")
                }
                .help("在浏览器里打开校宝")
                .buttonStyle(VitraRoundStyle())
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .primaryAction) {
                SyncButton(store: store).buttonStyle(VitraRoundStyle())
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }

    /// 科目页写成「2 项待处理 · 共 17 项」，免得把 2 看成这科只有 2 个作业
    private func subtitle(_ sections: [TaskSectionModel], total: Int) -> String {
        switch item {
        case .subject, .category: break
        default: return "\(total) 项"
        }
        let pending = sections.filter { Sections.pendingKinds.contains($0.kind) }.reduce(0) { $0 + $1.tasks.count }
        return "\(pending) 项待处理 · 共 \(total) 项"
    }

    private var emptyTitle: String {
        switch item {
        case .smart(.rescue): return "没有需要补救的"
        case .smart(.soon): return "今明两天没有要交的"
        case .waiting: return "这里是空的"
        default: return "没有要交的作业"
        }
    }
}

// MARK: - 弹窗提醒

struct AlertSheet: View {
    @ObservedObject var store: Store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 34))
                .foregroundStyle(.orange)
            ForEach(store.alertMessages) { message in
                VStack(spacing: 6) {
                    Text(message.title).font(.headline)
                    Text(message.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button("知道了") { store.dismissAlerts() }
                .buttonStyle(VitraPrimaryStyle())
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
        }
        .padding(28)
        .frame(width: 440)
    }
}
