import AppKit
import SwiftUI

// VITRA 视觉系统：用户自己和 Gemini 一起做的网页版设计（设计/vitra_ui_v2.6.html），搬到 SwiftUI。
//
// 画面是一层一层的：
// 1. 画布：淡紫蓝的底色，后面慢慢飘着几团模糊的彩色光（用户说几何形状难看，只要光）；
// 2. 玻璃：每块玻璃都由「彩色投影（焦散）+ 磨砂主体 + 上亮下暗的不对称边框 + 1px 内倒角 + 跟着鼠标走的高光」组成；
// 3. 内容：字永远在最上面，清楚锐利。
// 颜色、边框、倒角、高光的数值都照 CSS 里的变量抄，白昼 / 暗夜两套跟着系统外观走。
// 网页版的「果冻」：每个能按的按钮都是 Q 弹的——按下缩一下、松手弹回来；按住往外拖会被拉长一点，松手弹回原位。
// 「水晶和弦音效」没搬：每天用会吵。

enum Vitra {
    /// 一套配色（CSS 里 :root 和 [data-theme="night"] 的变量）
    struct Palette {
        let canvas: Color
        let display: Color
        let primary: Color
        let secondary: Color
        let muted: Color
        /// 大面板的玻璃底色（--board-bg）
        let board: Color
        /// 小组件的玻璃底色（--widget-white-bg）
        let widget: Color
        let borderTop: Color
        let borderLeft: Color
        let borderRB: Color
        let bevelTop: Color
        let bevelLeft: Color
        let bevelCyan: Color
        let glareSpot: Color
        let glareWash: Color
        let codeBG: Color
        let codeText: Color
        /// 实体陶瓷按钮
        let solid: Color
        let solidText: Color
        /// 字的「蚀刻」阴影
        let etch: Color
        let etchRadius: CGFloat
        /// 中性投影
        let shadow: Color
        let orbOpacity: Double
    }

    static func palette(_ scheme: ColorScheme) -> Palette { scheme == .dark ? night : day }

    static let day = Palette(
        canvas: rgb(0xEEF3FA), display: rgb(0x0B101E), primary: rgb(0x141B2D), secondary: rgb(0x37435C), muted: rgb(0x5B6882),
        board: .white.opacity(0.48), widget: .white.opacity(0.62),
        borderTop: .white.opacity(0.96), borderLeft: .white.opacity(0.68), borderRB: .white.opacity(0.18),
        bevelTop: .white.opacity(0.78), bevelLeft: .white.opacity(0.46), bevelCyan: rgb(0x96E6FF).opacity(0.22),
        glareSpot: .white.opacity(0.32), glareWash: .white.opacity(0.50),
        codeBG: rgb(0x0F172A).opacity(0.07), codeText: rgb(0x4F39D6),
        solid: .white, solidText: rgb(0x0F1523),
        etch: .white.opacity(0.85), etchRadius: 0,
        shadow: rgb(0x0A0E1A).opacity(0.12), orbOpacity: 1)

    static let night = Palette(
        canvas: rgb(0x0A0D16), display: .white, primary: rgb(0xF1F5FB), secondary: rgb(0xC5D0E6), muted: rgb(0x8E9BB5),
        board: rgb(0x14192A).opacity(0.52), widget: .white.opacity(0.11),
        borderTop: .white.opacity(0.24), borderLeft: .white.opacity(0.16), borderRB: .white.opacity(0.06),
        bevelTop: .white.opacity(0.22), bevelLeft: .white.opacity(0.14), bevelCyan: rgb(0x82D2F5).opacity(0.10),
        glareSpot: rgb(0xDCE8FF).opacity(0.11), glareWash: rgb(0xDCE8FF).opacity(0.14),
        codeBG: .white.opacity(0.11), codeText: rgb(0xB8A4FF),
        solid: rgb(0xF8FAFC), solidText: rgb(0x0B0F1A),
        etch: .black.opacity(0.65), etchRadius: 1.5,
        shadow: .black.opacity(0.45), orbOpacity: 0.72)

