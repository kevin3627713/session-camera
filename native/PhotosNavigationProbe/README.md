# 照片跳转诊断 0.1.1

独立 iPhone App，Bundle ID `com.kevin3627713.photosnavigationprobe`，内置中转扩展 `.share`，最低 iOS 18.0。工程和编译流程独立于借拍 Runner；不会将诊断界面或代码加入借拍 IPA。源代码保存在 `research/photos-album-navigation-probe-ios18` 分支。

## 真机操作

0.1.1 增加“数据管理”：清空测试记录保留目标与链接设置；重置全部诊断数据清空记录、目标和链接设置。两个操作都清理本机持久化数据，执行测试期间禁用。覆盖安装时保留同一签名身份即可继续使用已有数据，不需要每轮重装。“只检查系统解析结果”也会加入报告，明确标记未执行跳转；报告版本来自实际 Info.plist。

1. 自签并安装 `photos-navigation-probe-unsigned.ipa`，保留 `PhotosNavigationShare.appex`。签名工具可以改写标识，中转从实际扩展 Info.plist 读取标识。
2. 允许完整照片访问，选择一个容易辨认的普通相册，再选择其中一张照片。推荐相册有少量照片，以便确认相邻照片与返回范围。
3. 先执行 A / 方式 4，确认独立 App 的中转能定位照片。返回诊断 App 后，在最新记录中填写实际页面。
4. 执行 C / 方式 5，再执行 D / 方式 5；核对返回位置与相邻照片是否属于所选相册。若失败，可用同一 C/D 链接切换方式 1–4 对照。
5. 复制完整诊断报告。报告包含真实本机标识、UUID、完整云标识、实际设备的解析器字段、派发方法与错误、手动填写的页面结果。也可复制单个或全部预设链接，继续在快捷指令中测试。

11 个预设覆盖外部照片 / 相册云标识、内部照片 / 相册组合 UUID、完整本机标识、云标识和相册名称。H/I 用于确认 18.7.8 是否仍忽略 18.2 解析器不读取的额外参数，界面明确标为版本对照。自定义 URL 可在同一安装包中编辑参数；限制为 Photos 相关 scheme。

## 证据与边界

机主在未越狱 iOS 18.7.8 上完成 0.1.0 的第一轮测试（2026-10-07）。A / 方式 4：解析器读取完整照片云标识，中转宿主回调正常，派发 accepted=true，机主确认在所有照片中打开大图。C / 方式 5：解析器识别照片和相册 UUID，type=7、revealMode=1（content），中转宿主回调正常，但 openSensitiveURL 派发 accepted=false，LSApplicationWorkspaceErrorDomain / 115，机主确认无反应。D / 方式 5：同样正确识别两个 UUID，type=7、revealMode=2（inContainer），同样派发失败 / 115。由此可确认这两次内部组合入口失败发生在启动派发阶段；通用错误 115 不足以认定唯一权限原因，也未排除主应用的其他派发方式。仓库只保存归纳结果，不保存机主报告中的真实照片 / 相册标识。

机主随后在同一未越狱 iOS 18.7.8 上完成 0.1.1 的第二轮测试。B / 方式 4：解析器读取真实相册云标识，type=8、revealMode=3（initialPosition），中转普通派发 accepted=true；机主确认进入所选的具体相册。H / 仅解析：只读取照片云标识，三个相册目标字段（UUID、本机标识、云标识）均为 null，说明附加的 albumuuid 没有进入目标。I / 仅解析：只读取相册云标识，三个照片目标字段均为 null，说明附加的 revealassetuuid 没有进入目标。H/I 没有实际派发，不能将其记为跳转失败。相册和照片云映射均无错误。记录不包含真实标识或相册名称。

机主第三轮完成 C/D × 方式 1–4 的八次测试，全部无反应。核对两份真实报告后，C/D × 五种派发方式合计十次：每次解析器均识别正确的照片与相册 UUID；C 的 revealMode=1，D 的 revealMode=2。UIApplication.open 两次均 accepted=false（此回调不提供 NSError）；主应用私有普通 / 敏感、中转私有普通 / 敏感的八次均 accepted=false、LSApplicationWorkspaceErrorDomain / 115。中转报告的宿主 hook 正常，主应用派发报告的 bundle 属于主应用，未把中转结果代替主应用结果。归纳数据见 [真机结果](../../docs/verification/photos-album-navigation-ios18.7.8.json)。

