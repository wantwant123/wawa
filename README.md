# File Frog Native

原生 macOS 桌宠原型，用 AppKit/Swift 实现。

## 功能

- 透明无边框置顶桌宠窗口
- 按住青蛙拖动整个窗口
- 拖入文件时用柔光反馈识别/投喂状态，默认不显示调试圈
- 支持从 Finder/桌面拖文件到青蛙
- 原生绘制青蛙、文件 ghost、吞文件动画、消化进度、结果卡
- 菜单栏提供显示、隐藏、重置位置和退出入口
- GitHub Actions 在线打包 `.dmg`

## 本地运行

```bash
swift run FileFrogNative
```

## 本地打包

```bash
./Scripts/package_app.sh
```

产物在 `build/File Frog.app.zip`。
同时会生成 `build/FileFrog.dmg`，推荐下载和分发 dmg。

## 线上打包

推到 GitHub 后，进入 Actions，运行 `Build macOS App` workflow。完成后下载 `FileFrog-macOS` artifact，解压后打开 `FileFrog.dmg`。