    // 主色：紫（Primary 按钮）、青（Secondary 按钮），渐变从上到下
    static let violet = LinearGradient(colors: [rgb(0x926EFC).opacity(0.90), rgb(0x704AF6).opacity(0.96)],
                                       startPoint: .top, endPoint: .bottom)
    static let violetGlow = LinearGradient(colors: [rgb(0x804AFF).opacity(0.62), rgb(0xA878FF).opacity(0.54)],
                                           startPoint: .leading, endPoint: .trailing)
    static let teal = LinearGradient(colors: [rgb(0x40CEC0).opacity(0.90), rgb(0x20AEA4).opacity(0.96)],
                                     startPoint: .top, endPoint: .bottom)
    static let tealGlow = LinearGradient(colors: [rgb(0x2EBEB4).opacity(0.58), rgb(0x64E6D7).opacity(0.48)],
                                         startPoint: .leading, endPoint: .trailing)

    /// 任意颜色的「光学胶囊」渐变（图标舱、状态点用）
    static func gradient(_ color: Color) -> LinearGradient {
        LinearGradient(colors: [color.opacity(0.78), color], startPoint: .top, endPoint: .bottom)
    }

    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - 字

extension View {
    /// 大标题：特粗、字距收紧，带一点「蚀刻」阴影（CSS 的 .vitra-h1）
    func vitraDisplay(_ size: CGFloat, _ palette: Vitra.Palette) -> some View {
        font(.system(size: size, weight: .heavy))
            .tracking(-size * 0.03)
            .foregroundStyle(palette.display)
            .shadow(color: palette.etch, radius: palette.etchRadius, y: 1)
    }
}

/// 等宽、全大写、字距拉开的小标签（CSS 的 .vitra-caption），比如「AI SUMMARY」
struct VitraCaption: View {
    let text: String
    var color: Color? = nil
    @Environment(\.colorScheme) private var scheme

    init(_ text: String, color: Color? = nil) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .tracking(0.9)
            .foregroundStyle(color ?? Vitra.palette(scheme).muted)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }
}

/// 等宽小胶囊（CSS 的 .vitra-code），比如模型名、数字标签
struct VitraCode: View {
    let text: String
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme

    init(_ text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        let p = Vitra.palette(scheme)
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(tint ?? p.codeText)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.map { $0.opacity(0.13) } ?? p.codeBG))
    }
}

/// 圆形图标舱：渐变底 + 白色图标 + 顶部一圈高光（CSS 的 .btn-icon-pod）
struct VitraPod: View {
    let icon: String
    var fill: LinearGradient = Vitra.violet
    var size: CGFloat = 32

    var body: some View {
        ZStack {
            Circle().fill(fill)
            Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.05)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.18), radius: 1, y: 1)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.12), radius: 3, y: 2)
    }
}

// MARK: - 背景：画布 + 慢慢飘的光球

struct VitraBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let p = Vitra.palette(scheme)
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height, unit = max(w, h)
            ZStack {
                p.canvas
                if reduceMotion {
                    scene(w: w, h: h, unit: unit, drift: 0)
                } else {
                    // 两个状态之间来回慢慢飘（18 秒一趟），跟网页版的 floatOrb 一样
                    PhaseAnimator([0.0, 1.0]) { drift in
                        scene(w: w, h: h, unit: unit, drift: drift)
                    } animation: { _ in .easeInOut(duration: 18) }
                }
            }
            .opacity(1)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func scene(w: CGFloat, h: CGFloat, unit: CGFloat, drift: Double) -> some View {
        let p = Vitra.palette(scheme)
        let d = CGFloat(drift)
        return ZStack {
            orb(size: unit * 0.62, stops: [(Vitra.rgb(0x9870FF), 0.40), (Vitra.rgb(0x5AC8FF), 0.16)])
                .position(x: w * 0.18 + 60 * d, y: h * 0.12 + 30 * d)
            orb(size: unit * 0.68, stops: [(Vitra.rgb(0xFF91CD), 0.36), (Vitra.rgb(0x55EEE4), 0.26)])
                .position(x: w * 0.86 - 50 * d, y: h * 0.92 - 40 * d)
            orb(size: unit * 0.5, stops: [(Vitra.rgb(0xFFC373), 0.28), (Vitra.rgb(0xA078FF), 0.24)])
                .position(x: w * 0.52 + 40 * (1 - d), y: h * 0.48 - 30 * d)
            orb(size: unit * 0.46, stops: [(Vitra.rgb(0x7FB4FF), 0.24), (Vitra.rgb(0xC9A2FF), 0.14)])
                .position(x: w * 0.82 - 30 * d, y: h * 0.18 + 40 * d)
        }
        .opacity(p.orbOpacity)
    }

    /// 一团光：中心颜色 → 外圈颜色 → 透明
    private func orb(size: CGFloat, stops: [(Color, Double)]) -> some View {
        Circle()
            .fill(RadialGradient(stops: [
                .init(color: stops[0].0.opacity(stops[0].1), location: 0),
                .init(color: stops[1].0.opacity(stops[1].1), location: 0.38),
                .init(color: stops[1].0.opacity(0), location: 0.70),
            ], center: .center, startRadius: 0, endRadius: size * 0.7))
            .frame(width: size, height: size)
    }
}

