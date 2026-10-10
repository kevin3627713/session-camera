# 借拍 0.3.8：可选读取隐藏照片

已切回 experiment/widget-direct-photos-ios18，在 0.3.7 的文件夹优化基础上增加每个照片小组件自己的“读取隐藏照片”开关，默认关闭。长按小组件 → 编辑小组件 → 样式“随机相册照片”即可设置。开启后来源列表增加系统“已隐藏”相册，所选相册或文件夹允许纳入系统可访问的隐藏照片，仍排除视频和来源之外的资产。

开关贯穿 PhotoKit 查询、文件夹候选选取、高清图片读取、图片缓存访问校验、点击后台意图及 Share 中转。文件夹选图缓存区分开启 / 关闭；关闭后重新验证资产，不沿用隐藏图片缓存。旧时间线或未携带该设置的中转请求默认关闭，传入非布尔字段时拒绝请求。

苹果限制：隐藏相册启用 Face ID / 密码验证时，系统可能不向 PhotoKit 返回其中的照片，即使设置 includeHiddenAssets=true。这个开关只控制借拍是否请求这些照片，不取消系统身份验证。实际行为见 [Apple isHidden 文档](https://developer.apple.com/documentation/photos/phasset/ishidden)。机主可自行调整系统照片的验证设置后测试；应用不改写该系统设置。

版本 0.3.8 / build 13。正常 IPA 保持两个内置扩展，默认不包含诊断和测试日志，继续采用当前的高清加载、焦点取景与后台打开系统照片。新增验证覆盖系统允许访问的真实隐藏图片、开关关闭后的缓存排除、隐藏来源目录、时间线传递，以及中转布尔字段的安全归档。

---

# 借拍 0.3.7：降低大量照片文件夹的刷新开销

针对机主反馈“相册照片再多正常，文件夹照片很多时停留占位”的问题，替换文件夹取图策略。旧流程每次刷新递归枚举所有照片 ID、合并去重、排序，并为随机计划生成完整洗牌；新流程只统计子相册数量，按数量加权定位候选，再按索引读取需要的照片。不设置照片数量上限，不同时保留所有子相册的照片查询结果，按相册与候选使用 autoreleasepool 释放临时对象。

各小组件按来源、独立编号、更换周期缓存一条当前选图。同周期重载重新核对照片权限、隐藏状态和当前文件夹归属后复用；下一周期避免上一张照片，即便它同时位于多个子相册。随机候选都重复时，用每个子相册至多两个索引寻找不同照片；只有一张独特照片时正常继续显示。相册和有限照片来源保留原有洗牌，文件夹采用数量加权抽取，重复收录可能改变抽中权重。

版本 0.3.7 / build 12。高清请求、系统建议取景、点击直接定位系统照片、相机会话和五种样式沿用当前实现。机主已确认 0.3.6 的照片中转在未越狱 iOS 18.7.8 可用。本次文件夹修复仍需在出现问题的大文件夹上真机验收。共享算法回归包括六千万个虚拟位置仅读取一个候选、重复收录、空相册、数量权重和周期一致性；PhotoKit 宿主补充实际嵌套文件夹选图、同周期复用与跨周期变化检查。测试和诊断不加入正常 IPA。

源码 fbd6e006af31f8213841c2e989be36850a642401 的[IPA 构建](https://github.com/kevin3627713/session-camera/actions/runs/37516954563)和[照片专项](https://github.com/kevin3627713/session-camera/actions/runs/37516960584)通过。普通模式 49 项实际 PhotoKit 检查通过，诊断模式也通过；[验证记录](verification/widget-folder-photos-ios18.6-v0.3.7.json)区分六千万虚拟位置算法回归与小型真实嵌套图库夹具，不将其描述为真机大图库性能验证。正常包已再次检查两个 arm64 扩展、统一版本、App Intents 元数据和测试代码排除。

[下载 0.3.7 未签名 IPA](https://github.com/kevin3627713/session-camera/releases/download/widgets-ios18-v0.3.7/session-camera-unsigned.ipa) · [发行页](https://github.com/kevin3627713/session-camera/releases/tag/widgets-ios18-v0.3.7)。安装包 6,708,455 字节，SHA-256：eb849923436bb4acb61b5723cbf9261d7af40f937484a1a162b015466333efa6。主应用及两个扩展均为 0.3.7 / build 12。沿用原签名身份和包名映射覆盖安装，并保留两个扩展，无需删除已有小组件。

---

# 借拍 0.3.6：修复照片中转请求校验

修复一处会导致“照片中转请求无效”的过严校验：接收端不再要求 NSExtensionItem.userInfo 恰好三个字段，改为逐项核对照片 ID、完整云标识和请求 UUID。系统附加的标题、附件等元数据不影响这三个字段的有效性，见 [Apple userInfo 文档](https://developer.apple.com/documentation/foundation/nsextensionitem/userinfo)。用真实 NSExtensionItem 设置标题即可复现字段数量超过三的情况。

输入为空或仅有系统占位字段时，不提前占用请求；原宿主回调完成后再处理可用数据。私有实现对象和界面入口按同一个公共 extensionContext 去重，避免同一请求被处理两次。输入取不可变快照。必需标识不合法时提供更具体的错误，照片权限、隐藏状态、完整标识双向映射和成功回传核对继续保留。

版本 0.3.6 / build 11。仍用同一个借拍 App 和两个内置扩展；沿用之前的签名身份与包名映射覆盖安装，保留并签署 SessionWidgets.appex、SessionPhotoBridge.appex。小组件设置与高清图片缓存继续沿用。按机主要求，只做参数回归和编译 / 包检查，不运行主屏 UI 或长时间模拟器验证，交付真机测试。

构建源码 14f153ad898325e4e24988cb2aa17e3202c2d40d，[真机测试包构建](https://github.com/kevin3627713/session-camera/actions/runs/37505511078)通过。六项[请求参数回归](verification/photo-bridge-payload-v0.3.6.json)使用真实 Foundation 对象，标题加入后 userInfo 实际有四个字段；加入标题及安全归档还原均保留三个必需标识，缺少照片 / 云标识或 UUID 无效仍被拒绝。24 项共享 Swift、18 项描述符、9 项裁剪桥接及 2 项 Flutter 检查通过；按要求跳过托管小组件 / 模拟器长流程。真实中转、签名与最终照片定位继续由机主 iOS 18.7.8 验收。

[下载 0.3.6 未签名 IPA](https://github.com/kevin3627713/session-camera/releases/download/widgets-ios18-v0.3.6/session-camera-unsigned.ipa) · [候选发行页](https://github.com/kevin3627713/session-camera/releases/tag/widgets-ios18-v0.3.6)。安装包 6,689,820 字节，SHA-256：3374a7f5364cc5a226eb76414822cd1211d0d0e4a4ecedbeb97d4f5b6e020eb8。主应用及两个扩展版本均为 0.3.6 / build 11。

---

# 借拍 0.3.5：从小组件直接打开系统照片

“在系统照片中打开”改为小组件的后台 AppIntent，通过 IPA 内的 Share 扩展派发系统照片链接。借拍主应用不参与此路径，也不需要浏览器中转。已有小组件选中的 photos 点击行为会沿用新实现；五种样式、相册 / 文件夹、独立随机序列、间隔与默认不打开应用继续保留。

只传递当前显示照片的资产 ID、完整云标识与随机请求标识。小组件和中转扩展分别核对照片权限、非隐藏资产与双向标识映射。成功完成扩展请求，取消、中断与 15 秒超时会释放回调；旧请求 UUID 晚到仍可取消。失败时在当前照片组件显示简短提示，不改开其他照片，不启动借拍作为替代。提示按组件编号和当前资产隔离。

版本 0.3.5 / build 10。相机 App 和原 WidgetKit 扩展保持原标识，新增 SessionPhotoBridge.appex，仍打包在同一个借拍 IPA，不需增加一个独立安装的 App。签名工具须保留并签署 SessionWidgets.appex、SessionPhotoBridge.appex；沿用之前的签名身份和包名映射覆盖安装。中转根据嵌入扩展的实际 Info.plist 识别重签后的标识，不依赖硬编码后缀；不增加 App Groups。中转扩展不作为普通分享菜单入口展示。

高清加载和 PHAsset.suggestedCropForTargetSize: 建议取景沿用 0.3.4，只移动窗口，保留放大程度。切后台继续保留同一相机会话。普通 IPA 不编译照片诊断、桥接测试日志或合成测试图。

真机验收：覆盖升级后长按照片小组件 → 编辑小组件 → 点击行为选择“在系统照片中打开”，关闭借拍，再点击图片；检查直接进入系统照片、所选照片与组件显示一致，借拍没有前台闪现。再从照片返回主屏重复点击，检查已在后台的 Photos。默认不打开应用和打开借拍选项照常使用。iOS 18.7.8 的免费账号签名、私有接口兼容和实际主屏显示仍以真机结果为准。

安装包来自源码 4d51d18e841e5442ff03057c62940f9d12c76073 的[完整构建](https://github.com/kevin3627713/session-camera/actions/runs/37501492244)。24 项共享 Swift 测试、18 项透明描述符检查、9 项裁剪桥接检查、2 项 Flutter 测试，以及普通版 / 诊断版编译和意图元数据检查通过。[照片专项](https://github.com/kevin3627713/session-camera/actions/runs/37501492364)普通模式 [45 项](verification/widget-photos-ios18.6-v0.3.5.json)、诊断模式 [49 项](verification/widget-photo-diagnostics-ios18.6-v0.3.5.json)均通过。本地重新检查了下载成品的 ZIP、两个 arm64 扩展、版本、权限、后台意图和调试代码排除。

生产桥接的实际主屏自动化尚未验证通过：首次运行在系统图库找不到测试小组件，未调用跳转；追加注册日志的运行也未通过。机主要求直接交付安装包，不继续复杂自动化验证。此前独立研究已有 iOS 18.6 的 Share 派发与主应用不运行证据，见[研究记录](CONFIGURABLE_WIDGETS.md)。本发行是供 iOS 18.7.8 自签真机测试的候选版，不将编译或普通 PhotoKit 宿主测试当成生产桥接的真机验证。

[下载 0.3.5 未签名 IPA](https://github.com/kevin3627713/session-camera/releases/download/widgets-ios18-v0.3.5/session-camera-unsigned.ipa) · [候选发行页](https://github.com/kevin3627713/session-camera/releases/tag/widgets-ios18-v0.3.5)。安装包 6,689,239 字节，SHA-256：e0220e434a51b81797867e3d800fafb75cbe923e22aaa2e3e76ef0d008c39227。主应用及两个扩展版本均为 0.3.5 / build 10。

---

# 借拍 0.3.4：系统建议取景与照片跳转

本版在当前照片上调用 PHAsset.suggestedCropForTargetSize:，与 iOS 18.2 系统 PhotosReliveWidget 的取图路径一致。桥接核对 CGRect / CGSize 签名后调用，并捕获 Objective-C 异常；返回原图像素坐标。只采用推荐位置来平移原有 aspect-fill 窗口，保持窗口宽高与放大程度不变。接口不可用或返回异常、空、越界数据时回到居中取景。系统没有有效分析信号时，成功返回的建议也可能居中。

保留单张高清照片、highQualityFormat / exact、三倍点数、最长边 1200 像素、SDR JPEG、八秒请求超时和失败五分钟重试。没有加入 Vision 分析模型。缓存键包括算法版本和实际裁剪位置，旧居中图不会覆盖新结果。当前区域的小数变化经过六位精度归一后区分缓存，文件上限仍是 32 / 24 MiB。

点击行为有三个选项：不打开应用（默认）、打开借拍、在系统照片中打开。照片链接对应时间线当前显示的资产，经借拍转交；只在点击时使用 PhotoKit 云标识映射，并核对反向映射、权限和隐藏状态，完整 PHCloudIdentifier.stringValue 编码到 photos-navigation://asset?cloud-identifier=…，不截为 UUID。失败会提示，不改开其他图片。WidgetKit 会先启动所属应用，转交可能短暂经过借拍；引导式访问或自动开启它的快捷指令可能阻止跨应用转交。

版本 0.3.4 / build 9，保留同一主应用和扩展 ID、一个扩展、五种样式和原生编辑配置，不增加 App Groups。相机预览仍只显示当前进程拍摄的内容，切后台保留同一会话。普通 IPA 不编译保留的诊断代码。

验证已完成：构建源码为 c0fae61df2c9d55f168cb17914306be3ea16e0a4，[完整构建](https://github.com/kevin3627713/session-camera/actions/runs/37422754306) 与[照片专项](https://github.com/kevin3627713/session-camera/actions/runs/37422754103) 均通过。普通模式 [45 项](verification/widget-photos-ios18.6-v0.3.4.json)、诊断模式 [49 项](verification/widget-photo-diagnostics-ios18.6-v0.3.4.json) PhotoKit / 时间线检查，24 项共享 Swift 测试、18 项描述符检查、9 项结构桥接检查、2 项 Flutter 测试通过。[相机原生回归](https://github.com/kevin3627713/session-camera/actions/runs/37421805192) 的 [4 项 XCTest](verification/camera-session-ios18-v0.3.4.json) 通过，其生产源码与最终构建一致。

普通应用宿主在 iOS 18.6 调用真实 PHAsset 得到有效矩形，不需额外 entitlement；云标识双向映射、编码与高清回归通过。新建合成测试照片的推荐框是整幅图，不证明识别了主体；单次模拟器计时也不用于推断真机能耗。iOS 18.7.8 真机的主体位置、系统照片实际选中位置、主屏组件内存和能耗需分别验收。

[下载未签名 IPA](https://github.com/kevin3627713/session-camera/releases/download/widgets-ios18-v0.3.4/session-camera-unsigned.ipa) · [候选发行页](https://github.com/kevin3627713/session-camera/releases/tag/widgets-ios18-v0.3.4)。安装包为 6,645,579 字节，SHA-256：9e7da0871de467dd1c1680e4618d6d7528588dbf87fe7c5382661b9d61cdd1de。主应用与扩展版本均为 0.3.4 / build 9；重新签名时保留 SessionWidgets.appex，用相同签名身份覆盖升级。编辑元数据仍是五个生产参数，点击枚举为 none / camera / photos；普通 IPA 不包含诊断代码、测试宿主或分析模型。

参考：[iOS 18.2 系统照片小组件实现](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/main/private/var/staged_system_apps/Photos.app/PlugIns/PhotosReliveWidget.appex/PhotosReliveWidget.m)、[公开裁剪取图接口](https://developer.apple.com/documentation/photos/phimagerequestoptions/normalizedcroprect)。

---

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
