# 可选照片组件诊断

普通 Debug / Release 构建均不定义 `WIDGET_PHOTO_DIAGNOSTICS`，因此不包含照片排查参数、诊断枚举、64×64 测试图、诊断时间线、系统日志或 Mach 内存采样。生产源码只保留受条件编译保护的接入点。ImageIO 尺寸读取仍属于生产缓存校验，保留在 PhotoImageMetadata 中。

## 启用诊断 IPA

在 GitHub Actions 的 **Build unsigned iOS IPA** 手动运行界面，选择当前开发分支并勾选 `widget_diagnostics`。工作流仅在该次构建为扩展添加 `WIDGET_PHOTO_DIAGNOSTICS`，并使用相应的 IPA 元数据检查。普通推送构建及未勾选的手动构建都关闭。

本地 Xcode 也可只在 SessionWidgets target 的 Swift Active Compilation Conditions 中添加该标志。手动打包诊断 IPA 时：

```sh
WIDGET_PHOTO_DIAGNOSTICS=1 bash scripts/package_unsigned_ipa.sh
```

这个打包环境变量只切换产物检查方式，不会为已经编译的扩展补上诊断；编译时必须同时启用 Swift 标志。

诊断版在编辑照片小组件中选择“照片排查”：1 测试图与文字；2 只读取相册；3 请求照片但只显示结果。最后关闭恢复照片。使用原来的主应用 / 扩展 ID，可以覆盖同一个自签名槽位。

## 继续验证

```sh
WIDGET_PHOTO_DIAGNOSTICS=0 bash scripts/test_widget_photos.sh
WIDGET_PHOTO_DIAGNOSTICS=1 bash scripts/test_widget_photos.sh
```

专项工作流矩阵分别编译和执行两种模式；普通模式检查生产加载逻辑，诊断模式额外检查三个阶段及默认关闭。日志仅记录处理阶段、尺寸 / 位深和采样时的 phys_footprint，没有照片内容、资产 ID 或相册名称，没有上传逻辑。阶段采样不能代替系统 Jetsam 报告。