// MARK: - 玻璃

/// 玻璃的种类
enum VitraGlassKind {
    /// 大面板（CSS 的 .layer-1-board）：底色更透、阴影更大
    case board
    /// 小组件（CSS 的 .widget-white）
    case widget
    /// 有颜色的玻璃：紫色、青色按钮那种，带彩色投影
    case tinted(LinearGradient, glow: LinearGradient)
}

// MARK: - 统一物理光源引擎（Unified Vitra Light Engine）

/// 窗口级统一物理光源中心：监听全局鼠标移动，为所有一级大卡片、二级卡片和小按钮提供统一的光学坐标与物理漫射
@MainActor
final class VitraLightCenter: ObservableObject {
    static let shared = VitraLightCenter()

    /// 鼠标在当前窗口中的坐标（原点在窗口内容区左上角，y 向下）
    @Published var windowPoint: CGPoint? = nil

    private var monitor: Any?

    private init() {
        startMonitor()
    }

    func startMonitor() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self = self, let window = event.window else { return }
                let loc = event.locationInWindow
                let contentH = window.contentView?.frame.height ?? window.frame.height
                let pt = CGPoint(x: loc.x, y: contentH - loc.y)
                if self.windowPoint != pt {
                    self.windowPoint = pt
                }
            }
            return event
        }
    }

    func update(windowPoint pt: CGPoint?) {
        if self.windowPoint != pt {
            self.windowPoint = pt
        }
    }
}

/// 计算出的光学投射参数
private struct VitraLightParams {
    let intensity: Double
    let spotCenter: CGPoint
    let spotRadius: CGFloat
    let isSmall: Bool
    let isBoard: Bool
}

/// 独立的玻璃背景层，仅在鼠标移动时局部重绘光斑，不引起外层业务视图重新布局
private struct VitraGlassBackground: View {
    let kind: VitraGlassKind
    let radius: CGFloat
    let followMouse: Bool
    let shape: RoundedRectangle
    let palette: Vitra.Palette
    let scheme: ColorScheme
    let localHoverPoint: CGPoint?
    @ObservedObject private var lightCenter = VitraLightCenter.shared

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let frameInWindow = geo.frame(in: .global)
            let light = calculateLight(size: size, frameInWindow: frameInWindow)

