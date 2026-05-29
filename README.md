# File Frog Native

原生 macOS 桌宠原型，用 AppKit/Swift 实现。

## 功能

- 透明无边框置顶桌宠窗口
- 按住青蛙拖动整个窗口
- 拖入文件时用柔光反馈识别/投喂状态，默认不显示调试圈
- 支持从 Finder/桌面拖 PDF、TXT、Markdown 到青蛙
- 处理文件时会拒绝新的投喂，避免连续拖入把状态机打乱
- 使用 PDFKit 和本地文本读取生成规则摘要，不接 AI 后端
- 本地保存最近文档、抽取文本和摘要缓存
- 原生绘制青蛙、文件 ghost、吞文件动画、处理进度、结果卡
- 处理文案按“咬开文件、抓重点、找风险、整理好了”推进
- 菜单栏“重置咕噜蛙”会取消当前处理并回到可投喂状态
- 点击结果卡打开理解窗口，查看历史、要点、风险、原文片段和推荐问答
- 菜单栏提供显示、隐藏、重置咕噜蛙、打开理解窗口、退出入口
- GitHub Actions 在线打包标准 Finder 拖拽安装布局的 `.dmg`

## 本地缓存

应用会把本地理解结果保存到：

```text
~/Library/Application Support/File Frog/
```

其中 `library.json` 保存历史记录，`documents/{documentId}/` 保存抽取文本和摘要。

## 本地运行

```bash
swift run FileFrogNative
```

## 本地打包

```bash
./Scripts/package_app.sh
```

产物在 `build/File Frog.app.zip`。
同时会生成 `build/FileFrog.dmg`，打开后把 `File Frog.app` 拖到 `Applications` 安装。

## 线上打包

推到 GitHub 后，进入 Actions，运行 `Build macOS App` workflow。完成后下载 `FileFrog-macOS` artifact，解压后打开 `FileFrog.dmg`，把 `File Frog.app` 拖到 `Applications`。
