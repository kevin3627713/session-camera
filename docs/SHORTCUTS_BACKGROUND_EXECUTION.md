# 快捷指令后台执行调查（2026-10-08）

目标：借拍照片小组件点击后，在其来源相册内打开当前照片，并省略完整快捷指令 App 的前台中转界面。设备为未越狱 iOS 18.7.8，使用自签 IPA。本次研究后增加独立诊断 0.1.3 / build 4 的执行器测试，借拍生产代码保持不变。

## 已有真机证据

机主已确认固定 C 链接 `photos://asset?uuid=<assetUUID>&albumuuid=<albumUUID>` 在系统快捷指令编辑器中成功，返回页面与相邻照片保留选定相册。随后把完整 C 链接作为动态 text 输入，从外部 `shortcuts://run-shortcut` 启动同样成功；观察到快捷指令页面约 0.5 秒加载，随后在目标相册中打开照片。该时间为机主估计，未经性能测量。

随后机主完成系统“快捷指令”小组件对照，选择的结果是“直接进入照片，或仅有进度提示”，确认没有完整快捷指令界面。此次答复没有单独复述返回页面和相邻照片的相册检查，因此报告不新增相册验收结论。

普通第三方主应用与中转扩展直接执行 INCAppLaunchRequest / FrontBoard 两次 C 请求都被系统以 Security / Request is not trusted 拒绝。此结果属于之前的启动路径，不能作为后台快捷指令执行器的真机结果。生产借拍小组件尚未接入相册中转；第三方执行器测试仍待 0.1.3 真机结果。

归纳数据见[真机报告](verification/photos-album-navigation-ios18.7.8.json)。照片、相册、签名真实标识只保存在本机忽略的测试材料中，不进入公开报告。

## URL 入口

