# 借拍 0.3.1：高清照片与加载恢复

修复随机照片小组件只能显示模糊预览，以及移除重放后加载失败迟迟不恢复的问题。仍在 experiment/transparent-widgets-ios18 分支，主程序 / 扩展均为版本 0.3.1、build 6。用原签名身份和包名映射覆盖更新，并保留 SessionWidgets.appex，沿用已有签名槽位。

0.3.0 的 PhotoKit opportunistic 请求可能先返回低清预览。旧代码收到第一个 UIImage 就结束请求，取消了后续高清图片。0.3.1 改为 highQualityFormat / exact，并显式忽略 PHImageResultIsDegradedKey 为 true 的回调。

- 按小组件显示点数的三倍请求图片，最长边上限 1200 像素，按组件比例裁剪后编码为 JPEG；不请求整个原始大图。
- 只缓存最终高清 JPEG，移除重放或重载时可以复用。缓存按照片 ID、修改时间和尺寸区分；读取前检查权限及当前资产访问，不会从缓存恢复已不可访问的资产。
- 当前图片加载失败时显示提示，请求五分钟后重试。未来图片失败时保留已准备好的照片，提前请求新的时间线，不预排没有图片的未来条目。
- 当前图片优先加载，限制后续预加载等待，减少首次放置时的等待时间。网络和系统刷新调度仍影响显示时间。

保留五种样式、原生编辑面板、默认点击不打开应用，以及每个组件独立的随机编号和更换周期。相机内只预览本次拍摄的功能继续沿用原实现。

更新后无需再删除小组件：打开借拍 → 右上角安心借拍说明 → 照片小组件权限与刷新（机主验证）→ 刷新照片小组件。如果已删除过组件，重新选择随机照片样式、来源和独立编号；这些设置由系统保存，删除组件会一并移除。

测试使用真实 iOS 18.6 PhotoKit 合成照片，并检查实际像素尺寸与细线纹理对比度，覆盖高清回调、缓存复用、缺失资产不使用缓存、加载失败提示和重试时间线。你的 iOS 18.7.8 手机上还需确认实际图片显示和 iCloud 加载情况。

详细使用和实现说明：[CONFIGURABLE_WIDGETS.md](https://github.com/kevin3627713/session-camera/blob/experiment/transparent-widgets-ios18/docs/CONFIGURABLE_WIDGETS.md)。

完整构建与验证：[Actions 37306257118](https://github.com/kevin3627713/session-camera/actions/runs/37306257118)，代码提交 c0e3f7c29715005e0c63e38982eaa01c13c1e955。19 项 Swift 测试、18 项描述符检查、2 项 Flutter 测试，以及 30 项真实 iOS 18.6 PhotoKit / 时间线检查均通过。[照片专项测试](https://github.com/kevin3627713/session-camera/actions/runs/37306256886) 也通过。实际验证 480×480 和 1080×1140 像素及细线纹理清晰度，不仅检查图片可以解码。

IPA 大小：6,632,637 字节。SHA-256：98ac7f90f757547b89586aec6c0f461e750945c5a54f852ff81984c5817ae9e3。
