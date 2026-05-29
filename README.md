# File Frog Native

原生 macOS 桌宠原型，用 AppKit/Swift 实现。

## 功能

- 透明无边框置顶桌宠窗口
- 按住青蛙拖动整个窗口
- 红色识别区、绿色可投喂区
- 支持从 Finder/桌面拖文件到青蛙
- 原生绘制青蛙、文件 ghost、吞文件动画、消化进度、结果卡
- GitHub Actions 在线打包 `.app.zip`

## 本地运行

```bash
swift run FileFrogNative
```

## 本地打包

```bash
./Scripts/package_app.sh
```

产物在 `build/FileFrogNative.app.zip`。
同时会生成 `build/FileFrogNative.dmg`，推荐下载和分发 dmg。

## 线上打包

推到 GitHub 后，进入 Actions，运行 `Build macOS App` workflow。完成后下载 `FileFrogNative-macOS` artifact，解压后打开 `FileFrogNative.dmg`。