研究结论：在机主的未越狱 iOS 18.7.8、自签名安装环境下，当前测试的 URL 路线无法在指定相册中自动定位原照片。外部 asset / album 分别可打开原照片大图 / 所选相册，但 H/I 的附加上下文被忽略；内部 C/D 能构造正确目标，但五种调用方式均被系统拒绝。这是对已测 URL 与调用条件的结论，不是对所有未来或未发现机制的证明。错误 115 仍不足以唯一确定具体拒绝原因。

目前暂停该 URL 路线，无新机制证据时不继续重复枚举同一内部 scheme 的标识写法或编译 IPA。E/F/G 仍使用同一内部 scheme，当前没有证据表明换成本机 / 云标识能绕过启动派发拒绝。保留诊断源码、预设和 0.1.1 安装包。借拍现有单照片大图跳转沿用；独立的“打开来源相册”能力已通过 B 真机验证，但尚未作为点击选项接入借拍，也未实现自动定位当前照片。

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

后续优先做无需新 IPA 的一次对照：在诊断 App 选择有效相册与照片，选择预设 C，点“复制当前 URL”；在系统快捷指令 App 中创建两步动作“URL（粘贴完整链接）→ 打开 URL”，直接在编辑器点运行。只记录是否打开目标大图、返回和相邻照片是否仍属于所选相册；失败时记录实际提示。该调用方及派发方式尚未纳入十次真机结果。[Apple iOS 18 URL 动作说明](https://support.apple.com/guide/shortcuts/apd68802640c/8.0/ios/18.0) 支持这种手动 URL 动作测试，但没有承诺内部 photos scheme 可用。

若后续需要新的诊断包，应增加一项直接 FrontBoard / INCAppLaunchRequest 派发，保持有效的当前调用方身份，限定目标为真实系统 Photos，记录原始 NSError 链和调用方前台状态。用途首先是取得拒绝原因，并验证不同派发路径；不是已完成的绕过。此路线尚未编译或真机测试，借拍的生产点击行为尚未接入它。已有 C/D 十次失败记录保持不变。

`PNInspectURL` 尝试加载设备现有 PhotosUICore，并读取 `PXProgrammaticNavigationDestination.initWithURL:` 的目标字段。不可用时记录失败，仍允许派发；不调用会查询整个图库的 collection getter。五种方式分别为 UIApplication.open、主应用私有普通 / 敏感派发、中转扩展私有普通 / 敏感派发。私有入口不保证每个系统版本可用。

系统接受 URL 不等于定位成功。没有自动截取系统 Photos 页面；页面结果由机主观察记录。此工具不创建合成照片、不修改相册、不上传照片或日志；最近 30 次测试留在本机，用户按复制 / 分享按钮导出。

PhotoKit 双向核对照片与相册云标识；云映射不可用时禁用需要它的预设，保留 UUID 路线。照片必须实际属于所选相册且可读取、非隐藏。网格按 120 张分页，不建立全图库 ID 数组。请求附随机 UUID，并忽略 NSExtensionItem.userInfo 的系统附加字段；宿主原回调执行后再读取输入，同一公共 context 去重，15 秒超时清理。

编译：`bash scripts/build_photos_navigation_probe.sh`（macOS / Xcode / xcodeproj gem）。只进行 9 项标识与 URL 检查、iPhone 编译和包结构检查，不运行桌面小组件自动化。构建通过仍需机主用 iOS 18.7.8 真机验证。

解析格式依据：[iOS 18.2 PXProgrammaticNavigationDestination](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/PhotosUICore.framework/PXProgrammaticNavigationDestination.m)。标识映射依据：[Apple cloudIdentifierMappings](https://developer.apple.com/documentation/photos/phphotolibrary/cloudidentifiermappings(forlocalidentifiers:))。
