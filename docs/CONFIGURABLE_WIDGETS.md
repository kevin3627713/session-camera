# 借拍 0.3.7：可编辑样式、随机相册与后台照片中转

在 experiment/widget-direct-photos-ios18 分支继续开发，基于此前开发与 URL 派发研究代码。机主已确认 0.3.2 在 iOS 18.7.8 的照片组件正常显示。单张高清加载、系统建议取景及五种样式沿用 0.3.4；0.3.5 接入后台 Share 中转，点击系统照片选项时不经借拍主应用。诊断沿用显式编译开关，不出现在正常 IPA 中。历史调查见 [WIDGET_PHOTO_INVESTIGATION.md](WIDGET_PHOTO_INVESTIGATION.md)，诊断启用见 [WidgetDiagnostics](../native/WidgetDiagnostics/README.md)。同一个主应用包含原 WidgetKit 扩展和新增照片中转扩展。

0.3.6 修正中转接收端：NSExtensionItem.userInfo 可包含系统的标题、附件等附加字段，[Apple 文档](https://developer.apple.com/documentation/foundation/nsextensionitem/userinfo)明确描述了这一行为。旧 input.count == 3 会误拒绝这种请求。现在只逐项验证照片 ID、完整云标识和请求 UUID，忽略额外元数据，保留权限、隐藏状态及双向映射校验。读取不到输入或只有系统占位数据时先等待后续回调；在原宿主回调完成后接收数据，并以同一个公共 extensionContext 去重。缺少必需字段时给出对应标识的错误。按机主要求，修复版本使用 phone_test 构建，不重复主屏 UI / 模拟器长流程，交付 IPA 真机验收。

机主已确认 0.3.6 的系统照片中转在未越狱 iOS 18.7.8 可用。0.3.7 针对大量照片文件夹的显示问题：生产时间线不再遍历、去重、排序文件夹所有照片 ID，也不生成与照片数等长的洗牌数组。只读取子相册数量，按照片数量加权定位一个候选，再从该相册按索引读取。每个子相册查询和候选读取都及时释放临时 PhotoKit 对象；不同时保留全部子相册的照片结果。

扩展缓存当前周期、照片 ID，按来源、独立编号、周期分别保存，最多 64 条。同周期重载先核对照片仍属于当前文件夹、仍可访问且非隐藏，之后复用选图，不重新统计全部子相册。下一周期按资产 ID 避免连续重复；随机候选均重复时，每个相册最多检查前两个位置寻找另一张，只有一张独特照片时仍可显示。相册及有限访问来源保留原来的去重洗牌。文件夹采用数量加权抽取，不承诺一轮内遍历所有独特照片；同一资产被多个子相册收录会增加抽中权重。没有截断文件夹照片范围。完整 ID 枚举只在明确启用的相册计数诊断和测试夹具中使用。

## 原生编辑小组件

上一版使用 StaticConfiguration，因此没有原生配置面板。本版四个现有 kind 均改为 AppIntentConfiguration，保留旧标识以支持原位升级。长按已有小组件 → 编辑小组件，或进入主屏编辑后轻点小组件，系统负责翻转动画和设置面板。

总共五种实际样式：透明相机、空白透明、磨砂相机、普通背景、随机相册照片。现有四种预设只是初始样式，任意一个都可以在编辑面板切换这五种样式。默认项“沿用当前预设”只沿用该入口的原始外观，不是第六种样式，因此旧空白版和普通版等会保持各自原来的默认内容。图库入口保留四个预设以兼容已放置的小组件。

| 样式 | 展示内容 | 额外设置 |
| --- | --- | --- |
| 透明相机 | 壁纸上的相机图标与借拍文字 | 点击行为 |
| 空白透明 | 透明空白区域 | 点击行为 |
| 磨砂相机 | 系统 Material 底上的相机图标与文字 | 点击行为 |
| 普通背景 | 普通系统底色上的相机图标与文字 | 点击行为 |
| 随机相册照片 | 所选相册或文件夹中的一张照片 | 来源、更换周期、独立编号、点击行为 |

描述符是按 kind 的全局声明，不能用于存储每个已放置小组件的个人设置。本版统一提供透明宿主，让各实例自己绘制颜色、Material 或照片。磨砂改用实例内部的系统 regularMaterial，不再将整个 kind 强制设为私有背景风格 2；这样同一预设的另一实例才能同时保持完全透明。材质在真实主屏幕上的表现需随设备验收。

## 点击不打开应用

默认“点击行为”为“不打开应用”。覆盖整个区域的 Button(intent:) 执行 openAppWhenRun=false 的无操作意图，接住点击；只移除 widgetURL 会仍然触发 iOS 默认启动主应用的行为。空白版也有完整区域的点击接收，不会依赖是否绘制图标。

在原生编辑面板里可以改成“打开借拍”，这时使用完整区域的启动链接。所有尺寸均关闭额外内容边距，避免边缘成为未覆盖的默认启动区域。原生长按编辑和拖动仍由系统处理。

0.3.5 的“在系统照片中打开”使用 Button / OpenWidgetPhoto 后台意图，参数固定为时间线当前显示的资产 ID 和该组件的独立编号。小组件在点击时做 PhotoKit 权限、非隐藏资产与双向云标识映射校验，通过私有 NSExtension 将资产 ID、完整云标识及随机请求标识传给内置 Share 扩展。Share 再独立校验同一资产与映射，通过 LSApplicationWorkspace 派发 photos-navigation://asset?cloud-identifier=…，随后完成扩展请求。全程不经过主应用或网页，不截短 PHCloudIdentifier.stringValue。

扩展标识从实际嵌入的 SessionPhotoBridge.appex/Info.plist 读取，支持重签工具独立改写标识；未新增 App Groups。成功回传必须匹配本次请求标识。完成、取消、中断与 15 秒超时均结束请求并释放回调，处理请求 UUID 晚于超时返回的情况。扩展缺失、资产不可访问或系统拒绝会在当前组件上显示简短提示；不会改开其他图片或启动借拍。提示按独立编号和资产隔离，旧请求不会覆盖新请求结果。失败提示在 90 秒后过期，消失时间仍受 WidgetKit 刷新调度约束。非照片样式和未加载图片的占位页仍不跳转。

重签时必须保留并签署 SessionWidgets.appex 与 SessionPhotoBridge.appex，沿用原 App 身份覆盖安装即可；已有 photos 点击设置沿用新行为，不需删掉小组件。中转扩展使用 FALSEPREDICATE，避免成为普通分享菜单入口。相机继续支持旧 sessioncamera://photos 链接，但新的组件按钮不产生该链接。引导式访问期间跨应用跳转仍由系统决定。默认点击仍是不打开应用。

## 不显示借拍界面的 URL 派发研究（2026-10-06）

实验保存在 `research/widget-direct-photos-url-ios18` 分支，基于 0.3.4 的开发分支创建。`native/WidgetURLProbe` 是独立测试宿主；Ruby 脚本在 build 目录生成自己的 Xcode 工程，实际运行桌面 WidgetKit 的 Button / AppIntent。它没有加入借拍的生产工程或 IPA，主应用、生产小组件、版本号和既有发行包均未改变。

普通 `Link` / `widgetURL` 由 WidgetKit 激活其所属应用，再把 URL 交给该应用。苹果的 [OpenURLIntent 文档](https://developer.apple.com/documentation/appintents/openurlintent) 明确只支持 universal link，不支持 `photos-navigation` 这样的自定义 scheme。[Apple DTS 的说明](https://developer.apple.com/forums/thread/762586) 与此一致。系统“照片”的小组件属于 Photos 应用，因此其默认激活路径不能证明第三方小组件也能直接打开 Photos。

用 HTTPS 页面中转可以把第一站改成浏览器，但它仍需要第二次请求打开 Photos，不能省去浏览器界面或保证没有确认提示。借拍内部的 WKWebView / 浏览器壳仍在借拍的进程和界面里，也不能解决启动借拍的问题。本次优先验证不依赖网页的本地路径。

[LiveContainer 的固定版本源码](https://github.com/LiveContainer/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/LaunchAppExtension/LaunchAppExtension.swift) 显示，其 AppIntent 先通过私有 NSExtension 启动自己的 Share 扩展，并在 NSExtensionItem.userInfo 中传递 URL；[Share 扩展](https://github.com/LiveContainer/LiveContainer/blob/4dbe0f9a626de801184a42c0be8d2cb105058e3d/ShareExtension/main.m) 再通过 LSApplicationWorkspace 派发。实验参考这一调用顺序，独立实现最小桥接，没有引入 LiveContainer 的 App Groups、UI 或客体应用加载代码。

[实际桌面实验 37482693075](https://github.com/kevin3627713/session-camera/actions/runs/37482693075) 在 iOS 18.6（22G86）、iPhone 16 Pro 模拟器中完成。测试先创建真实 PhotoKit 合成照片、取得完整云端标识并添加中尺寸桌面小组件，然后终止主应用。以下四个按钮均有 AppIntent 的实际执行日志，结果不是从普通应用宿主推断：

| 派发路径 | 系统结果 | 测试主应用 |
| --- | --- | --- |
| 小组件 AppIntent → openURL:withOptions:error: | 拒绝，LSApplicationWorkspaceErrorDomain / 115 | 未运行 |
| 小组件 AppIntent → openSensitiveURL:withOptions:error: | 拒绝，同样为 115 | 未运行 |
| 小组件 AppIntent → 私有 NSExtension → Share 扩展 → openURL:withOptions:error: | 接受；Photos 进入前台 | 全程未运行 |
| LiveActivityIntent → 主应用后台进程 → openURL:withOptions:error: | 拒绝，同样为 115 | 后台启动，无进入前台的生命周期日志 |

第三条路径实际记录到了 Share 扩展发现成功、请求启动、私有宿主回调收到输入、LSApplicationWorkspace 接受，以及 Photos 前台状态。初次截图是 Photos 的黑色启动过渡页，因此这一轮证明的是跨进程派发和未启动主应用，还不能证明指定图片完成显示。[验证数据](verification/widget-url-ios18.6.json) 明确保留这一限制。前面三次 CI 失败发生在安装配置或系统图库的 UI 自动化阶段，尚未调用派发接口，不计作接口失败。

后续 [37484808830](https://github.com/kevin3627713/session-camera/actions/runs/37484808830) 等待 Photos 的 Edit 按钮后已看到真实单张大图，但试验选择器误将模拟器自带的 2009 年旧照片当成“更早的红色测试图”。这一轮只计作进入单张照片页面，未计作合成目标成功。选择器在 a6a7e03 修正为明确匹配合成目标的唯一 creationDate。

最终 [37487201411](https://github.com/kevin3627713/session-camera/actions/runs/37487201411) 的四条路线全部实际执行，结果与上表一致。小组件解析目标的 creationDate 为 1700000000；Share 跳转后等待单张大图控件，再观察 15 秒，Photos 的 OneUpMainPagingView 对应“November 14, 2023 / 10:13 PM / Photo 7 of 8”，与红色目标一致。蓝色对照图为一分钟后的 10:14 PM，六张系统样片为其他日期。主应用状态仍为 notRunning，Share 路线期间没有主应用启动或进入前台的日志。因此当前证据已支持指定目标的页面定位，而不是只唤起 Photos。

这台新建模拟器的 Photos 同时弹出了系统“What's New in Photos / Continue”首次启动介绍页，[原始截图](verification/widget-url-ios18.6-share-onboarding.png) 被该页遮挡。无遮挡的目标像素还未人工验收；验证 JSON 将页面标识核对成功与像素未验收分别记录，不能将 CI 绿色状态理解为所有图片显示、签名或真机行为都已通过。

后台主应用路线使用 `LiveActivityIntent`，按照[苹果交互式小组件文档](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities) 强制在主应用进程执行，`openAppWhenRun=false` 使其不请求显示主界面。结果也说明：后台执行资格不等于打开另一个应用的资格。失败结论仅适用于本次调用和系统，不能推导所有私有调用组合都不可用。

以上是生产接入前的研究证据。0.3.5 现已独立接入同一 IPA 内的 Share `.appex`，无需单独安装另一个 App，也无需为了 URL 传递增加 App Groups。它会新增需要签名的 bundle / App ID；这与三个已安装 App 的限制是不同配额，见 [AltStore App IDs](https://faq.altstore.io/altstore-classic/app-ids)。自签工具必须保留并签署两个扩展；产品代码直接读取重签后的实际兄弟扩展标识。

产品代码保留权限、非隐藏资产和双向标识映射校验，只打开小组件当前显示的那张照片，失败不会静默改开图库或启动借拍。新增 native/WidgetPhotoBridgeTests 用实际主屏幕组件执行生产中转代码，关闭包含应用，使用独立改写的 Share 标识，核对冷启动 / 后台 Photos 的目标日期与时间，以及主应用保持 notRunning。机主未越狱 iOS 18.7.8 的自签行为仍需真机验收；模拟器使用临时合成照片和临时 TCC 授权，不等于免费账号真机签名验证。

原始研究 Share 回调为保留观察窗口没有实现请求收尾，仍单独保留用于复现；生产 IPA 使用 ios/SessionPhotoBridge 和 ios/SessionWidgets/PhotoBridgeClient，补齐上述生命周期处理。生产中转测试日志只在 WIDGET_BRIDGE_TEST 中编译，普通 IPA 明确检查不含该标记。

## 随机相册照片

1. 在借拍右上角锁图标 → 设置 → 照片小组件 → 权限与刷新，完成机主 Face ID / Touch ID / 设备密码验证。
2. 按系统设置说明允许照片访问。仅使用相机仍推荐有限访问；选择具名相册或文件夹需要完整访问。
3. 在主屏幕编辑小组件，把样式改为“随机相册照片”。
4. 选择相册、文件夹或已授权照片，填写更换间隔，选择这个小组件自己的独立编号。

有限权限下只能选择“已授权的照片”，因为 PhotoKit 不提供用户相册和文件夹目录。完整权限时提供自建相册、系统相册和文件夹；目录显示嵌套路径以区分同名相册。选择文件夹会递归包含其中所有子文件夹的相册，去除重复相册路径，按照片 ID 避免相邻重复。隐藏照片、视频和所选来源以外的照片不加入随机集合。来源被删除或不可访问时显示提示，不会擅自换成其他相册。

周期可填写 5～10080 分钟，默认 60 分钟。0.3.2 每次仅准备当前一张照片，并在该实例的下一周期边界请求更新；快照也只请求一张图片。系统对小组件更新有预算和调度，时间可能延后，短周期尤为明显。

0.3.0 使用 opportunistic 请求，收到第一个 UIImage 就取消请求，没有检查 PHImageResultIsDegradedKey。PhotoKit 可能先交付低清预览，再交付清晰图片；旧代码将后者取消。0.3.1 使用 highQualityFormat / exact，并显式忽略低清回调。按三倍显示点数请求图片，最长边上限 1200 像素，然后按组件宽高裁剪、编码为 JPEG，兼顾屏幕清晰度与扩展内存；原照片自身的分辨率仍限制可得到的细节。

0.3.2 保留高清回调、三倍点数和最长边 1200 像素；请求阶段指定中心裁剪，最终渲染器使用标准动态范围，缓存尺寸检查改用 ImageIO 元数据。当前图片最多等待八秒；没有未来图片预加载。失败会显示提示并请求五分钟后重试。iCloud 原图仍允许通过系统 PhotoKit 下载，刷新时间受系统约束。

0.3.4 在当前照片上调用 PHAsset.suggestedCropForTargetSize:，与 iOS 18.2 系统 PhotosReliveWidget 的取图路径一致。Objective-C 桥接先核对 CGRect / CGSize 结构签名，再调用并捕获异常。返回原图像素坐标，按源图尺寸归一化后只用于平移现有 aspect-fill 窗口，窗口宽高保持不变。无接口、签名不兼容、异常或越界 / 空结果均回到居中裁剪；没有 Vision 分析模型或像素级预分析。最终裁剪继续由 PhotoKit.normalizedCropRect / exact 执行，保持高清加载策略。

缓存键加入算法版本和实际裁剪位置，防止继续使用旧居中图，也能在系统推荐位置变化但照片编辑时间没有变化时更新。系统尚未保存有效分析信号的照片，推荐框可能仍居中；接口成功本身不能证明识别了某个主体。与普通应用宿主的模拟器结果分开，实际主体位置和扩展表现仍需在 iOS 18.7.8 真机验收。

只缓存最终高清 JPEG，保存在扩展自己的 Caches 目录，按照片 ID、修改时间和像素尺寸区分；不同组件可以复用同一张图的编码数据，各自的随机序列仍独立。最多保留 32 个文件、24 MiB，使用首次解锁后的文件保护。删除再添加小组件可复用尚未被系统清理的缓存，但需要重新选择来源、样式和编号；不需要反复删除组件来刷新。每次读取缓存前先检查当前权限和资产是否仍可访问，来源被删除时不会改读其他来源。

每个实例的来源、周期、点击行为和独立编号由自己的配置保存。独立编号由动态实体查询自动提供新 UUID；复制已有小组件可能复制其全部参数，这时在独立编号中选择新编号。不同编号有不同的随机洗牌和周期相位，没有全局“当前照片”。两张组件偶尔显示同一张照片是正常随机结果；只有一张可用照片时必然重复。

同一周期内重载不会因为轻点组件就重新抽图；有多张图片时避免连续两次重复。相册的洗牌跨轮边界也进行处理；文件夹使用上述数量加权候选与少量选图缓存。

## 隐私范围

新增照片枚举仅在小组件扩展内执行，来源由用户在主屏编辑面板选择。相机内 SessionStore / SessionGallery 仍只使用本次创建的资产 ID 和会话内列表，没有导入已有照片。小组件点击默认不打开应用；仅明确选择“在系统照片中打开”时，主应用核对该张照片并转交系统照片。

照片小组件会按你的选择在主屏幕显示照片；借出整部手机前仍应开启引导式访问。机主设置只管理授权和刷新，不展示图库或相册目录。无需 App Groups，不在主应用与扩展间共享图库文件。

## 验证

0.3.4 的[完整构建 37422754306](https://github.com/kevin3627713/session-camera/actions/runs/37422754306) 和[照片专项 37422754103](https://github.com/kevin3627713/session-camera/actions/runs/37422754103) 均通过，构建源码提交为 c0fae61df2c9d55f168cb17914306be3ea16e0a4。普通模式 [45 项检查](verification/widget-photos-ios18.6-v0.3.4.json)、诊断模式 [49 项检查](verification/widget-photo-diagnostics-ios18.6-v0.3.4.json) 全部通过。真实 PHAsset 的私有选择器可调用并返回有效像素矩形，无需额外 entitlement；保持窗口宽高、裁剪位置变化时缓存失效、显示资产与点击目标一致、真实云 / 本地标识双向映射、完整字符串编码与缺失 / 隐藏资产拒绝跳转均已验证。

测试照片是新建合成图，系统推荐返回整幅 1800×1800 图像，因此这些结果证明调用兼容性，不证明已有主体识别。接口单次模拟器计时也不是 iPhone 能耗或扩展性能基准。24 项共享 Swift 测试、18 项描述符检查、9 项结构桥接检查和 2 项 Flutter 测试通过；[相机原生回归](https://github.com/kevin3627713/session-camera/actions/runs/37421805192) 的 [4 项 XCTest](verification/camera-session-ios18-v0.3.4.json) 通过，其生产源码与最终构建一致。签名后真机上系统照片的实际选中位置及主体取景仍需验收。

共享 WidgetCore 测试验证不同实例的随机序列和相位、同周期重载稳定、跨轮无相邻重复、周期与来源范围、异常输入，以及嵌套文件夹去重和循环处理。实际编译和 IPA 检查还要求 App Intents 元数据存在，避免“有代码但编辑入口未注册”。

独立 iOS 18 模拟器测试宿主使用真实 PhotoKit 创建合成图片、两个相册和嵌套文件夹，调用生产 PhotoLibrarySource、实体查询、计划和时间线源码。除读取范围、隐藏照片排除、去重和实体恢复外，0.3.1 增加大尺寸细线纹理图片，检查实际 JPEG 像素尺寸和细节对比度，避免仅验证“能解码”而漏掉模糊图片；另模拟先低清、后高清以及迟到回调，验证最终采用高清结果且只完成一次。缓存复用、尺寸隔离、缺失资产不使用缓存、失败提示和重试时间线也有回归检查。缺失资产用真实缓存文件和不存在的资产 ID 验证，不调用需要用户确认的系统删除接口。测试宿主和合成图不会加入发行 IPA。

0.3.3 的 [照片专项 37323039643](https://github.com/kevin3627713/session-camera/actions/runs/37323039643) 分别验证两种模式：普通模式 [32 项检查](verification/widget-photos-ios18.6-v0.3.3.json)、诊断模式 [36 项检查](verification/widget-photo-diagnostics-ios18.6-v0.3.3.json) 全部通过，系统为 iOS 18.6；各报告明确记录 diagnosticsEnabled。0.3.2 的最终真机显示已由机主在 iOS 18.7.8 确认正常。

0.3.0 的完整构建 [37299084781](https://github.com/kevin3627713/session-camera/actions/runs/37299084781) 已通过，代码提交为 a38d7035c92a346cfc9181deee6207d13bdca28f。通过 19 项 Swift 测试、18 项描述符检查、2 项 Flutter 测试和 13 项 PhotoKit 宿主检查，但当时没有验证图片细节和低清回调，因此未覆盖本次真机发现的问题。

0.3.1 的完整构建 [37306257118](https://github.com/kevin3627713/session-camera/actions/runs/37306257118) 与 [照片专项测试 37306256886](https://github.com/kevin3627713/session-camera/actions/runs/37306256886) 均已通过，代码提交为 c0e3f7c29715005e0c63e38982eaa01c13c1e955。保留的 19 项 Swift 测试、18 项描述符检查和 2 项 Flutter 测试通过，PhotoKit / 时间线检查增加到 30 项，见 [widget-photos-ios18.6.json](verification/widget-photos-ios18.6.json)。真实高分辨率合成图得到 480×480 与 1080×1140 像素 JPEG，细线纹理对比度通过阈值；结果不是仅将低清图放大。高清图片替换低清回调、重载缓存、缺失资产拒绝读取缓存和失败重试策略均执行了生产源码。

最终 0.3.1 IPA 为 6,632,637 字节，SHA-256：98ac7f90f757547b89586aec6c0f461e750945c5a54f852ff81984c5817ae9e3。主应用与扩展均为 0.3.1 / build 6，仍只有一个 arm64 扩展；元数据中的五种样式、配置字段与默认点击不打开均验证通过。

0.3.2 候选版的完整构建 [37311849551](https://github.com/kevin3627713/session-camera/actions/runs/37311849551) 和 [照片专项 37311849274](https://github.com/kevin3627713/session-camera/actions/runs/37311849274) 已通过，生产代码提交为 e4443ba9a13b2281becdbe0a30b8b090d5727778。PhotoKit / 时间线宿主检查为 36 项，包含单图请求和下次边界、请求裁剪以及三种诊断分支。480×480 与 1080×1140 像素和细节检查继续通过。结果原样保存在 [widget-photos-ios18.6.json](verification/widget-photos-ios18.6.json)，没有执行系统时间线归档或桌面渲染。IPA 为 6,644,485 字节，SHA-256：d701fbc595cfbad5c89a1b233ed5679707a32adf904c237c5dca8c78d5bf0abe。

真实测试暴露了 iOS 18.6 的按标识查询 PHCollectionList 接口异常。本版使用明确的 .folder 类型查询建立目录索引，递归时仅按选定 ID 读取。测试环境为合成数据宿主修正模拟器命令行授权写入的旧 auth_version；这段初始化只在 CI 脚本，不进入应用。主应用和扩展仍使用系统 PhotoKit 授权。

0.3.3 普通 IPA 检查要求 App Intents 元数据只有五个生产配置参数，没有照片排查参数或诊断枚举；二进制没有诊断采样器、日志类别或测试图字符串。显式诊断构建额外注册默认关闭的照片排查，仍是五种实际样式。两种模式均保留两个实体查询、默认点击 none、间隔默认 60 分钟和无操作意图 openAppWhenRun=false。分发包只有一个 arm64 扩展，版本与主应用一致，未包含测试宿主或合成相册。

上述 PhotoKit 验证使用普通应用宿主，未覆盖系统托管 WidgetKit 归档/渲染及真机扩展内存额度。0.3.1 真机反馈已经说明该验证不足。原生主屏翻转、旧小组件迁移、透明 / 材质显示、点击区域、扩展的真机权限继承、图片显示及真实调度时间最终仍需在 iPhone 验收。

参考：[Apple 可配置小组件](https://developer.apple.com/documentation/widgetkit/making-a-configurable-widget)、[交互式小组件](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities)、[刷新调度](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)、[有限照片权限](https://developer.apple.com/documentation/photokit/delivering-an-enhanced-privacy-experience-in-your-photos-app)、[低清回调标记](https://developer.apple.com/documentation/photos/phimageresultisdegradedkey)、[高清请求](https://developer.apple.com/documentation/photos/phimagerequestoptionsdeliverymode/highqualityformat)。

0.3.3 的相机会话回归由 [iOS 18 独立运行](https://github.com/kevin3627713/session-camera/actions/runs/37327457989) 验证，四项 XCTest 全部通过。更新后的安装包、验证范围与前一次宿主任务超时说明见 [发行记录](WIDGET_RELEASE_NOTES.md)。
