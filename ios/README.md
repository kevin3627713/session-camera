# iOS folder notes

真实项目请用 Flutter 生成完整 `ios/` 目录：

```bash
flutter create --platforms=ios .
```

然后检查这些设置：

- `PRODUCT_BUNDLE_IDENTIFIER = com.example.ipaCiDemo;`
- `IPHONEOS_DEPLOYMENT_TARGET = 13.0;`
- `CURRENT_PROJECT_VERSION = "$(FLUTTER_BUILD_NUMBER)";`
- `MARKETING_VERSION = "$(FLUTTER_BUILD_NAME)";`
- 签名构建时将 `CODE_SIGN_STYLE` 与 profile 策略保持一致。

本目录只放说明和 plist 片段，避免提交与特定项目绑定的 Xcode 工程文件。