            ZStack {
                // 1. 投影：有颜色的玻璃投彩色的光（焦散），白玻璃投淡淡的中性阴影
                switch kind {
                case .tinted(_, let glow):
                    shape.fill(glow)
                        .padding(.horizontal, 10)
                        .offset(y: 10)
                        .blur(radius: 12)
                        .opacity(scheme == .dark ? 0.55 : 0.75)
                case .board:
                    shape.fill(palette.shadow).offset(y: 18).blur(radius: 28).opacity(0.9)
                case .widget:
                    shape.fill(palette.shadow).offset(y: 6).blur(radius: 12).opacity(0.7)
                }

                // 2. 磨砂主体
                shape.fill(.ultraThinMaterial)
                switch kind {
                case .board: shape.fill(palette.board)
                case .widget: shape.fill(palette.widget)
                case .tinted(let fill, _): shape.fill(fill)
                }

                // 3. 漫射底光：一道斜着的微弱洗墙底光
                shape.fill(LinearGradient(stops: [
                    .init(color: palette.glareWash.opacity(0.48), location: 0),
                    .init(color: .white.opacity(0.025), location: 0.28),
                    .init(color: .clear, location: 0.40),
                ], startPoint: .topLeading, endPoint: .bottomTrailing))
                .opacity(kindIsTinted ? 0.45 : 0.85)

                // 4. 基础静态边框与内倒角（柔和微光底，未受光时依然晶莹通透）
                shape.strokeBorder(
                    LinearGradient(
                        colors: [palette.borderTop.opacity(0.36), palette.borderLeft.opacity(0.24), palette.borderRB, palette.borderRB],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
                shape.strokeBorder(
                    LinearGradient(
                        colors: [palette.bevelTop.opacity(0.32), palette.bevelLeft.opacity(0.18), .clear, palette.bevelCyan.opacity(0.20)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
                .padding(1)
                .blur(radius: 0.5)
                .clipShape(shape)

                // 5. ✨【核心突破：统一物理点光源与多尺度自适应折射】
                if followMouse && light.intensity > 0.01 {
                    // (A) 内部跟随漫反射光斑（大中型卡片开启，小按钮不开启，避免小按钮泛白）
                    if !light.isSmall {
                        Circle()
                            .fill(RadialGradient(
                                stops: [
                                    .init(color: palette.glareSpot.opacity((scheme == .dark ? 0.26 : 0.32) * light.intensity), location: 0),
                                    .init(color: palette.glareSpot.opacity((scheme == .dark ? 0.08 : 0.12) * light.intensity), location: 0.46),
                                    .init(color: .clear, location: 1.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: light.spotRadius * 0.82
                            ))
                            .frame(width: light.spotRadius * 1.64, height: light.spotRadius * 1.64)
                            .position(light.spotCenter)
                            .blur(radius: 7)
                            .clipShape(shape)
                            .allowsHitTesting(false)
                    }

                    // (B) 外边框柔和点光源流动高光（高光更柔顺、精致不刺眼，小按钮具有极强左右方向感）
                    let strokeGradient = scheme == .dark
                        ? LinearGradient(
                            colors: [
                                Vitra.rgb(0xF2F7FF).opacity(0.82),
                                Vitra.rgb(0x84DCFF).opacity(0.70),
                                Vitra.rgb(0xC4B2FF).opacity(0.55)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                        : LinearGradient(
                            colors: [
                                .white.opacity(0.85),
                                Vitra.rgb(0x8EE0FF).opacity(0.72),
                                .white.opacity(0.60)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )

                    let borderLineWidth: CGFloat = light.isSmall ? 1.15 : (light.isBoard ? 1.35 : 1.22)

                    shape.strokeBorder(strokeGradient, lineWidth: borderLineWidth)
                        .mask {
                            if light.isSmall {
                                // 小按钮专属高聚集遮罩：中心聚拢、陡峭衰减，左右晃动时边缘亮暗灵动切换
                                Circle()
                                    .fill(RadialGradient(
                                        stops: [
                                            .init(color: .white, location: 0),
                                            .init(color: .white.opacity(0.65), location: 0.20),
                                            .init(color: .white.opacity(0.18), location: 0.52),
                                            .init(color: .clear, location: 1.0)
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: light.spotRadius
                                    ))
                                    .frame(width: light.spotRadius * 2, height: light.spotRadius * 2)
                                    .position(light.spotCenter)
                            } else {
                                // 大中型卡片专属五阶平滑高斯漫射遮罩：柔和通透
                                Circle()
                                    .fill(RadialGradient(
                                        stops: [
                                            .init(color: .white.opacity(0.88), location: 0),
                                            .init(color: .white.opacity(0.68), location: 0.20),
                                            .init(color: .white.opacity(0.35), location: 0.48),
                                            .init(color: .white.opacity(0.08), location: 0.78),
                                            .init(color: .clear, location: 1.0)
                                        ],
                                        center: .center,
                                        startRadius: 0,
                                        endRadius: light.spotRadius
                                    ))
                                    .frame(width: light.spotRadius * 2, height: light.spotRadius * 2)
                                    .position(light.spotCenter)
                            }
                        }
                        .blendMode(.screen)
                        .opacity(light.intensity * (scheme == .dark ? 0.80 : 0.75))
                        .blur(radius: 0.4)
                        .allowsHitTesting(false)

                    // (C) 内倒角动态折射流光
                    let bevelLineWidth: CGFloat = light.isSmall ? 0.85 : 1.05
                    let bevelRadius = light.spotRadius * 0.72

                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                .white.opacity(scheme == .dark ? 0.72 : 0.80),
                                Vitra.rgb(0x6AD8FF).opacity(scheme == .dark ? 0.52 : 0.62)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: bevelLineWidth
                    )
                    .padding(1)
                    .mask {
                        Circle()
                            .fill(RadialGradient(
                                stops: [
                                    .init(color: .white.opacity(0.80), location: 0),
                                    .init(color: .white.opacity(0.28), location: 0.52),
                                    .init(color: .clear, location: 1.0)
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: bevelRadius
                            ))
                            .frame(width: bevelRadius * 2, height: bevelRadius * 2)
                            .position(light.spotCenter)
                    }
                    .blur(radius: 0.5)
                    .opacity(light.intensity * (scheme == .dark ? 0.75 : 0.68))
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private var kindIsTinted: Bool {
        if case .tinted = kind { return true }
        return false
    }

    private var kindIsBoard: Bool {
        if case .board = kind { return true }
        return false
    }

    private func calculateLight(size: CGSize, frameInWindow: CGRect) -> VitraLightParams {
        let w = size.width
        let h = size.height
        guard w > 0, h > 0 else {
            return VitraLightParams(intensity: 0, spotCenter: .zero, spotRadius: 40, isSmall: false, isBoard: false)
        }

        let shortSide = min(w, h)
        let longSide = max(w, h)
        // 判定特别小的按钮（如 34x34 圆钮、32 高度胶囊、小图标舱等）
        let isSmall = (shortSide <= 44 && longSide <= 140) || (shortSide <= 36)
        let isBoard = kindIsBoard || (w >= 360 && h >= 180)

        // 1. 若鼠标在当前视图内部，直接使用精准局部坐标
        if let local = localHoverPoint {
            let spotRadius: CGFloat
            if isSmall {
                // 特别小的按钮：极度收拢聚光，半径仅 20~26 像素，左右移动明暗灵动交替
                spotRadius = max(shortSide * 0.68, 20)
            } else if isBoard {
                spotRadius = 210
            } else {
                // 中型卡片（二级卡片）
                spotRadius = min(max(shortSide * 1.35, 85), 140)
            }
            return VitraLightParams(intensity: 1.0, spotCenter: local, spotRadius: spotRadius, isSmall: isSmall, isBoard: isBoard)
        }

        // 2. 鼠标不在内部时，利用全局统一窗口光源进行协同投影
        guard let winMouse = lightCenter.windowPoint else {
            return VitraLightParams(intensity: 0, spotCenter: .zero, spotRadius: 40, isSmall: isSmall, isBoard: isBoard)
        }

        let localX = winMouse.x - frameInWindow.minX
        let localY = winMouse.y - frameInWindow.minY

        // 鼠标到卡片外边界的最短距离
        let dx = max(frameInWindow.minX - winMouse.x, 0, winMouse.x - frameInWindow.maxX)
        let dy = max(frameInWindow.minY - winMouse.y, 0, winMouse.y - frameInWindow.maxY)
        let distFromCard = sqrt(dx * dx + dy * dy)

        let maxReach: CGFloat
        let spotRadius: CGFloat
        if isSmall {
            // 小按钮在外部感应范围 85px，两个小按钮放置在一起时，中间的鼠标能让两边按钮都受到柔和照亮
            maxReach = 85
            spotRadius = max(shortSide * 0.68, 20)
        } else if isBoard {
            maxReach = 320
            spotRadius = 210
        } else {
            // 二级卡片感应范围 280px，主卡片任意角落的光源都能辐射到二级卡片
            maxReach = 280
            spotRadius = min(max(shortSide * 1.35, 85), 140)
        }

        if distFromCard > maxReach {
            return VitraLightParams(intensity: 0, spotCenter: .zero, spotRadius: spotRadius, isSmall: isSmall, isBoard: isBoard)
        }

        // 平滑高斯衰减
        let t = 1.0 - (distFromCard / maxReach)
        let intensity = t * t * (3.0 - 2.0 * t)

        // 计算光斑在卡片边框上的锚定投影点（朝向外部光源的方向）
        let borderX = min(max(localX, 0), w)
        let borderY = min(max(localY, 0), h)

        let vecX = localX - borderX
        let vecY = localY - borderY
        let vecLen = sqrt(vecX * vecX + vecY * vecY)
        let normX = vecLen > 0 ? vecX / vecLen : 0
        let normY = vecLen > 0 ? vecY / vecLen : 0

        // 将光斑投在朝向外部光源的外轮廓边缘上（微向外延展，形成菲涅尔边缘掠射角）
        let spotX = borderX + normX * min(vecLen, spotRadius * 0.22)
        let spotY = borderY + normY * min(vecLen, spotRadius * 0.22)

        return VitraLightParams(
            intensity: intensity,
            spotCenter: CGPoint(x: spotX, y: spotY),
            spotRadius: spotRadius,
            isSmall: isSmall,
            isBoard: isBoard
        )
    }
}

/// 鼠标在玻璃上的局部位置
@MainActor
final class VitraHover: ObservableObject {
    @Published var point: CGPoint?
}

/// 一块 VITRA 玻璃：彩色投影 → 磨砂主体 → 柔和高光 → 内倒角 → 不对称边框，内容永远在最上面
struct VitraGlass: ViewModifier {
    var kind: VitraGlassKind = .widget
    var radius: CGFloat = 22
    /// 跟着鼠标走的高光（长列表里关掉，省电）
    var followMouse = true

    @Environment(\.colorScheme) private var scheme
    @StateObject private var hover = VitraHover()

    func body(content: Content) -> some View {
        let p = Vitra.palette(scheme)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)

        return content
            .background {
                VitraGlassBackground(
                    kind: kind,
                    radius: radius,
                    followMouse: followMouse,
                    shape: shape,
                    palette: p,
                    scheme: scheme,
                    localHoverPoint: hover.point
                )
            }
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard followMouse else { return }
                switch phase {
                case .active(let location): hover.point = location
                case .ended: hover.point = nil
                }
            }
    }
}

extension View {
    func vitraGlass(_ kind: VitraGlassKind = .widget, radius: CGFloat = 22, followMouse: Bool = true) -> some View {
        modifier(VitraGlass(kind: kind, radius: radius, followMouse: followMouse))
    }
}

// MARK: - 按钮

/// Q 弹按钮（App 里所有能按的按钮都用它，或者用下面几种带外观的版本）
struct VitraPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        VitraJelly(pressed: configuration.isPressed) { configuration.label }
    }
}

/// 紫色光学胶囊主按钮（VITRA 的 Primary）
struct VitraPrimaryStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        VitraJelly(pressed: configuration.isPressed) {
            configuration.label
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(.white)
                .shadow(color: Vitra.rgb(0x200C58).opacity(0.28), radius: 1, y: 1)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .vitraGlass(.tinted(Vitra.violet, glow: Vitra.violetGlow), radius: 18)
        }
    }
}

/// 普通按钮：一块小玻璃胶囊（设置窗口里的「保存」「删除」这些）
struct VitraSoftStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        VitraJelly(pressed: configuration.isPressed) {
            configuration.label
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .vitraGlass(.widget, radius: 12, followMouse: false)
        }
    }
}

/// 工具栏上的玻璃圆钮（VITRA 的 widget-round），只显示图标
struct VitraRoundStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        VitraJelly(pressed: configuration.isPressed) {
            configuration.label
                .labelStyle(.iconOnly)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 34, height: 34)
                .vitraGlass(.widget, radius: 17)
        }
    }
}

/// 文字链接按钮（主题色字），也是 Q 弹的
struct VitraLinkStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        VitraJelly(pressed: configuration.isPressed) {
            configuration.label.foregroundStyle(Color.accentColor)
        }
    }
}

