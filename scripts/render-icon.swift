// 画一个【临时】App 图标：蓝紫渐变的圆角方块 + 白色的清单符号。
//
// 这只是占位用的。正式图标请你用专业工具做：1024×1024 的 PNG，
// 放到 App/AppIcon.png，重新运行 build-app.sh 就会自动换上，不再用这个。
//
// 用法：render-icon <输出的 .iconset 文件夹>
import AppKit

let outputFolder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outputFolder, withIntermediateDirectories: true)

func draw(in rect: NSRect) {
    // Apple 的图标规范：四周留大约 10% 的空白，圆角方块画在中间
    let body = rect.insetBy(dx: rect.width * 0.1, dy: rect.height * 0.1)
    let shape = NSBezierPath(roundedRect: body, xRadius: body.width * 0.225, yRadius: body.height * 0.225)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    shadow.shadowBlurRadius = rect.width * 0.02
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.01)
    shadow.set()
    NSGradient(starting: NSColor(calibratedRed: 0.36, green: 0.55, blue: 1.00, alpha: 1),
               ending: NSColor(calibratedRed: 0.47, green: 0.33, blue: 0.93, alpha: 1))!
        .draw(in: shape, angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let config = NSImage.SymbolConfiguration(pointSize: body.height * 0.48, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))
    if let symbol = NSImage(systemSymbolName: "checklist", accessibilityDescription: nil)?
        .withSymbolConfiguration(config) {
        let size = symbol.size
        symbol.draw(in: NSRect(x: body.midX - size.width / 2, y: body.midY - size.height / 2,
                               width: size.width, height: size.height))
    }
}

func png(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// .iconset 要求的文件名和尺寸
let files: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in files {
    try png(pixels: pixels).write(to: outputFolder.appendingPathComponent("\(name).png"))
}
