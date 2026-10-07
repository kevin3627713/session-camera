# 照片跳转诊断 0.1.0

独立 iPhone App，Bundle ID `com.kevin3627713.photosnavigationprobe`，内置中转扩展 `.share`，最低 iOS 18.0。工程和编译流程独立于借拍 Runner；不会将诊断界面或代码加入借拍 IPA。源代码保存在 `research/photos-album-navigation-probe-ios18` 分支。

## 真机操作

1. 自签并安装 `photos-navigation-probe-unsigned.ipa`，保留 `PhotosNavigationShare.appex`。签名工具可以改写标识，中转从实际扩展 Info.plist 读取标识。
2. 允许完整照片访问，选择一个容易辨认的普通相册，再选择其中一张照片。推荐相册有少量照片，以便确认相邻照片与返回范围。
3. 先执行 A / 方式 4，确认独立 App 的中转能定位照片。返回诊断 App 后，在最新记录中填写实际页面。
4. 执行 C / 方式 5，再执行 D / 方式 5；核对返回位置与相邻照片是否属于所选相册。若失败，可用同一 C/D 链接切换方式 1–4 对照。
5. 复制完整诊断报告。报告包含真实本机标识、UUID、完整云标识、实际设备的解析器字段、派发方法与错误、手动填写的页面结果。也可复制单个或全部预设链接，继续在快捷指令中测试。

11 个预设覆盖外部照片 / 相册云标识、内部照片 / 相册组合 UUID、完整本机标识、云标识和相册名称。H/I 用于确认 18.7.8 是否仍忽略 18.2 解析器不读取的额外参数，界面明确标为版本对照。自定义 URL 可在同一安装包中编辑参数；限制为 Photos 相关 scheme。

## 证据与边界

`PNInspectURL` 尝试加载设备现有 PhotosUICore，并读取 `PXProgrammaticNavigationDestination.initWithURL:` 的目标字段。不可用时记录失败，仍允许派发；不调用会查询整个图库的 collection getter。五种方式分别为 UIApplication.open、主应用私有普通 / 敏感派发、中转扩展私有普通 / 敏感派发。私有入口不保证每个系统版本可用。

系统接受 URL 不等于定位成功。没有自动截取系统 Photos 页面；页面结果由机主观察记录。此工具不创建合成照片、不修改相册、不上传照片或日志；最近 30 次测试留在本机，用户按复制 / 分享按钮导出。

PhotoKit 双向核对照片与相册云标识；云映射不可用时禁用需要它的预设，保留 UUID 路线。照片必须实际属于所选相册且可读取、非隐藏。网格按 120 张分页，不建立全图库 ID 数组。请求附随机 UUID，并忽略 NSExtensionItem.userInfo 的系统附加字段；宿主原回调执行后再读取输入，同一公共 context 去重，15 秒超时清理。

编译：`bash scripts/build_photos_navigation_probe.sh`（macOS / Xcode / xcodeproj gem）。只进行 9 项标识与 URL 检查、iPhone 编译和包结构检查，不运行桌面小组件自动化。构建通过仍需机主用 iOS 18.7.8 真机验证。

解析格式依据：[iOS 18.2 PXProgrammaticNavigationDestination](https://github.com/EthanArbuckle/iPhone17-1_18.2_22C152_Restore/blob/e26ed4563f78871c59d2d96856756a65d62517e5/System/Library/PrivateFrameworks/PhotosUICore.framework/PXProgrammaticNavigationDestination.m)。标识映射依据：[Apple cloudIdentifierMappings](https://developer.apple.com/documentation/photos/phphotolibrary/cloudidentifiermappings(forlocalidentifiers:))。