[Apple iOS 18 的 URL 运行文档](https://support.apple.com/guide/shortcuts/run-a-shortcut-from-a-url-apd624386f42/8.0/ios/18.0) 支持快捷指令名称与 text / clipboard 输入，没有公布省略前台界面的参数。[x-callback-url 文档](https://support.apple.com/guide/shortcuts/use-x-callback-url-apdcd7f20a6f/8.0/ios/18.0) 提供成功、取消及错误回调，不承诺后台执行。

在公开 iOS 18.2 / 22C152 的 [WFRunWorkflowURLHandler.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/WorkflowKit.framework/WFRunWorkflowURLHandler.m) 中，运行入口读取 id / name、input、text、pasteboard 和 source，并交给注册的运行回调。source 默认为请求的 sourceName。此文件没有读取 background / silent / hide 等界面开关。不能据此排除其他文件或 18.7.8 新增的行为，但未发现支持随意添加这些参数的依据；不能将 source=widget 等同于系统小组件调用身份。

## 系统小组件执行器

[Apple iOS 18 小组件说明](https://support.apple.com/guide/shortcuts/run-shortcuts-from-the-home-screen-widget-apd029b36d05/8.0/ios/18.0) 明确区分：部分动作可以在快捷指令小组件中执行并显示进度，无法在组件中完成的动作会打开完整快捷指令 App。它不保证每个 URL 动作与系统版本均能省略前台界面，因此本机这条照片链接还需要一次对照。

iOS 18.2 的 [WFWidgetWorkflowRunnerClient.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/WFWidgetWorkflowRunnerClient.m) 使用数据库工作流标识创建 WFWorkflowRunRequest，设置 runSource 为 widget，根据位置及 System Aperture 条件选择 presentationMode，并初始化 WFWorkflowRunnerClient。此入口没有先派发 shortcuts URL。

[WFWorkflowRunnerClient.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/WFWorkflowRunnerClient.m) 创建运行上下文和进程外控制器，使用当前主 bundle 的真实标识作为 originatingBundleIdentifier。presentationMode 是执行请求字段，发现该字段不等于获得执行权限。

服务器 [WFBackgroundShortcutRunner.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/WorkflowKit.framework/WFBackgroundShortcutRunner.m#L3171) 在运行前通过 allowIncomingRunRequest 检查运行时访问能力、请求描述符类型及关联应用等条件；拒绝分支在约 5376 行记录 missing required entitlement。约 5665 行从真实 XPC 连接取得 accessSpecifier。反编译中部分类引用及类别方法没有还原，不能声称已经枚举所有授权分支。

[VCAccessSpecifier.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/VoiceShortcutClient.framework/VCAccessSpecifier.m#L50) 从连接 audit token 创建 SecTask，并用 SecTaskCopyValuesForEntitlements 读取实际签名权限；可见 com.apple.shortcuts.background-running 等系统权限参与判断。普通自签名声明这些字符串不能作为 OS 已授予权限的证据，参见 [Apple TN2415](https://developer.apple.com/library/archive/technotes/tn2415/_index.html)。修改客户端返回值、runSource 或名称不会修改服务器看到的真实 audit token。

因此，这条独立执行器路径有研究价值，但当前证据不足以承诺借拍普通自签小组件可以调用。以上静态材料来自 iOS 18.2，不能替代机主 iOS 18.7.8 上的实际调用测试。

## 系统分享扩展

另一个候选是由系统快捷指令分享扩展执行。iOS 18.2 的 [WFActionExtension.m](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/private/var/staged_system_apps/Shortcuts.app/PlugIns/ShortcutsActionExtension.appex/WFActionExtension.m#L166) 从 NSExtensionItem.userInfo 取得 ActionExtensionWorkflowToken，必须通过系统快捷指令偏好设置将一次性令牌兑换为工作流标识，再从数据库实例化工作流。输入只有名称、普通 UUID 或照片 URL 并不符合这条接口。尚未发现普通第三方能在无需用户打开系统选择界面的情况下取得有效令牌的机制。

## 无需新 IPA 的对照步骤

1. 选择之前成功的固定 C 链接快捷指令，包含“URL → 打开 URL”两个动作。使用固定链接版本，避免系统小组件缺少动态快捷指令输入。
2. 在主屏幕长按空白处，进入编辑、添加小组件，搜索“快捷指令”，添加小尺寸组件。
3. 长按这个系统组件，选择编辑小组件，将快捷指令设为第 1 步的固定链接版本。
4. 从主屏幕点击它，记录是否显示完整快捷指令 App、是否只显示进度或浮层，以及照片是否仍在目标相册中打开。

此对照验证系统自身的入口能否避免前台中转。即使成功，也不证明借拍照片小组件能获得同一调用能力。系统快捷指令小组件的入口与借拍照片小组件的界面属于不同扩展，不能将前者的成功记作生产集成成功。后续若验证第三方独立执行器，应单独记录真实调用身份、服务器错误及是否出现界面，不重复把既有失败路由换成同一 URL 的其他拼写。

## 当前结论

外部动态中转已解决相册上下文，仍有机主观察到的约 0.5 秒前台页面。系统小组件对照已确认没有完整快捷指令界面。未找到可直接用于生产的 URL 后台开关。系统执行器与分享扩展存在具体访问条件，普通自签调用的成功尚未建立。

## 独立执行器诊断 0.1.3

增加方式 8（主应用）和方式 9（自有后台中转扩展）。两者使用系统小组件的同一父类 WFWorkflowRunnerClient，创建数据库名称描述符与 widget 运行请求，把完整 C 链接按文本封装为 WFContentCollection。选择 presentationMode 时参考同一 System Aperture 条件；使用运行请求入口，避免 start() 在立即连接失败时对空进度上下文断言。这里没有直接调用子类 WFWidgetWorkflowRunnerClient 的标识初始化，也没有读取系统快捷指令数据库。

快捷指令名称默认为“借拍相册跳转”，可修改并保存在本机；应指向已成功接收动态输入的版本。清空记录保留配置，重置全部数据清除名称配置。请求仍保持各进程真实身份，没有声明或伪造系统 entitlement，没有改写 originatingBundleIdentifier，也没有退回 shortcuts URL。

运行前核对类和方法的实际签名，记录可读取的当前进程运行时访问能力、真实 bundle、请求模式、返回 NSError 与耗时。请求保留到委托完成或 15 秒超时，重复与晚到回调只完成一次；超时取消排在同一执行队列，不与连接请求并发。中转宿主留 20 秒收尾。委托执行成功仍不能替代实际 Photos 页面核对。

该独立 App 的主应用和扩展属于第三方进程。方式 9 的结果有助于判断后台扩展能否调用，但不能自动代替未来生产 WidgetKit 扩展的集成结果。具体操作见[诊断发行说明](../native/PhotosNavigationProbe/RELEASE_NOTES.md)。
