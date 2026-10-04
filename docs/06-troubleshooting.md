# 排错清单

## `flutter build ios --no-codesign` 找不到 iOS 工程

确认仓库里有 `ios/` 目录：

```bash
ls ios
```

如果没有，在本地执行：

```bash
flutter create --platforms=ios .
```

然后提交生成文件。

## `No profiles for ... were found`

这是签名问题。检查：

- Bundle ID 是否和 Provisioning Profile 匹配。
- profile 是否真的安装到了 `~/Library/MobileDevice/Provisioning Profiles/`。
- `ExportOptions.plist` 的 `method` 是否和 profile 类型匹配。
- `teamID` 是否正确。

## `Code Signing Error`

检查：

- `.p12` 密码是否正确。
- keychain 是否 unlock。
- certificate 是否是 Apple Distribution 或 Apple Development，取决于 method。
- profile 是否包含对应证书。

## Artifact 里没有 IPA

检查打包路径：

```bash
ls -la build/ios/iphoneos
ls -la build/ios/ipa
ls -la *.ipa
```

未签名 workflow 通常手动 zip `Payload/Runner.app`。

签名 workflow 通常产物在：

```text
build/ios/ipa/*.ipa
```

或 `xcodebuild -exportArchive` 指定目录。

## 构建在本地可以，在 CI 失败

常见原因：

- 本地有未提交文件。
- 依赖版本没有锁定。
- iOS 目录里引用了本地绝对路径。
- 证书/profile 没有放进 Secrets。
- 某些插件需要更高的 iOS deployment target。

## 建议固定 deployment target

如果插件要求 iOS 13 或更高，确保 Xcode project 里设置一致。Flutter 项目常见最低版本可从 `ios/Podfile` 或 Xcode build settings 中调整。

## 私有依赖拉取失败

如果项目依赖私有 Git 仓库：

- 使用 deploy key 或 GitHub token。
- 不要把 token 写入 `pubspec.yaml`。
- 在 workflow 中通过 `secrets` 配置 git credentials。
