# 核心原理

## 没有 Mac 为什么还能编译 iOS

iOS 编译必须依赖 Apple 的 Xcode 工具链。没有本地 Mac 时，可以借助 GitHub Actions 提供的 macOS runner：

- `ubuntu-latest`：适合跑 Flutter analyze、test、Rust check 等不依赖 Xcode 的检查。
- `macos-latest` 或固定版本如 `macos-15`：适合跑 `flutter build ios`、`xcodebuild`、codesign、打包 IPA。

也就是说，我们不是在 Windows 上直接编译 iOS，而是：

1. 在 Windows/Linux 上写代码。
2. 推送到 GitHub。
3. GitHub Actions 启动一台临时 macOS runner。
4. 在 runner 上安装/准备 Flutter。
5. 执行 iOS 编译。
6. 上传 IPA artifact。

## 两种 IPA 路线

### 1. 未签名 IPA

适合：

- 验证项目可以编译。
- 先打通 CI。
- 留给后续工具或人工流程再签名。

核心命令：

```bash
flutter build ios --release --no-codesign
mkdir -p Payload
cp -R build/ios/iphoneos/Runner.app Payload/Runner.app
zip -q -r app_no_sign.ipa Payload
```

注意：未签名 IPA 一般不能直接装到普通 iPhone。

### 2. 签名 IPA

适合：

- Ad Hoc 分发。
- TestFlight。
- App Store Connect 上传。
- 企业签名，取决于你的 Apple 账号类型。

需要：

- Apple Developer Program 账号。
- Distribution certificate，通常导出为 `.p12`。
- Provisioning Profile，通常是 `.mobileprovision`。
- Bundle ID 与 profile 匹配。
- GitHub Secrets 保存证书、密码、profile。

## 从实际项目抽象出的 CI 结构

一个稳妥的结构通常是：

- `verify` job 跑在 Ubuntu 上，负责静态检查和测试。
- `build-ios` job 跑在 macOS 上，负责 Flutter iOS 构建和 IPA 打包。
- tag 触发正式构建，`workflow_dispatch` 支持手动构建。
- 产物通过 `actions/upload-artifact` 上传，而不是提交回仓库。

示意：

```yaml
jobs:
  verify:
    runs-on: ubuntu-latest
  build-ios:
    needs: [verify]
    runs-on: macos-latest
```

如果你想允许“跳过 verify 直接构建”，可以结合 `workflow_dispatch` input 和 `always()` 控制依赖逻辑。
