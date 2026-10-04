# 借拍的 iOS 原生实现

本目录已包含完整 Xcode 工程，由 Flutter 3.35.4 的 CI 构建。不要重新生成或覆盖 Runner 的原生源文件。

- Bundle ID: `com.kevin3627713.sessioncamera`
- Minimum iOS: 17.0
- `AppDelegate.swift`: Flutter 启动桥接、SwiftUI 全屏相机、任务切换器遮罩。
- `CameraEngine.swift`: AVFoundation、串行会话配置、拍照/录像、对焦/变焦/曝光。
- `CameraScreen.swift`: 原生界面、本次画廊、视频播放、引导式访问说明。
- `SessionStore.swift`: 本次资产 ID 范围、保存重试、PhotoKit 非破坏性编辑。
- `PhotoEditor.swift`: Core Image 渲染和照片编辑界面。
- `SessionLedger.swift` 的工程引用指向 `native/SessionCore/Sources/SessionCore`，应用和测试使用同一份实现。
- `PhotoRendering.swift` 的工程引用指向 `native/SessionCore/Sources/PhotoCore`，应用和 macOS CI 测试共用 Core Image / ImageIO 渲染及编码。

使用步骤与权限边界见根目录 [README.md](../README.md)，原生渲染测试位于 `RunnerTests/RunnerTests.swift`。
