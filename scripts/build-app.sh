#!/bin/bash
# 编译、打包，并安装到「应用程序」文件夹：~/Applications/学习助手.app。不需要 Xcode。
#
# 用法：在项目文件夹里运行  ./scripts/build-app.sh
# 注意：每次重新打包后第一次打开，系统可能会再问一次「是否允许访问钥匙串」，点「始终允许」就行。
#
# 为什么装到「应用程序」文件夹，而不是放在项目里：
# 桌面、文稿这些文件夹受 macOS 隐私保护，定时任务到点去启动放在那里的 App 可能会被系统拦下。
set -euo pipefail
cd "$(dirname "$0")/.."

echo "▶ 编译（release 版，大约 1 分钟）…"
swift build -c release --product SchoolisHelper

echo "▶ 生成图标"
# 优先用 GitHub 云端 Mac 编译好的新格式图标（App/CompiledIcon/）：
# Assets.car 里有浅色、深色两套，系统自己跟着外观换，App 关着时访达、启动台里也会换。
# 想换图标：改 icon-build/ 里的图层，push 到你自己的 GitHub 仓库，
# 等云端编译完，下载 icon-result，把 Assets.car 和 AppIcon.icns 放进 App/CompiledIcon/。
COMPILED="App/CompiledIcon"
ICONSET=".build/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
if [ -f App/AppIcon.png ]; then
    # 你提供的正式图标（1024×1024 PNG）：缩放成各种尺寸
    # （原图换了的话，先运行：swiftc -O scripts/make-icons.swift -o .build/make-icons && .build/make-icons App/AppIcon-source.png App）
    for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
                "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" "512 icon_256x256@2x" \
                "512 icon_512x512" "1024 icon_512x512@2x"; do
        set -- $spec
        sips -z "$1" "$1" App/AppIcon.png --out "$ICONSET/$2.png" >/dev/null
    done
else
    # 还没有正式图标：先用程序画的临时图标
    echo "  （用的是临时图标。正式图标请做成 1024×1024 PNG，放到 App/AppIcon.png）"
    swiftc -O scripts/render-icon.swift -o .build/render-icon
    .build/render-icon "$ICONSET"
fi
if [ -f "$COMPILED/Assets.car" ]; then
    echo "  用的是云端编译的深浅色图标（App/CompiledIcon）"
else
    iconutil -c icns "$ICONSET" -o .build/AppIcon.icns
fi

APP="$HOME/Applications/学习助手.app"
echo "▶ 安装到 $APP"
# 如果 App 正在运行，先让它退出，免得替换文件时出问题
# 先正常退出（App 会顺手关掉它自己开的本地模型），等两秒还没退就强制结束
osascript -e 'quit app id "io.github.cealias.schoolishelper"' >/dev/null 2>&1 || true
sleep 2
pkill -x SchoolisHelper 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/SchoolisHelper "$APP/Contents/MacOS/SchoolisHelper"
cp App/Info.plist "$APP/Contents/Info.plist"
if [ -f "$COMPILED/Assets.car" ]; then
    cp "$COMPILED/Assets.car" "$COMPILED/AppIcon.icns" "$APP/Contents/Resources/"
else
    cp .build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# 本地签名："-" 表示不用开发者证书，只在这台电脑上用
codesign --force --sign - "$APP"
# 让系统重新登记一下这个 App，换了图标能马上显示新的
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP" 2>/dev/null || true

# 旧版本放在项目的 dist/ 里，现在统一装到「应用程序」，把旧的删掉，免得聚焦搜索搜出两个
rm -rf dist

echo "✅ 装好了：$APP"
echo "   打开它：open \"$APP\""
