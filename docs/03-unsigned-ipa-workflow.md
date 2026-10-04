# 未签名 IPA Workflow

未签名构建是最容易打通的第一步。它不需要 Apple Developer 证书，也不需要 GitHub Secrets。

## 触发方式

推荐同时支持：

- push tag 触发正式构建。
- `workflow_dispatch` 手动触发。

## 完整示例

见：[`examples/flutter_ipa_ci/.github/workflows/release-ios-unsigned.yml`](../examples/flutter_ipa_ci/.github/workflows/release-ios-unsigned.yml)

核心步骤：

```yaml
- name: Build iOS app without signing
  run: flutter build ios --release --no-codesign

- name: Package IPA unsigned
  run: |
    mkdir -p Payload
    cp -R build/ios/iphoneos/Runner.app Payload/Runner.app
    zip -q -r example_${{ env.BUILD_NAME }}_no_sign.ipa Payload
```

## 为什么要重新 codesign framework

某些 Flutter 插件或 framework 在无签名打包时可能保留不一致签名。可以用 ad-hoc 签名减少后续打包问题：

```bash
find Payload/Runner.app/Frameworks -type d -name "*.framework" -exec codesign --force --sign - --preserve-metadata=identifier,entitlements {} \;
```

这不是正式签名，只是 ad-hoc 签名，不能替代 Apple Distribution 证书。

## 下载产物

构建完成后：

1. 打开 GitHub 仓库。
2. 进入 Actions。
3. 选择对应 workflow run。
4. 在 Artifacts 下载 `ios_unsigned_ipa`。

## 验证产物内容

IPA 本质是 zip：

```powershell
Rename-Item .\example_no_sign.ipa example_no_sign.zip
Expand-Archive .\example_no_sign.zip .\ipa-unpacked
Get-ChildItem .\ipa-unpacked\Payload
```

应能看到：

```text
Payload/Runner.app
```
