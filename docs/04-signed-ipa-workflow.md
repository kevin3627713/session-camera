# 签名 IPA Workflow

当你需要把 IPA 安装到真机、通过 TestFlight 分发或上传 App Store 时，就需要签名。

## 需要准备的材料

- Apple Developer Program 账号。
- App ID / Bundle ID，例如 `com.example.ipaCiDemo`。
- Apple Distribution 证书，导出为 `.p12`。
- `.p12` 密码。
- Provisioning Profile，文件后缀为 `.mobileprovision`。
- Export method：`ad-hoc`、`app-store`、`development` 或 `enterprise`。

## GitHub Secrets 设计

建议使用这些 secrets：

```text
IOS_CERTIFICATE_P12_BASE64
IOS_CERTIFICATE_PASSWORD
IOS_PROVISION_PROFILE_BASE64
IOS_KEYCHAIN_PASSWORD
IOS_EXPORT_METHOD
IOS_TEAM_ID
```

在 Windows 上把文件转 base64：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("dist.p12")) | Set-Clipboard
[Convert]::ToBase64String([IO.File]::ReadAllBytes("profile.mobileprovision")) | Set-Clipboard
```

粘贴到 GitHub Secrets。

## CI 中安装证书和 profile

关键思路：

1. 解码 `.p12` 和 `.mobileprovision`。
2. 创建临时 keychain。
3. 导入证书。
4. 把 profile 放到 `~/Library/MobileDevice/Provisioning Profiles/`。
5. 使用 `xcodebuild -exportArchive` 导出 IPA。

完整示例见：[`examples/flutter_ipa_ci/.github/workflows/release-ios-signed.yml`](../examples/flutter_ipa_ci/.github/workflows/release-ios-signed.yml)

## ExportOptions.plist

GitHub Actions 中可以动态生成：

```xml
<plist version="1.0">
<dict>
  <key>method</key>
  <string>ad-hoc</string>
  <key>teamID</key>
  <string>ABCDE12345</string>
  <key>signingStyle</key>
  <string>manual</string>
</dict>
</plist>
```

不同 method 的含义：

| method | 用途 |
| --- | --- |
| `development` | 开发设备安装 |
| `ad-hoc` | 指定 UDID 设备安装 |
| `app-store` | App Store/TestFlight |
| `enterprise` | 企业内部分发 |

## 安全注意

- 永远不要提交 `.p12`、`.mobileprovision`、`.pem`、`.key`。
- 不要在 log 里 echo secret。
- workflow 里使用临时 keychain，构建结束后删除。
- private repo 不等于可以提交私钥；仓库私有也可能被 fork、泄露或被误授权。
