// swift-tools-version:5.10
// 工程说明书：告诉 Swift 这个项目有哪些部分。
// 不用 Xcode，直接在终端里 `swift build` 就能编译。
import PackageDescription

let package = Package(
    name: "SchoolisHelper",
    // 只在这台 Mac（macOS 27）上用，所以直接要求 macOS 26+，好用上 Liquid Glass
    platforms: [.macOS("26.0")],
    targets: [
        // 核心代码：登录、调接口。以后的菜单栏 App 直接复用这一块，不用重写。
        .target(name: "SchoolisCore"),
        // M1 探针：一个命令行小程序，把每个接口调一遍，确认数据拿得到、和网页对得上。
        .executableTarget(name: "probe", dependencies: ["SchoolisCore"]),
        // 菜单栏 App 本体。用 scripts/build-app.sh 打包成 学习助手.app。
        .executableTarget(name: "SchoolisHelper", dependencies: ["SchoolisCore"]),
    ]
)
