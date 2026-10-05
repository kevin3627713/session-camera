# 透明小组件实验：借拍的同一个 IPA

本实验从借拍 v0.2.0 / cb7895d 创建 experiment/transparent-widgets-ios18 分支，应用版本 0.2.1（build 4）。正式 main 分支不受本实验影响。目标设备是用户的未越狱 iPhone，iOS 18.7.8；该小版本的真机显示效果尚待验收。

## 安装和使用

下载此分支的实验版 IPA，用安装原借拍的同一 Apple ID / 签名工具更新原应用。主应用包名保持 com.kevin3627713.sessioncamera；如果之前签名时改过包名，更新时应继续使用当时的映射。保留小组件扩展，不要启用 Remove app extensions / 删除扩展选项。安装后先打开借拍一次。

长按主屏幕 → 编辑 → 添加小组件 → 借拍。提供小、中、大三种尺寸，共四种样式：

| 样式 | 用途 |
| --- | --- |
| 透明相机 | 保留白色相机图标和文字，尝试让真实壁纸透过背景 |
| 空白透明 | 不绘制图标和文字，尝试留出完全透明的网格区域 |
| 磨砂相机 | 尝试使用系统模糊背景，与透明版对照 |
| 普通背景 | 不修改私有描述符，用于观察系统默认背景 |

四种样式都包含在同一个 SessionWidgets.appex 中，点按都会打开借拍。空白版仍占据小组件网格并响应点击；小组件外的名称标签由主屏幕管理，本实验没有修改 SpringBoard 的布局或标签规则。

这是更新现有借拍应用的一个扩展，不另安装第四个主应用。扩展有自己的包名 com.kevin3627713.sessioncamera.widgets，因此通常会增加一个签名 App ID；多个样式共用这一个扩展。AltStore 的 App IDs 限额与三个活跃应用槽位是不同限制，详见 [AltStore App IDs](https://faq.altstore.io/altstore-classic/app-ids)。签名工具需同时为主应用和扩展提供匹配的签名；打包中的 ad-hoc 签名只是待重新签名的占位。

## 判断真透明是否生效

把空白透明与普通背景放在有明显线条或颜色变化的壁纸上。移动空白小组件到其他位置，并切换另一张壁纸：如果区域直接显示新位置的真实壁纸，且没有背景色块、边框或壁纸拼接错位，才算透明生效。程序没有保存、裁剪或读取壁纸截图。

如果透明版仍显示系统色块，先确认 IPA 保留了 SessionWidgets.appex、已打开过主应用，再移除并重新添加小组件，必要时重启手机。仍有色块表示这个系统版本、主屏幕显示模式或描述符缓存没有应用私有属性；不能用“编译通过”代替实际效果。建议先在普通浅色 / 深色图标模式测试，再测试着色、大图标和智能叠放等显示模式。

## 技术实现与来源

依据 [Jinwoo Kim 的原始示例 ClearAndBlurredWidgets](https://github.com/pookjw/ClearAndBlurredWidgets) 和其 [Stack Overflow 回答](https://stackoverflow.com/questions/68718989/swift-widget-background-transparent/78984412#78984412) 研究方法，独立实现 ARC Objective-C 钩子。没有整份复制该仓库源码。也参考 [PR #6 的崩溃分析](https://github.com/pookjw/ClearAndBlurredWidgets/pull/6) 加入初始化所有权和兼容性处理；该 PR 是上游讨论，并非 iOS 18.7.8 的验证证明。

钩子仅编译在小组件扩展，修改自己的 WidgetKit XPC 描述符回调：

1. 在 iOS 18 安装 _TtCC9WidgetKit24WidgetExtensionXPCServer14ExportedObject 的 getAllCurrentDescriptorsWithCompletion: 方法替换；启动时短暂重试，以应对延迟加载。
2. 安全解码 activityDescriptors、controlDescriptors、widgetDescriptors，保留前两组和其他 kind。
3. 对 SessionCamera.Clear / Blank 的描述符副本设置 backgroundRemovable=true、transparent=true、preferredBackgroundStyle=1。
4. 对 SessionCamera.Blur 设置同样的移除 / 透明属性，preferredBackgroundStyle=2，并启用 supportsVibrantContent。
5. 通过正常 Objective-C initWithCoder: 重建原始 DescriptorFetchResult 类型，回调一次。

代码检查私有类、方法和参数类型；未知 kind、未修改成功、解码错误及 Objective-C 异常均返回原始结果。其他 iOS 主版本不安装钩子。私有接口没有稳定性保证，异常回退也不能覆盖所有底层崩溃；未来兼容性必须重新验证。

小组件只显示固定内容与启动 URL，不访问照片、不共享相机会话，不需要 App Groups 或特殊私有 entitlement。原有本次照片隔离、拍摄保存和照片编辑保持原逻辑。

## 自动验证的范围

- macOS Foundation 测试直接编译生产 Objective-C 钩子，使用模拟的安全编码描述符验证四种 kind、其他数组保留、原对象不变、晚安装、重复安装、继承方法隔离、无效数据 / 方法签名 / 异常回退及单次回调。
- iPhone arm64 Release 构建和 iPhone Simulator 扩展构建检查实际 WidgetKit / SwiftUI 链接与 Xcode 嵌入关系。
- iOS 18 模拟器运行独立诊断程序，记录实际私有类、选择器编码和生产钩子能否安装；报告 AVAILABLE 仅表示接口可用，不表示主屏幕已经显示透明背景。
- IPA 验证检查同一主包名、恰好一个扩展、匹配的版本号、设备 arm64 程序、私有钩子只存在于扩展和正确的启动 URL。
- 原有 13 项 Swift 会话 / 照片渲染测试与两项 Flutter 桥接测试继续运行。

GitHub Actions 上传的 native-verification 产物含上述测试日志和运行时探测报告。自动检查无法替代 iOS 18.7.8 真机重签名安装及主屏幕视觉验收。
