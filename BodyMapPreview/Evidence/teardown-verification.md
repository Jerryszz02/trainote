# SceneKit 拆卸崩溃回归

## 环境与范围

- 修复基线：`origin/main` 的 `c00427d9aab51e59d8eb9b091be1d6a05c246aec`（PR #5 已合并）。
- Xcode 26.6（17F113），iOS Simulator 26.5（23F77），iPhone 17 Pro。
- 专用模拟器：`Trainote BodyMap Teardown QA`，`E59DEE52-5C1C-402F-8F6C-F5B3DE501D3B`。
- 独立预览使用正式 BodyMap 源码、原生 UIKit/SceneKit、冻结 DTO 和合成数据。
  未替换渲染器，未访问健康数据、网络或 F 的数据库。
- 本修复不修改 F/A 工作树、恢复计算、共享契约、工程登记或 CI。
  F 实际恢复页面仍由集成任务接入修复提交后复验。

## 修复前复现

新增的 `testDismantledContainerIgnoresLateUIKitLayoutAndUpdates` 在未修改生产源码时，
创建真实 `BodyMapSceneContainer`，调用 `dismantleUIView`，改变 bounds 并触发布局。
测试进程以 `EXC_BAD_ACCESS / KERN_INVALID_ADDRESS 0xe8` 退出，和 F 提供的崩溃栈一致：

```text
pthread_mutex_lock
C3DSceneLock
-[SCNRenderer _projectPoint:viewport:]
-[SCNView projectPoint:]
BodyMapScene.projectedAnchors(in:)       BodyMapScene.swift:142
BodyMapSceneContainer.updateLabels()    BodyMapSceneView.swift:152
BodyMapSceneContainer.layoutSubviews()  BodyMapSceneView.swift:106
```

本地原始证据保留在忽略目录 `build/body-map/teardown-native-before.xcresult` 和
`teardown-native-before.log`；系统报告为 `BodyMapPreview-2026-10-03-053050.ips`。
首次真实 UI 列表往返没有触发该崩溃，但在重建 3D 后找不到肌群标签，
记录于 `build/body-map/teardown-before.xcresult`。

## 修复

- 先使容器及回调失效、释放 model，再断开相机和场景；重复拆卸安全。
- 拆卸后布局、配置更新、旋转和排队的不可用通知不再访问已移除的渲染器。
- 投影和射线选择同时核对场景、相机与有效 viewport，保留的旧 model 也不能访问脱离的 SCNView。
- 新建 SCNView 在标签投影前完成自身布局，保证从列表返回后的标签立即恢复。

## 回归覆盖

- 原生单测：拆卸后强制布局、主队列延迟更新和选择回调、重复拆卸，以及脱离/不匹配场景、相机和零尺寸 viewport。
- UI：8 次 3D→列表→3D，验证列表选择保留、标签恢复、前后旋转和 16 次选择回调。
- UI：6 次 NavigationStack 进入/退出，分别从 3D 与列表返回；每次重进后验证网格选择、拖动旋转和标签选择。
- 既有几何、遮挡选择、状态映射、未知/零分、辅助功能、低电量及静止渲染回归。

独立工程生成和全组件测试命令：

```sh
python3 BodyMapPreview/prepare_preview.py --xcodegen /path/to/xcodegen
xcodebuild -project build/body-map/preview/BodyMapPreview.xcodeproj \
  -scheme BodyMapPreview \
  -destination 'platform=iOS Simulator,id=E59DEE52-5C1C-402F-8F6C-F5B3DE501D3B' \
  -derivedDataPath build/BodyMapTeardownDerivedData \
  -resultBundlePath build/body-map/teardown-regression-after.xcresult \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

2026-10-03 修复后结果：独立组件 **18/18 通过**（9 项原生单测、9 项 UI 测试），无跳过。
原崩溃用例通过；8 次列表往返与 6 次页面进出均通过。

正式工程使用同一专用模拟器运行以下命令，**9/9 BodyMap 单测通过**，无跳过：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote \
  -destination 'platform=iOS Simulator,id=E59DEE52-5C1C-402F-8F6C-F5B3DE501D3B' \
  -derivedDataPath build/TrainoteTeardownDerivedData \
  -resultBundlePath build/body-map/teardown-product-after.xcresult \
  -parallel-testing-enabled NO -only-testing:TrainoteTests/BodyMapTests \
  CODE_SIGNING_ALLOWED=NO test
```

`swift-format lint --strict`（5 个修改的 Swift 文件）及 `git diff --check` 均通过。
原始 xcresult、日志及导出的 UI 附件保留在此修复工作树的忽略目录 `build/body-map/`。
此前 PR #5 的历史验收文件未被替换。