/// 果冻：按下缩到 94%，松手带一点回弹（阻尼小，所以会「Q」一下）；
/// 按住往外拖，跟着手指挪一点、顺着方向拉长一点（tanh 阻尼：越拉越费劲，最多挪 7 点），松手像弹簧一样弹回原位。
struct VitraJelly<Content: View>: View {
    let pressed: Bool
    @ViewBuilder let content: () -> Content
    @StateObject private var drag = VitraDrag()
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let t = reduceMotion ? .zero : drag.translation
        let dx = 7 * tanh(t.width / 70)
        let dy = 7 * tanh(t.height / 70)
        // 顺着拉的方向变长、另一个方向稍微变窄（像果冻一样体积不变）
        let sx = 1 + abs(dx) / 110 - abs(dy) / 220
        let sy = 1 + abs(dy) / 110 - abs(dx) / 220
        let press: CGFloat = pressed && isEnabled ? 0.94 : 1
        content()
            .scaleEffect(x: press * sx, y: press * sy)
            .offset(x: dx, y: dy)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.3, dampingFraction: 0.42), value: pressed)
            // 不能在按钮上叠拖动手势：会把点击吃掉（按钮有果冻感但点了没反应）。
            // 改成按下时在旁边单独看鼠标怎么动，点击照样交给按钮自己处理
            .onChange(of: pressed) { _, isPressed in
                guard isEnabled, !reduceMotion else { return }
                if isPressed { drag.begin() } else { drag.end() }
            }
            .onDisappear { drag.end() }
    }
}

