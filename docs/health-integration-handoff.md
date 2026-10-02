# Health integration (task F)

2026-10-03：实施中。工作树 `392a/trainote`、分支 `agent/health-integration`，固定基础
`967fa5351838240b2bb6ca0c5cb8e777530e54c4`（A/D 联合构建基础）。本页只记录 F 的接口和验证。骨架已提交 `d486247` / 工程 `9feaf35`，随后普通合并固定基础
`28500cfaba534d2d09a1415f8c6d1cb1d904a10e`（merge `22a53d2` / 工程 `da4b72b`）。
不表示 B/C/E 已装配、模型已验证或服务已部署。

## 当前接口协调

- A 的 `goalRevisionState` / `applyGoalRevision` 已随固定基础 `28500cf` 接入。F 的旧目标编辑器使用
  `ManualNutritionGoalEditing` 捕获状态并在同一事务写入，stale 时保留草稿、阻止重复保存，要求明确载入
  最新目标再确认；不使用两次写入。B 仍负责分析页 proposal/undo。
- 既有 `AnalysisInput` 没有 Routine、选定模板、可训练日；当前 Routine 也没有排期字段。
  F 的规则接受显式 `TrainingRecommendationContext`，它是本地规则上下文，不是第二套共享分析模型。
  模板选择必须来自用户，不能用最近编辑模板猜出长期计划。动作到肌群映射由 C 适配。
- `RecommendationProviding` 只返回 candidates；`ReportSnapshotBuilder` 的事实表目前只收集
  health/trend/recovery facts，且仓储指纹不含模板上下文。建议 A 单一负责人在报告构建边界允许
  收集 recommendation facts，并把模板选择/内容/可训练日版本并入最终报告指纹。未协调前
  F 新理由事实不直接送给 E，避免不可解析 ID 和旧报告复用。
- E 需提供报告生命周期适配：availability/disclosureVersion、服务器登记、同步取消、
  服务器撤回（持久重试）、删除全部报告和 `HealthDerivedDataInvalidating`。注册 invalidator
  必须发生在缓存报告前；AI 撤回即刻取消，再尝试本地撤回与服务器撤回，分别呈现失败。

## F 实装入口

- `AppShell` 五 Tab，每个保留独立 NavigationStack；`LibraryView(initialSection:)` 从今日/训练/饮食进入，原设置、目标、备份、周回顾入口保留。
- `HealthFeatureAccess` 构造时注册 `AIReportLifecycle` 的 health invalidator 与 AI 同步取消 hook；
  健康断开调用 A `disconnectAndDelete`。撤回分别尝试本机和服务器，失败可重试。
  当前生产装配为 `LocalOnlyReportAccess`，无网络/凭据/报告缓存，未配置时无法预先同意。
- `HealthAnalysisDestinations` 是 B/C 页面装配点；当前默认是诚实的未开放空态，不提供合成数据。
- `TrainingRecommendationRules(context:)` 遵守 A `RecommendationProviding`；`evaluate` 同时返回
  candidates、新增 facts、`plansByAction` 和 contextFingerprint。C 提供 reviewed exercise mapping，
  B 提供有事实来源的 nutritionReviewFactIDs。无显式模板不推断长期计划。
- `RecommendationWorkoutFactory.make` 调用 `reevaluate`、核对当前 action ID 和绑定模板的完整修订快照，
  然后新建 Workout。减组不改模板/历史；提高 RIR 只写目标提示，实际组的 RIR/completion 清空。
- 规则版本 `training-candidates-p1`：最近 24 小时、保留 50%–75% 组数、建议至少 2–4 RIR 是工程初值。
  未知旧组角色按计划先验计入并标记 unknownSetRole，不回填旧记录；疼痛优先于高分，未知准备度不变成 100。

## 待完成

- 当前建议卡尚未运行完整 B/C 计算；完成页面装配后连接真实候选和采用入口、可跳过的 C 体感入口。
- Settings 手动写入已接 A 的单事务；旧营养汇总按日历史查询仍待 B 实装。首次主动启用趋势选择每周建议，不改变升级前手动目标。
- 在同分支接入主对话已验证的 B/C/E 固定提交，完成采用/撤销、报告及真机条件清单。
- 只推送 ready PR，不自行合并、部署或发布。

## 骨架验证（2026-10-03）

- Xcode 26.6 / iOS 26.5；专用 Simulator `B4FF3837-B382-4AD5-A24A-FEAC05A0ECAB`，
  DerivedData `/tmp/trainote-health-integration-derived`。其他任务设备/进程未操作。
- 全部 94 项单元测试，0 失败；含 F 新增 14 项训练候选/快照和 7 项同意/撤回测试。
  这是初始 `967fa535` 骨架结果：`/tmp/trainote-health-integration-units-verified.xcresult`。
- UI 首轮 22 项中 21 项通过；“关于”入口因新增设置内容移出可见区，已修正滚动定位。
  受影响的 6 项 UI 再跑通过，包括全部 F 流程及该“关于”回归；覆盖合计 22 条 UI 路径。
  `/tmp/trainote-health-integration-skeleton-final.xcresult` 的 UI 均通过，但其中早期合成测试
  曾错误复用 SwiftData 子对象而崩溃；已改成独立对象，修正后全部单元测试结果以上一条为准。
- 构建实际包含新增文件。XcodeGen 2.46.0 的完整 binary + SettingPresets 必须一起使用；
  只复制 binary 会丢默认产品名设置。工程登记另行机械提交，不修改 project.yml/CI。
- 深色用仅 DEBUG 的 `-ui-testing-dark` 显式主题注入；普通 `-AppleInterfaceStyle` 参数在本机未生效，
  不把该旧截图当深色证据。最终深色大字号复测通过，截图已人工查看：
  `/tmp/trainote-health-integration-dark-verified.xcresult`。大字号与引导附件保存在 xcresult。
- 普通合并 `28500cf` 并接入原子手动目标编辑后：全部 **113 项单元测试通过，0 失败**，含新增
  3 项旧目标基线、过期草稿/重新确认、无效目标原子性测试。
  结果 `/tmp/trainote-health-integration-goal-base-units.xcresult`。
- 本次基线另验证只读存储的目标保存失败提示，以及从设置保存/再次修改目标后今日页立即回显。
  后者结果 `/tmp/trainote-health-integration-manual-goal-ui.xcresult`。累计覆盖 23 条 UI 路径，
  为上述分次运行结果，不表示本次 head 已完整重跑 23 项 UI；联合集成后仍需完整验收。
- `git diff --check` 和 planning 链接审计通过。未运行真实 HealthKit、供应商、签名、TestFlight 或部署。

复现：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote \
  -destination 'platform=iOS Simulator,id=<本任务专用UDID>' \
  -derivedDataPath /tmp/trainote-health-integration-derived \
  -only-testing:TrainoteTests CODE_SIGNING_ALLOWED=NO test
```

UI 使用同一命令替换为 `-only-testing:TrainoteUITests`。使用本机实际 UDID，不复用其他任务设备。
