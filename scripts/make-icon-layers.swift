// 把深色、浅色两张图标做成苹果新图标格式（.icon）要用的两张图层：light.png、dark.png（1024×1024）。
//
// 用法：swiftc -O scripts/make-icon-layers.swift -o .build/make-icon-layers
//       .build/make-icon-layers 深色.png 浅色.png icon-build/AppIcon.icon/Assets
//
// 做了三件事：
// 1. 量出每张图「主体」（不透明的圆角方块）有多大。两张原图主体大小不一样（深色宽 1102、浅色宽 1042），所以分别量；
// 2. 把主体放大 / 缩小到铺满 1024×1024，两张就一样大了；
// 3. 主体四个圆角外面是透明的，用主体边缘的颜色补满。
//    macOS 26 的新图标由系统自己切圆角方块，图层要铺满整个正方形，不然角上会露出底色。

import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fatalError("读不了 \(path)")
    }
    return image
}

func pixels(of image: CGImage) -> [UInt8] {
    var data = [UInt8](repeating: 0, count: image.width * image.height * 4)
    let context = CGContext(data: &data, width: image.width, height: image.height, bitsPerComponent: 8,
                            bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return data
}

func makeLayer(from path: String, to output: URL) {
    let image = load(path)
    let w = image.width, h = image.height
    let px = pixels(of: image)
    func alpha(_ x: Int, _ y: Int) -> UInt8 { px[(y * w + x) * 4 + 3] }

    // 1. 主体的范围：alpha > 40 的像素（去掉外面那圈几乎透明的毛边）
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h { for x in 0..<w where alpha(x, y) > 40 {
        minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
    } }
    let bodyW = maxX - minX + 1, bodyH = maxY - minY + 1

    // 3. 边缘颜色：四条边中点往里 6 像素，取平均（数组里第 0 行是图片最上面一行）
    let samples = [(minX + 6, (minY + maxY) / 2), (maxX - 6, (minY + maxY) / 2),
                   ((minX + maxX) / 2, minY + 6), ((minX + maxX) / 2, maxY - 6)]
    var rgb = [0.0, 0.0, 0.0]
    for (x, y) in samples {
        let i = (y * w + x) * 4
        let a = max(Double(px[i + 3]), 1)
        for c in 0..<3 { rgb[c] += Double(px[i + c]) / a / Double(samples.count) } // 去掉预乘
    }

    // 2. 画到 1024×1024：先铺边缘色，再把主体拉伸到铺满
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.interpolationQuality = .high
    context.setFillColor(CGColor(srgbRed: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    // CGImage 的裁剪坐标从左上角算
    let body = image.cropping(to: CGRect(x: minX, y: minY, width: bodyW, height: bodyH))!
    context.draw(body, in: CGRect(x: 0, y: 0, width: size, height: size))

    let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("写不了 \(output.path)") }
    let hex = rgb.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    print("✅ \(output.lastPathComponent)：主体 \(bodyW)×\(bodyH) → \(size)×\(size)，四角补色 #\(hex)")
}

let args = CommandLine.arguments
guard args.count == 4 else {
    print("用法：make-icon-layers 深色.png 浅色.png 输出文件夹")
    exit(1)
}
let folder = URL(fileURLWithPath: args[3])
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
makeLayer(from: args[1], to: folder.appendingPathComponent("dark.png"))
makeLayer(from: args[2], to: folder.appendingPathComponent("light.png"))
