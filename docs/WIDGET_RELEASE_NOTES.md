# 借拍 0.3.3：精简界面与进程会话

机主已确认 0.3.2 的照片组件在 iOS 18.7.8 正常显示。本版保留单张高清图的加载、裁剪、缓存和重试策略，分离排查工具，调整相机界面与会话边界。

- 排查枚举、三个诊断时间线、测试图、系统日志和内存采样移到 native/WidgetDiagnostics。只有显式启用 WIDGET_PHOTO_DIAGNOSTICS 才编译；普通 IPA 的编辑面板没有“照片排查”。生产缓存的 ImageIO 尺寸校验继续保留。诊断代码与复现步骤没有删除。
- 去掉任务切换器的“借拍 · 本次可见”文字、照片页的拍摄说明及空页提示段落。预览 / 网格标题改为“照片”，信息按钮只显示媒体类型和拍摄时间。设置页压缩为引导式访问、自动化和照片组件权限入口，首次启动不再弹出说明。保留错误提示、移除预览的确认和机主验证。
- SessionStore 由 AppDelegate 持有。切后台只停止相机与倒计时，保留照片、预览和编辑；晚到的照片 / 视频仍属同一会话。视图重建不会新建会话，也不会再次清理正在使用的原图。划掉应用重开或系统终止后重新启动才创建空会话。
- 保留任务切换器黑色遮罩；机主照片设置切后台后仍需重新验证。会话清空不删除已经保存到系统照片的内容。

版本 0.3.3 / build 8，沿用同一主应用 ID 与扩展 ID，仍恰好一个 WidgetKit 扩展，五种样式、原生编辑、独立随机序列和默认点击不打开应用均保留。用相同签名身份覆盖升级并保留 SessionWidgets.appex，沿用现有应用槽位。开发继续在 experiment/transparent-widgets-ios18，正式 main 不变。

两种编译模式分别运行 PhotoKit 源码宿主检查；正常 IPA 检查明确拒绝诊断元数据与诊断二进制标记。实际相机视图的 XCTest 覆盖后台通知、晚到回调、当前文件保留、视图重建及新进程会话隔离。模拟器不能代替真机相机与签名验收。

[诊断代码与启用方法](../native/WidgetDiagnostics/README.md) · [历史照片调查](WIDGET_PHOTO_INVESTIGATION.md) · [隐私与会话设计](PRIVACY.md)

## 验证与下载

- 普通模式 32 项 / 诊断模式 36 项 PhotoKit 源码宿主检查全部通过：[照片专项 37323039643](https://github.com/kevin3627713/session-camera/actions/runs/37323039643)。普通版元数据只有五个生产参数，不含诊断枚举、内存日志或测试图字符串；保留的诊断扩展单独编译并成功注册三个阶段。
- 两种屏幕尺寸、七种状态共 14 张实际 Swift 界面截图生成成功，照片页 / 网格页已查看：[界面运行 37322428530](https://github.com/kevin3627713/session-camera/actions/runs/37322428530)，来源提交 29b735aee3d85af04621ffa52f1112e99d24f654。图片均是原创合成测试内容。
- iOS 18 XCTest 宿主的会话回归和三项编辑测试全部通过：[独立运行 37327457989](https://github.com/kevin3627713/session-camera/actions/runs/37327457989)，[结构化记录](verification/camera-session-ios18.json)。后台通知、晚到回调、原文件保留、视图重建和新 Store 隔离均执行了生产源码。新进程由新 Store 建模，未自动化真实划掉进程；硬件与签名仍需真机验收。
- 发行 IPA 来自 [构建 37323042913](https://github.com/kevin3627713/session-camera/actions/runs/37323042913) 的成功编译与打包步骤，生产源码提交 7f3ecf4144c32e9d5a32a4c6deffecfeb693ca31。19 项 Swift、18 项描述符、2 项 Flutter 和 32 项普通模式照片检查通过。该次整体任务因可选 XCTest 选中了冷启动耗时很长的 iOS 26 模拟器而超时，日志里的四项测试实际已通过；随后固定为 iOS 18，并由上述独立运行取得完整成功结果。之后只有测试工作流与文档变化，发行源码与包保持一致。

IPA 大小 6,627,086 字节，SHA-256：76c883ba1e461547ffc4521fddec9b8b3a9fa685c41003111d9d6256eb4f71c0。下载的成品再次通过 ZIP、arm64、唯一扩展、版本匹配、配置默认值以及诊断移除检查。

[下载 0.3.3 IPA](https://github.com/kevin3627713/session-camera/releases/download/widgets-ios18-v0.3.3/session-camera-unsigned.ipa) · [候选版 Release](https://github.com/kevin3627713/session-camera/releases/tag/widgets-ios18-v0.3.3)。沿用原签名身份和包名映射覆盖安装，并保留小组件扩展。