/// 按钮被拖了多远
@MainActor
final class VitraDrag: ObservableObject {
    @Published var translation: CGSize = .zero
    /// nonisolated(unsafe)：deinit 里要用它把监听摘掉（按钮正被按着时消失了，不摘就一直挂在事件链上）
    nonisolated(unsafe) private var monitor: Any?

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
    }
    private var start: CGPoint = .zero

    /// 按下：记住鼠标在哪，之后鼠标拖动时跟着算偏了多少（只是旁观，事件原样交回去）
    func begin() {
        end()
        start = NSEvent.mouseLocation
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = NSEvent.mouseLocation
                withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.8)) {
                    self.translation = CGSize(width: now.x - self.start.x, height: self.start.y - now.y)
                }
            }
            return event
        }
    }

    /// 松手：像弹簧一样弹回原位
    func end() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if translation != .zero {
            withAnimation(.spring(response: 0.45, dampingFraction: 0.36)) { translation = .zero }
        }
    }
}

/// 白色实体陶瓷小按钮（CSS 的 .layer-3-inner-btn）：文字 + 右边一个深色圆形箭头舱
struct VitraSolidButton: View {
    let title: String
    var icon = "arrow.right"
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(p.solidText)
                Image(systemName: icon)
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(p.solidText))
            }
            .padding(.leading, 10)
            .padding(.trailing, 3)
            .padding(.vertical, 3)
            .background(Capsule().fill(p.solid))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.05)))
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.10), radius: 4, y: 2)
        }
        .buttonStyle(VitraPressStyle())
    }
}

// MARK: - 分段栏

/// VITRA 的液态分段栏：玻璃轨道，选中的一格是白色陶瓷胶囊，切换时滑过去；每一格都是 Q 弹的。
/// 用来代替系统的分段按钮（系统的没法加果冻效果）。
struct VitraSegmented<Value: Hashable>: View {
    let options: [(title: String, value: Value)]
    let selection: Value
    let onSelect: (Value) -> Void
    @Namespace private var thumb
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = Vitra.palette(scheme)
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let selected = option.value == selection
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { onSelect(option.value) }
                } label: {
                    Text(option.title)
                        .font(.system(size: 12.5, weight: .bold))
                        .foregroundStyle(selected ? p.solidText : p.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background {
                            if selected {
                                Capsule()
                                    .fill(p.solid)
                                    .overlay(Capsule().strokeBorder(.white.opacity(0.9), lineWidth: 1))
                                    .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.12), radius: 4, y: 2)
                                    .matchedGeometryEffect(id: "thumb", in: thumb)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(VitraPressStyle())
            }
        }
        .padding(3)
        .vitraGlass(.widget, radius: 17)
    }
}
