# 无 Mac 创建 Flutter iOS 项目

## 推荐方式

即使没有 Mac，也可以在 Windows/Linux 上创建 Flutter 项目并提交源码。Flutter 会生成 `ios/` 目录，但真正编译 iOS 的步骤交给 GitHub Actions 的 macOS runner。

```powershell
flutter create my_app
cd my_app
flutter pub get
git init
git add .
git commit -m "Initial Flutter app"
```

如果你的现有项目没有 `ios/` 目录，可以运行：

```powershell
flutter create --platforms=ios .
```

## 需要关注的文件

- `pubspec.yaml`：项目名、版本、依赖。
- `ios/Runner/Info.plist`：iOS App 元信息。
- `ios/Runner.xcodeproj/project.pbxproj`：Bundle ID、部署版本、签名配置等。
- `.github/workflows/release-ios.yml`：CI 构建流程。
- `.gitignore`：避免提交 build 产物、证书、缓存。

## Bundle ID

请使用你自己的反向域名，例如：

```text
com.example.ipaCiDemo
```

签名构建时，Bundle ID 必须与 Apple Developer 后台的 App ID 和 Provisioning Profile 完全匹配。

## Flutter 版本

建议在 CI 里固定 Flutter channel，必要时固定 Flutter 版本。最简单方式是克隆 stable：

```bash
git clone --depth 1 --branch stable https://github.com/flutter/flutter.git "$RUNNER_TEMP/flutter"
echo "$RUNNER_TEMP/flutter/bin" >> "$GITHUB_PATH"
flutter --version
```

也可以使用 `subosito/flutter-action`，更短但多依赖一个 action：

```yaml
- uses: subosito/flutter-action@v2
  with:
    channel: stable
```

## 依赖 Rust 或原生代码怎么办

如果项目像一些 Flutter + Rust 架构一样带有额外 native module，可以拆成两类检查：

```yaml
- name: Flutter analyze
  run: flutter analyze --no-fatal-infos --fatal-warnings

- name: Rust check
  run: cargo check --manifest-path native-core/Cargo.toml
```

但示例仓库不包含任何实际 Rust 业务源码，只保留这种“多语言项目如何在 CI 里分层检查”的模式。
