# 照片跳转诊断 0.1.3

独立 iPhone App，Bundle ID `com.kevin3627713.photosnavigationprobe`，内置中转扩展 `.share`，最低 iOS 18.0。工程和编译流程独立于借拍 Runner；不会将诊断界面或代码加入借拍 IPA。源代码保存在 `research/photos-album-navigation-probe-ios18` 分支。

## 当前结果（2026-10-08）

0.1.2 的 C / 方式 6、7 已完成真机测试。照片与相册 UUID 解析正确，主应用派发时为 active，中转 hook 正常。两项均 accepted=false：外层 FBSOpenApplicationServiceErrorDomain / 4（InvalidRequest），底层 FBSOpenApplicationErrorDomain / 3（Security），明确原因 `Request is not trusted.`。当前直接启动实现被系统信任检查拒绝；不再要求重复这两项，也不将其接入借拍生产小组件。不能据此认定所有私有路径绝对不可用或指定某个 entitlement 缺失。

系统快捷指令编辑器内的 C 链接已由机主确认成功，保留指定相册。随后，外部 `shortcuts://run-shortcut` 动态 text 输入也成功：机主观察到快捷指令界面约 0.5 秒加载，然后在目标相册内打开照片。这是机主的时间估计。机主随后确认系统快捷指令小组件能够直接进入照片，或仅显示进度提示，没有完整快捷指令界面；借拍小组件仍未接入。0.1.3 增加方式 8 / 9，验证普通自签主应用与自有后台中转能否调用同一父类执行器；操作见[发行说明](RELEASE_NOTES.md)，机制与权限边界见[后台执行调查](../../docs/SHORTCUTS_BACKGROUND_EXECUTION.md)。真实目标标识仅用于机主本机的测试链接；仓库报告保留归纳结果。

