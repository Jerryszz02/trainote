# 3D 人体组件的独立验收

此目录只包含合成数据预览、组件 UI 测试和本地性能采样。不会注册到生产 App，
不读取 SwiftData / HealthKit，不访问网络，不修改恢复计算、RecoveryView 或导航。
实际截图及验证结果见 [Evidence/verification.md](Evidence/verification.md)。

## 正式接入点

```swift
BodyMapView(presentation: presentation) { muscleID in
  // 父页面更新 presentation.muscles[*].isSelected 并展示该肌群详情。
  selectMuscle(muscleID)
}
```

共享 `BodyMapPresentation` / `MuscleID` 来自 A 的固定提交
`32e9fac26055d9b35eb791e75a0ceacd1d45e898`；D 通过普通 merge 保留其祖先关系，未修改 A 的文件。
`BodyMapRenderInput(presentation:)` 是唯一薄适配层。只做状态文案、合法值检查和 5 分显示舍入，
不会计算恢复分数，也不会根据分数重判上游 state。选择由父页面控制；回调参数为正式 `MuscleID`。
遗漏肌群或无效数值保持未知；`.unknown` 不采用附带数值。疼痛和活动受限保留为独立警示，
不因同时存在高分而显示普通绿色。多个选中标记时以首项为准。

## 交互及降级

- 74 个原创闭合体积网格，26,596 顶点 / 52,896 三角形；11 个规范肌群均可选择，同组左右共享值。
- 水平拖动绕身体纵轴旋转 360°，前/背按钮立即定位，不自动转动。垂直手势交还页面滚动。
- 点击前景网格或标签触发相同回调。最近表面阻止穿透选择；标签跟随投影并检查遮挡，拥挤列重新平衡。
- 显示分数、文字、选中标记；未知使用灰色、破折号和虚线，不等于 0 分。
- VoiceOver、辅助功能字号、严重/临界热状态或渲染资源不可用时自动改用同一数据的原生按钮列表。
- 用户也可随时切换列表。低电量/一般热状态采用 20 fps、关闭抗锯齿；普通模式上限 30 fps。
- 无动画、无惯性、自转或粒子；减少动态效果模式下仍只有用户主动旋转。视图退出时释放场景。
- 静止时 `rendersContinuously = false`、`isPlaying = false`。模拟器测试中的偶发系统重绘不计为持续渲染。

## 本地预览与测试

需要 Xcode 和 XcodeGen。本次使用 Xcode 26.6、XcodeGen 2.46.0，最低部署版本保持 iOS 17。
若机器未安装 XcodeGen，可把官方 release 解压到忽略目录 `.xcodegen/`；不将工具提交到仓库。

```sh
python3 BodyMapPreview/prepare_preview.py --xcodegen /path/to/xcodegen
xcodebuild -project build/body-map/preview/BodyMapPreview.xcodeproj \
  -scheme BodyMapPreview \
  -destination 'platform=iOS Simulator,id=<本任务专用UDID>' \
  -derivedDataPath build/BodyMapDerivedData \
  -resultBundlePath build/body-map/tests.xcresult \
  CODE_SIGNING_ALLOWED=NO test
```

`prepare_preview.py` 只在忽略的 `build/body-map/preview/` 生成 spec 和工程，
使用本组件、A 的两个契约文件和固定 JSON。不会修改共享 `project.yml` / `.pbxproj`。
`TrainoteTests/BodyMapTests.swift` 可同时加入主 App 单测目标；独立预览目标通过编译条件切换测试模块。
`BodyMapPreview/Tests` 仅属于独立预览 UI 测试，不能误加入生产 App 或原有 UI 测试目标。

安装构建好的 `BodyMapPreview.app` 并启动 `com.jerryszz.trainote.bodymap-preview`。
可选启动参数：`-fixture-list`、`-fixture-economical`、`-fixture-dark`、`-fixture-large-text`。
`-fixture-benchmark` 在预览内运行 1 秒预热、5 秒旋转和 2 秒静止采样，显示实际渲染回调间隔与进程物理内存。
这些参数仅在预览入口读取，未加入生产 App 的 launch 参数。

## 资产许可与重现

见 [PROVENANCE.md](../Trainote/Resources/BodyMap/PROVENANCE.md)、[MIT 许可](../Trainote/Resources/BodyMap/LICENSE.txt)
及 [mesh-muscle-map.json](../Trainote/Resources/BodyMap/mesh-muscle-map.json)。
`python3 BodyMapPreview/generate_asset.py` 从原创几何控制点重现资产；没有下载、采购或复用第三方人体素材。
它是用于粗粒度训练肌群的风格化三维插图，不是解剖扫描或模型分数的科学验证。

原生实现使用 Apple [SceneKit](https://developer.apple.com/documentation/scenekit)，
以[非连续渲染](https://developer.apple.com/documentation/scenekit/scnview/renderscontinuously)
控制静止时的工作量。完整渲染器与健康数据服务相互独立，未来可替换渲染实现而保留正式 DTO。

## 工程注册与后续集成

`Trainote/Features/Recovery/BodyMap/*.swift`、`Trainote/Resources/BodyMap/` 和
`TrainoteTests/BodyMapTests.swift` 已通过现有 XcodeGen 流程注册到正式工程。
主对话明确委派 D 将必要的生成登记作为单独机械提交；未修改根 `project.yml` 功能配置或 CI。
`BodyMapPreview/` 未加入生产 App。A/D 联合分支仍由主对话重新生成最终工程并验证 CI，处理生成文件冲突。
本次主工程生成差异另保存在忽略的 `build/body-map/registration.patch`。
