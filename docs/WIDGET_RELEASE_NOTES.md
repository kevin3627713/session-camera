# 借拍 0.2.1：iOS 18 透明小组件实验

基于 v0.2.0 创建独立 experiment/transparent-widgets-ios18 分支，在借拍的同一个 IPA 内加入一个 WidgetKit 扩展。主应用包名保持不变；使用原签名身份和包名映射更新借拍，并保留扩展，不需再安装一个独立主应用。

- 透明相机、空白透明、磨砂相机和普通背景对照，支持小 / 中 / 大尺寸，点击打开借拍。
- 私有描述符修改限定 iOS 18，增加类型检查、延迟安装和错误回退；钩子仅在扩展进程运行。
- 原有相机、照片自动保存、本次预览和编辑同步逻辑保持原样。
- 一个扩展通常额外使用一个签名 App ID，四个样式不会各占一个 App ID。重签名时必须保留并签名 SessionWidgets.appex。

这是实验预发布：编译、描述符逻辑测试和运行时可用性探测不等于 iOS 18.7.8 真机透明效果已验证。安装后长按主屏幕 → 编辑 → 添加小组件 → 借拍，建议先用空白透明对比普通背景，并移动位置、更换壁纸验证。

已通过 [完整构建](https://github.com/kevin3627713/session-camera/actions/runs/37282829051)：13 项 Swift 测试、两项 Flutter 测试、18 项描述符检查、iPhone Release 与模拟器扩展编译、最终 IPA 校验。真实 iOS 18.6（22G86）模拟器确认所有目标私有方法可用，生产钩子成功安装；本次没有测试主屏幕视觉效果。源码提交 3f15b770010de5e1fee06058e162ef8dab2ef81d，标签中后续提交仅增加验证文档。

应用 / 扩展均为版本 0.2.1、build 4。IPA 大小 6,500,088 字节；SHA-256 为 dcf74e4e418c5ad5250b18c3c54a6d8821433aa3f56f5e43c7da87f16b2409da。

详细原理、来源与验收方法见 [实验说明](https://github.com/kevin3627713/session-camera/blob/experiment/transparent-widgets-ios18/docs/TRANSPARENT_WIDGETS.md)。