0.1.3 / build 4 的 [构建 37664186145](https://github.com/kevin3627713/session-camera/actions/runs/37664186145) 已通过，源码 `d694be0ed5fb9d4fd257d556db1be4528d48bcfa`。9 项 URL 检查、主应用与扩展编译和 IPA 结构检查完成。IPA 为 247,035 字节，SHA-256 `ab7cc0978e7e5e0450e9b8c1ca14faf85b9ca02aa79e27352e77decb35ad3d5e`；下载后的文件与 CI 哈希一致。[下载 IPA](https://github.com/kevin3627713/session-camera/releases/download/photos-navigation-probe-v0.1.3/photos-navigation-probe-unsigned.ipa)。方式 8 / 9 仍待机主真机测试。

## 外部快捷指令中转测试（无需新 IPA）

1. 在系统快捷指令 App 中复制之前成功的快捷指令，将副本准确命名为“借拍相册跳转”。
2. 保留两个动作“URL → 打开 URL”。清空第一个 URL 动作里的固定照片链接，轻点文本栏，在键盘上方变量条中选择“快捷指令输入”（必要时左右滑动变量条，或通过“选择变量”选取）。字段中应只有一个蓝色变量记号；不要输入文字“快捷指令输入”。
3. 第二个“打开 URL”继续使用前一个 URL 动作的输出，保存后退出编辑器。
4. 从 Safari 地址栏打开测试链接：`shortcuts://run-shortcut?name=<URL 编码的快捷指令名称>&input=text&text=<完整编码的 C 链接>`。外层 text 必须完整保留内层 uuid 与 albumuuid；内层的 & 编码为 %26。设备专用链接留在忽略的 artifacts 中，未上传至仓库。
5. 核对目标照片、退出大图后的相册及相邻照片；记录初次确认提示，以及是否短暂显示 / 停留在快捷指令界面。成功后才验证生产小组件发起、动态来源相册及文件夹中实际包含照片的子相册。

操作依据：[Apple iOS 18 变量使用](https://support.apple.com/zh-cn/guide/shortcuts/apdd02c2780c/8.0/ios/18.0)、[从 URL 运行快捷指令及 text 输入](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/8.0/ios/18.0)。上述外部调用已由机主确认成功，但约 0.5 秒显示快捷指令界面；借拍小组件发起尚未真机验证。

## 0.1.2 历史诊断操作

0.1.1 增加“数据管理”：清空测试记录保留目标与链接设置；重置全部诊断数据清空记录、目标和链接设置。两个操作都清理本机持久化数据，执行测试期间禁用。覆盖安装时保留同一签名身份即可继续使用已有数据，不需要每轮重装。“只检查系统解析结果”也会加入报告，明确标记未执行跳转；报告版本来自实际 Info.plist。

1. 自签并安装 `photos-navigation-probe-unsigned.ipa`，保留 `PhotosNavigationShare.appex`。签名工具可以改写标识，中转从实际扩展 Info.plist 读取标识。
2. 允许完整照片访问，选择一个容易辨认的普通相册，再选择其中一张照片。推荐相册有少量照片，以便确认相邻照片与返回范围。
3. 在“数据管理”点“清空测试记录”；关闭“使用自定义 URL”，选择预设 C。机主已验证此链接在系统快捷指令中可以在目标相册内打开大图。
4. 选择“6 · 主应用：直接系统启动”，点“执行跳转测试”。若打开照片，核对返回页面和相邻照片是否属于目标相册；回到诊断 App，在这条记录的“实际页面”填写结果。
5. 保持同一 C 和目标，切换“7 · 中转扩展：直接系统启动”，重复一次并填写结果。无需重测方式 1–5、无需枚举其他 URL。
6. 点“复制完整诊断报告”并提供这两条结果。主应用成功不等于后台扩展可用，因此两种环境分别记录。

11 个预设覆盖外部照片 / 相册云标识、内部照片 / 相册组合 UUID、完整本机标识、云标识和相册名称。H/I 用于确认 18.7.8 是否仍忽略 18.2 解析器不读取的额外参数，界面明确标为版本对照。自定义 URL 可在同一安装包中编辑参数；限制为 Photos 相关 scheme。

## 证据与边界

机主在未越狱 iOS 18.7.8 上完成 0.1.0 的第一轮测试（2026-10-07）。A / 方式 4：解析器读取完整照片云标识，中转宿主回调正常，派发 accepted=true，机主确认在所有照片中打开大图。C / 方式 5：解析器识别照片和相册 UUID，type=7、revealMode=1（content），中转宿主回调正常，但 openSensitiveURL 派发 accepted=false，LSApplicationWorkspaceErrorDomain / 115，机主确认无反应。D / 方式 5：同样正确识别两个 UUID，type=7、revealMode=2（inContainer），同样派发失败 / 115。由此可确认这两次内部组合入口失败发生在启动派发阶段；通用错误 115 不足以认定唯一权限原因，也未排除主应用的其他派发方式。仓库只保存归纳结果，不保存机主报告中的真实照片 / 相册标识。

机主随后在同一未越狱 iOS 18.7.8 上完成 0.1.1 的第二轮测试。B / 方式 4：解析器读取真实相册云标识，type=8、revealMode=3（initialPosition），中转普通派发 accepted=true；机主确认进入所选的具体相册。H / 仅解析：只读取照片云标识，三个相册目标字段（UUID、本机标识、云标识）均为 null，说明附加的 albumuuid 没有进入目标。I / 仅解析：只读取相册云标识，三个照片目标字段均为 null，说明附加的 revealassetuuid 没有进入目标。H/I 没有实际派发，不能将其记为跳转失败。相册和照片云映射均无错误。记录不包含真实标识或相册名称。

机主第三轮完成 C/D × 方式 1–4 的八次测试，全部无反应。核对两份真实报告后，C/D × 五种派发方式合计十次：每次解析器均识别正确的照片与相册 UUID；C 的 revealMode=1，D 的 revealMode=2。UIApplication.open 两次均 accepted=false（此回调不提供 NSError）；主应用私有普通 / 敏感、中转私有普通 / 敏感的八次均 accepted=false、LSApplicationWorkspaceErrorDomain / 115。中转报告的宿主 hook 正常，主应用派发报告的 bundle 属于主应用，未把中转结果代替主应用结果。归纳数据见 [真机结果](../../docs/verification/photos-album-navigation-ios18.7.8.json)。

前三轮结论：原有五种派发方式无法在指定相册内定位照片。外部 asset / album 分别可打开原照片大图 / 所选相册，但 H/I 的附加上下文被忽略；内部 C/D 能构造正确目标，但五种方式均被系统拒绝。错误 115 仍不足以唯一确定具体拒绝原因。下文记录新的快捷指令成功结果；历史十次失败数据不变。

不继续重复枚举同一内部 scheme 的标识写法。E/F/G 没有证据表明可通过改用本机 / 云标识修复启动派发。根据第四轮成功，0.1.2 改测不同的 INCAppLaunchRequest / FrontBoard 启动路径。借拍现有单照片大图跳转沿用；来源相册上下文尚未接入生产小组件。

敏感 URL 的权限检查可参考另一位开发者的 [SwiftUI 实测](https://kyleye.top/posts/explore-swiftui-link/)：设置隐私 URL 的模拟器示例需要系统 opensensitiveurl entitlement。该例不能替代本机 Photos 的失败原因诊断。[Apple TN2415](https://developer.apple.com/library/archive/technotes/tn2415/_index.html) 说明 entitlement 受代码签名、描述文件及 OS 校验；不能用普通自签名随意声明系统权限来声称已经解决。

## 2026-10-08 社区与启动机制复查

复查 Stack Overflow、Apple Developer Forums、公开 URL scheme 项目、开发者实测以及 GitHub 代码搜索，未找到可在未越狱 iOS 18.7.8 上由普通第三方 App 实现“指定相册上下文 + 指定照片大图”的已验证方案。搜索未发现不等于不存在；系统 18.2 静态实现也不替代本机 18.7.8 行为。

社区资料的适用边界：

- [Stack Overflow 2022：打开选中的照片](https://stackoverflow.com/questions/74124200/how-can-i-show-selected-image-in-photos-app) 仅给出否定回答和 photos-redirect 启动入口，未提供相册上下文的成功实现。机主已经验证单照片云标识跳转，因此不能把这份旧回答当作现代系统绝对不可行的证明。
- [Apple Developer Forums 2025：photos-navigation 相册入口](https://developer.apple.com/forums/thread/773483) 的提问者尝试按自定义相册名称打开失败；回复者为社区用户，未给出成功代码，也不是 Apple 对全部私有机制的结论。机主的相册云标识 B 已验证有效。
- [Sami Samhuri 2024 原始逆向记录](https://samhuri.net/posts/2024/04/photos-navigation-url-scheme/) 能按部分系统名称打开相册，但作者未成功定位单照片；[Rare iOS URL Schemes](https://github.com/jimmy-zhening-luo/scheme) 中多项 Photos 路由也引用该文章，不能视作独立成功验证。未发现其中提供双目标云标识的接口。
- [CarPlay 开发者的原始系统日志](https://developer.apple.com/forums/thread/836595) 显示可见性 / 信任拒绝也能表现为 115；[Meta SDK 开发者报告](https://github.com/facebook/meta-wearables-dat-ios/issues/188) 则报告普通深链接发生 115 后重启能暂时恢复。两者涉及其他应用，不能套用作本机 Photos 的故障原因或修复办法。

本轮从公开 iOS 18.2 反编译实现发现两个具体新线索：

1. [LSSpringBoardCall.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/Frameworks/CoreServices.framework/LSSpringBoardCall.m) 的 `callSpringBoardWithCompletionHandler` 回调（约 153–183 行）收到底层 NSError 后先记录系统日志，再改造成 LSApplicationWorkspaceErrorDomain / 115，仅提示查看日志。原始错误没有作为 NSUnderlyingError 保存。这为“115 不能唯一确定缺少哪个 entitlement”提供代码依据；单纯扩充现有 LS 返回值的记录无法保证取回被替换的原始错误。
2. 快捷指令的 URL 动作经 [WFOpenURLAction.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/ActionKit.framework/WFOpenURLAction.m)、ICManager / WFApplicationContext 请求打开链接。[WFApplicationContext.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/ContentKit.framework/WFApplicationContext.m) 在 UI 宿主不处理请求时创建 WFAppLaunchRequest；其父类 [INCAppLaunchRequest.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/IntentsCore.framework/INCAppLaunchRequest.m) 的 `performWithService:retainsSiri:completionHandler:` 直接通过 FrontBoard `openApplication:withOptions:completion:` 携带目标 bundle 和 URL，并将原始 NSError 交给回调。它与现有五种 LS / UIApplication 路由不同，值得验证；调用方的系统权限仍会影响结果，不能声称普通 App 仿调用就能获得 Shortcuts 的权限。

第四轮：2026-10-08，机主明确确认把诊断 App 的 C 链接放入系统快捷指令，使用“URL → 打开 URL”从编辑器运行后，目标照片成功打开，返回页面及相邻照片均属于选定相册。系统为未越狱 iOS 18.7.8。这是具体调用方与运行方式的成功证据，未验证普通第三方 App / 扩展能获得相同结果，也未证明实际经过哪条 Shortcuts 内部回退分支。[Apple iOS 18 URL 动作说明](https://support.apple.com/guide/shortcuts/apd68802640c/8.0/ios/18.0) 支持这种手动测试，但没有承诺内部 photos scheme 可用。

0.1.2 / build 3 增加方式 6 / 7：加载 IntentsCore 和 FrontBoardServices，创建目标 bundle 固定为 `com.apple.mobileslideshow`、URL 为当前预设、无 userActivity、retainsSiri=false 的 INCAppLaunchRequest，通过 `performWithService:retainsSiri:completionHandler:` 使用默认 Shell 端点。该方法复用 Shortcuts 启动请求父类的实现，不调用外层的 CarPlay 检测。类、参数和返回类型均先核对。主应用记录派发时 active / inactive / background；中转记录扩展实际 bundle 与宿主 hook。保持真实调用身份，没有声明系统 entitlement 或退回旧 LS 方法。保留原始 NSError，包括 NSUnderlyingError / failureReason 与有界 userInfo。请求超时清理，晚到 / 重复回调只完成一次。这两项随后已被真机确认因 Request is not trusted 拒绝；原始错误见本文当前结果。借拍生产点击行为尚未接入它。

两项直接调用已被拒绝，随后改为系统快捷指令中转：[Apple 从 URL 运行快捷指令](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/8.0/ios/18.0) 支持 `shortcuts://run-shortcut?name=…&input=text&text=…`。机主已将快捷指令改为接收输入，确认外部动态照片链接成功，在目标相册中打开照片；同时观察到约 0.5 秒完整快捷指令界面。尚未验证借拍小组件发起，未记录首次许可过程。进一步调查系统小组件执行器和后台权限，见[后台执行调查](../../docs/SHORTCUTS_BACKGROUND_EXECUTION.md)。

`PNInspectURL` 尝试加载设备现有 PhotosUICore，并读取 `PXProgrammaticNavigationDestination.initWithURL:` 的目标字段。不可用时记录失败，仍允许派发；不调用会查询整个图库的 collection getter。方式 1–5 保留原有 UIApplication / LS 主应用与中转派发，6–7 使用直接系统启动。私有入口不保证每个系统版本可用。

系统接受 URL 不等于定位成功。没有自动截取系统 Photos 页面；页面结果由机主观察记录。此工具不创建合成照片、不修改相册、不上传照片或日志；最近 30 次测试留在本机，用户按复制 / 分享按钮导出。

PhotoKit 双向核对照片与相册云标识；云映射不可用时禁用需要它的预设，保留 UUID 路线。照片必须实际属于所选相册且可读取、非隐藏。网格按 120 张分页，不建立全图库 ID 数组。请求附随机 UUID，并忽略 NSExtensionItem.userInfo 的系统附加字段；宿主原回调执行后再读取输入，同一公共 context 去重。直接启动内部超时为 15 秒，其中转宿主给 20 秒以预留扩展启动时间；旧 LS 中转仍为 15 秒。

编译：`bash scripts/build_photos_navigation_probe.sh`（macOS / Xcode / xcodeproj gem）。只进行 9 项标识与 URL 检查、iPhone 编译和包结构检查，不运行桌面小组件自动化。构建通过仍需机主用 iOS 18.7.8 真机验证。

0.1.2 / build 3 的[构建 37656298590](https://github.com/kevin3627713/session-camera/actions/runs/37656298590) 已通过，源码提交 `50a96e8752efcebf9e195b15752489cec709191c`。9 项检查通过；主应用与中转扩展版本一致且二进制均包含 INCAppLaunchRequest / 直接派发选择器。下载后的 IPA 与 CI 哈希核对一致：226,834 字节，SHA-256 `8b9232a17a38b3ced30807e65ddf9a315d5bc0bb8e4d66c2e98625230189665f`。安装包见 [0.1.2 发行版](https://github.com/kevin3627713/session-camera/releases/tag/photos-navigation-probe-v0.1.2)。随后真机确认新直接派发在主应用和中转扩展中均被信任检查拒绝。

解析格式依据：[iOS 18.2 PXProgrammaticNavigationDestination](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/PhotosUICore.framework/PXProgrammaticNavigationDestination.m)。标识映射依据：[Apple cloudIdentifierMappings](https://developer.apple.com/documentation/photos/phphotolibrary/cloudidentifiermappings(forlocalidentifiers:))。
