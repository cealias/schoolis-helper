// 把一张图标原图做成 App 要用的两个版本：
//   App/AppIcon.png        深色模式用（原图）
//   App/AppIcon-Light.png  浅色模式用（把深蓝底色和方块之间的缝变成白色）
// 两张都会缩放到 macOS 图标的标准尺寸：1024×1024 的画布，主体占 824×824（四周留白）。
//
// 用法：swiftc -O scripts/make-icons.swift -o .build/make-icons && .build/make-icons <原图.png> App
//
// 浅色版是怎么做的：
// 原图里方块是很亮的蓝（亮度 V≈250），深蓝底色和缝很暗（V≈80～140），
// 边框的发光从 V≈250 往里慢慢变暗。所以按「越暗越变白」处理：
// V≤150 的全变白，V≥235 的保持原样，中间按比例混合。
// 这样方块不动，边框留一圈蓝色光、往里过渡成白色，正是想要的效果。
import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 3,
      let sourceRep = NSBitmapImageRep(data: try Data(contentsOf: URL(fileURLWithPath: arguments[1]))),
      let source = sourceRep.cgImage else {
    print("用法：make-icons <原图.png> <输出文件夹>")
    exit(1)
}
let outputFolder = URL(fileURLWithPath: arguments[2])
let width = source.width, height = source.height
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

/// 把图片读成一串 RGBA 字节（预乘透明度），方便逐个像素改
func pixels(of image: CGImage) -> [UInt8] {
    var buffer = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(data: &buffer, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    return buffer
}

func image(from buffer: [UInt8]) -> CGImage {
    var copy = buffer
    let context = CGContext(data: &copy, width: width, height: height, bitsPerComponent: 8,
                            bytesPerRow: width * 4, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}

let original = pixels(of: source)

// 1. 找图标主体的边界（不透明的部分），用来缩放到标准尺寸
var minX = width, maxX = 0, minY = height, maxY = 0
for y in 0..<height {
    for x in 0..<width where original[(y * width + x) * 4 + 3] > 128 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    }
}
let bodySize = Double(max(maxX - minX, maxY - minY))
let centerX = Double(minX + maxX) / 2, centerY = Double(minY + maxY) / 2
print("原图主体：\(Int(bodySize)) 像素（画布的 \(Int(bodySize / Double(width) * 100))%）")

// 2. 浅色版：越暗的地方越变白
func smoothstep(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let t = min(max((x - edge0) / (edge1 - edge0), 0), 1)
    return t * t * (3 - 2 * t)
}
let white: (Double, Double, Double) = (247, 250, 255) // 带一点点蓝的白，比纯白柔和
var light = original
for i in stride(from: 0, to: light.count, by: 4) {
    let alpha = Double(light[i + 3])
    guard alpha > 0 else { continue }
    // 先去掉预乘，拿到真实颜色
    let r = Double(light[i]) * 255 / alpha, g = Double(light[i + 1]) * 255 / alpha, b = Double(light[i + 2]) * 255 / alpha
    let keep = smoothstep(150, 235, max(r, g, b)) // 1 = 保持原色，0 = 全变白
    let nr = r * keep + white.0 * (1 - keep)
    let ng = g * keep + white.1 * (1 - keep)
    let nb = b * keep + white.2 * (1 - keep)
    light[i] = UInt8(min(255, nr * alpha / 255))
    light[i + 1] = UInt8(min(255, ng * alpha / 255))
    light[i + 2] = UInt8(min(255, nb * alpha / 255))
}

// 3. 缩放到 1024 画布、主体 824，居中，存成 PNG
func save(_ image: CGImage, to name: String) throws {
    let canvas = 1024, body = 824.0
    let scale = body / bodySize
    let context = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    // CGContext 的 y 轴朝上，而像素行是从上往下数的，所以 y 方向要翻一下
    let drawWidth = Double(width) * scale, drawHeight = Double(height) * scale
    let originX = Double(canvas) / 2 - centerX * scale
    let originY = Double(canvas) / 2 - (Double(height) - centerY) * scale
    context.draw(image, in: CGRect(x: originX, y: originY, width: drawWidth, height: drawHeight))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: outputFolder.appendingPathComponent(name))
    print("已生成 \(name)")
}

try save(image(from: original), to: "AppIcon.png")
try save(image(from: light), to: "AppIcon-Light.png")
