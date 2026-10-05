# iOS 18 照片小组件占位问题调查

2026-10-05，分支 `experiment/transparent-widgets-ios18`。

机主在 iOS 18.7.8、未越狱、自签名安装 0.3.1 后确认：小、中、大尺寸均一直显示系统灰色骨架占位，少量照片的相册也发生，没有开启 iCloud 优化储存空间。截图未显示应用自己的权限、空来源或加载失败文字。这说明还需要检查提供器是否返回，以及时间线归档、渲染和扩展进程是否成功；截图本身不能证明是 Jetsam。

## 资料与证据强度

| 原始资料 | 内容与适用范围 |
| --- | --- |
| [Stack Overflow：Photo Asset Dimensions](https://stackoverflow.com/questions/64094473/ios-14-widgetkit-memory-issue-photo-asset-dimensions) | 开发者在照片组件使用屏幕三倍尺寸请求，遇到 30 MB 限制；缩小请求后可显示，但模糊。aspectFill 返回的像素尺寸也可能比目标矩形大。这是 iOS 14 的亲历报告，不能直接证明 18.7.8 的原因。 |
| [Apple 开发者论坛：小组件 EXC_RESOURCE](https://developer.apple.com/forums/thread/713561) | 开发者记录内存超限和骨架占位；讨论指出 JPEG 压缩和视图 frame 没有减少原始像素解码成本。参与者建议提前缩小图片。这是论坛讨论，不是 Apple 对固定内存额度的承诺。 |
| [Apple 开发者论坛：相册轮播占位](https://developer.apple.com/forums/thread/842805) | iOS 17/18 的相册轮播作者报告扩展超限后停在占位。作者虽尝试降采样和减少条目，仍有间歇失败；截至调查时没有回复，不能把提问中的 App Group 方案当成官方建议。 |
| [Apple：扩展性能](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionCreation.html) | 官方说明扩展内存限制显著低于前台应用，系统可主动终止；应实际调试扩展进程。普通应用宿主运行源码的检查不等价于桌面组件验收。 |
| [Apple WWDC：iOS Memory Deep Dive](https://developer.apple.com/videos/play/wwdc2018/416/) | 图片内存主要与像素尺寸和像素格式有关。将 UIImage 画进小矩形仍可能先解码大图；ImageIO 从文件降采样可减少这种峰值。 |
| [Apple：normalizedCropRect](https://developer.apple.com/documentation/photos/phimagerequestoptions/normalizedcroprect) | PhotoKit 支持在请求阶段指定归一化裁剪矩形，要求 resizeMode 为 exact。裁剪能提出有界请求，但仍需检查实际回调尺寸和进程内存。 |
| [Apple：扩展共享容器](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html) | 主应用预生成图片、扩展读共享文件需要正确配置和签名 App Groups。当前自签名模板没有该能力，不能用主应用的普通 Caches 路径替代共享容器。 |

## 对照 0.3.1 代码

`CameraWidgetProvider.snapshot` 调用整个 `timeline`；提供器会请求最多六张高清照片，并把 JPEG Data 放进六个时间点。小组件视图再创建 UIImage。PhotoKit 回调、裁剪渲染器、JPEG 编码和归档中的图像资源都可能产生额外缓冲区。

1080 × 1140 像素按每像素四字节计算，单张位图约 4.70 MiB；六张约 28.18 MiB。这个算式只是像素成本估算，不表示所有缓冲一定同时存在，也不包括框架基础内存。高精度格式、源图比例和多个组件请求可能增加峰值。磁盘缓存 24 MiB 上限没有限制进程总内存。

0.3.1 已正确忽略低清回调并检查当前权限；相册范围、隐藏照片排除、文件夹递归也通过宿主检查。尚未找到依据说明 PhotoKit 在所有 WidgetKit 扩展中都禁止读取相册。需要在真实扩展中验证权限状态，不能因为主应用获批就直接断言扩展也已获得访问。

## 0.3.2 调整与诊断

- 时间线和快照每次只准备当前一张照片，只计算下一个切换边界，不提前加载未来图片。清晰度继续使用三倍点数、最长边 1200 像素。
- PhotoKit 请求加入中心裁剪矩形；最终渲染器显式使用标准动态范围。缓存尺寸用 ImageIO 读取元数据验证，避免为检查尺寸创建 UIImage。
- 系统日志记录提供器开始、权限检查、相册查询、请求开始、实际回调尺寸/位深、时间线返回及视图图片准备阶段的进程 phys_footprint。日志没有资产 ID、相册名称和图片内容。阶段采样不是连续峰值测量，也不能替代 Jetsam 报告。
- 在随机照片样式中增加“照片排查”，默认关闭；这是诊断选项，五种样式不变。

每次只提供当前一张照片后，需要系统在下个边界重新请求时间线。[WidgetKit 刷新由系统预算与调度决定](https://developer.apple.com/documentation/widgetkit/keeping-a-widget-up-to-date)，因此可能延后；此版本用更少的预加载换取更低的工作量，没有承诺每个短周期都准时切换。

| 编辑小组件中的照片排查 | 实际执行 | 能判断的范围 |
| --- | --- | --- |
| 1 · 测试图与文字 | 小型红蓝测试图，同一个照片视图、透明宿主和不打开应用的按钮；不调用照片库 | 显示后说明这一小型图片的真实 WidgetKit 绘制路径可用。若仍停在骨架，应先查配置、扩展启动或归档，不能归咎于相册数量。 |
| 2 · 只读取相册 | 检查权限、枚举所选来源，显示可用照片数和当时内存；不请求图片 | 若 1 成功而 2 不返回，需要查权限/相册查询阶段。只显示所选来源的统计，不显示相册名称和照片。 |
| 3 · 请求照片但只显示结果 | 请求当前照片，显示最终像素尺寸、JPEG 大小和当时内存；不把照片交给视图 | 若 2 成功而 3 不返回，需要查 PhotoKit/裁剪/编码；若 3 成功而正常照片失败，重点检查大图片归档与渲染。 |

先在现有组件中选随机照片样式，保留来源和编号，按 1 → 2 → 3 测试，最后关闭排查恢复照片。切换配置会请求新的内容，但仍可能受系统调度影响。不要先反复删除组件，以免丢失已经选好的参数。

如需要确认系统是否终止扩展，可在 iPhone 设置 → 隐私与安全性 → 分析与改进 → 分析数据，寻找相同时刻含 `SessionWidgets` 或实际重签扩展名称的 JetsamEvent / 崩溃记录。记录中的终止原因比单纯观察灰色占位更可靠。该步骤只有仍失败时才需要。

## 验证范围

0.3.1 的 30 项检查运行在普通模拟器应用中，证明生产 PhotoKit/时间线源码在该宿主可工作，但没有覆盖 SpringBoard 托管、WidgetKit 图像归档或真机扩展内存限制。不能据此宣布真机组件修好。

0.3.2 增加只请求一张图片、下一周期边界、请求裁剪和三种诊断分支检查。IPA 检查要求诊断配置真正进入 App Intents 元数据，默认关闭，仍恰好一个小组件扩展。编译与宿主检查通过后也只能作为候选版；真实 iOS 18.7.8 的最终显示需通过组件自身的诊断及机主反馈验证。
