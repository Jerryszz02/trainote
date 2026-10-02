# Health integration (task F)

2026-10-03：B/C/E 真实生产装配已进入 PR #9，分支 `agent/health-integration`，工作树 `392a/trainote`。
本任务只交付可审阅 PR；不自行合并默认分支、发布、部署或上传真实健康数据。当前仍有 E 的日统计窗口校验阻塞，不能声明最终验收完成。

## 固定依赖与工程

按主协调指定的准确提交普通合并，未复制算法或另建共享 DTO：

| 依赖 | 已消费固定提交 | 当前用途 |
| --- | --- | --- |
| A/D 基础 | `967fa535`、`28500cf`、`59766ea` | schema 1.2、原子目标写入、备份 Date 精度 |
| C | `2d2703ef28033d952d0d61a3b950003afe5e97f2` | 真实恢复服务、审核映射、体感/校准和恢复页 |
| B | `27a026f88f1e6d21158313af6d1fb7e619ad82e0` | 趋势计算、目标采用/撤销、历史日目标和趋势页 |
| A 推荐快照 | `d4ee483a5ff355e94e813b9ff760cb6333295772` | 一次求值收集推荐 facts 与候选；最终报告指纹包含上下文 |
| E | `a36d640ee4ba4b3fe375e477ec08c109ebac9fa2` | 真实报告缓存、最小化、客户端校验及撤回生命周期 |
| D 生命周期 | `a363195d480d1412d496336b674efc7c09dafaa8` | 普通合入 `e794a3c` 的 SceneKit teardown 修复 |

`.pbxproj` 仅使用本树 XcodeGen 2.46.0 完整运行时从 `project.yml` 机械生成，工程登记单独提交；原 CI、schema、entitlements 未改。
PR base 保持 `agent/health-foundation-integration`，由主协调处理后续合并。

## 页面与数据入口

- 五 Tab 各自保留 NavigationStack。资料库从今日/训练/饮食进入对应分区；设置、手动目标、备份、周回顾和原训练/饮食入口继续可用。
- 趋势入口首次明确选择“启用每周建议”或“保留原模式并查看趋势”。升级和浏览不会改变旧手动目标；采用、撤销、自动模式与基线确认使用 B 页面和 A 原子事务。
- 旧目标编辑器捕获 `goalRevisionState`，通过一次 `applyGoalRevision` 保存；过期草稿保留，需明确载入最新状态再确认。
- 今日营养进度和周回顾按各日本地日末查询 `TrendHistory.effective`。历史未知不拿今天目标回填；完全没有目标历史时只对今天兼容旧目标。未知目标不画零进度。
- 恢复页及今日体感使用同一个 C `RecoveryService` / calibration control。今日反馈复用同日同一时区记录；跳过不写入，清空既有答案使用 C 保存语义。
- 今日建议读取真实 B/C/F 结果。恢复页“训练建议”需要显式选择本次模板，可另选备选模板和可训练日；不从最近编辑模板推断长期计划。

## 推荐采用

`TrainingRecommendationProvider` 用 C 的审核映射和 B 的 `diet.targetDifferencePercent` 事实建立规则上下文；未审核动作、未支持记录方式或 unallocated records 不会得到无条件 keepPlan。
`TrainingRecommendationRules.snapshot` 一次 evaluate 返回候选、理由 facts 和 contextFingerprint。非空 exclusionCodes 是已批准候选的约束，不等于候选无效。

`RecommendationWorkoutFactory` 在采用前读取新记录和完整模板，不复用旧健康快照。显示 actionID 含读取时间，因此匹配的是新规则仍批准的动作、肌群、参数范围、约束、完整模板修订、同一本地日和上下文；纯时钟前进不阻止采用。
同时核对阻塞肌群、目标/训练频率、全身状态及实际体感内容。同一条 check-in 的正常/好、轻微/无酸痛、睡眠体感等修改也要求重新确认，不能只比较 tired/显著酸痛布尔值。

采用只新建进行中 Workout，已有进行中训练会阻止重复创建。原模板和历史不改；所有新组清除完成状态和实际 RIR，提高 RIR 只记录训练提示。
规则版本 `training-candidates-p1` 的最近 24 小时、保留 50%–75% 组数、至少 2–4 RIR 是待验证的工程初值。

## 报告与撤回

- App 启动只创建一次 `HealthReportIntegration` 和 `AIReportAssembly.make`，注入真实 B/C 计算器。`proxy: nil`，AI 仍待开放，不预存 AI 同意，没有真实网络传输或设备凭据生成。
- 常驻 provider 在 A builder 的 MainActor 同步 snapshot 调用中重读当前模板、选择和可训练日；该调用发生在 fresh HealthKit await 之后。每次远程报告仍由 E 调用 A prepare，使用最终 ReportInput 指纹；F 不传旧 prepared input 给传输。
- 今日“基础报告与历史”连接 `AIReportCard`、当前事实依据和历史只读页。本地输入仅用于 fallback；缺失值为未知，基础报告不进入 AI 历史缓存。历史候选没有直接采用按钮。
- E 在缓存前注册持久 cache 与内存 service invalidator；F 另注册自己的显示状态 invalidator。健康断开使用 A `disconnectAndDelete`，保留手动记录，删除健康依赖报告。
- 关闭 AI 委托 E `closeAI`；启动/前台先恢复待撤回状态。失败不清 pending marker；删除 AI 历史调用 `deleteAIReports`，与手动记录、健康连接独立。
- 模板或可训练日变化使当前报告失效；保存本地记录也取消当前工作和卡片，历史快照保留。前台健康同步完成后重算已请求的本地基础报告；配置远程服务时仍走明确报告请求入口。

## 当前阻塞

E `ReportFactSelection.wireWindow` 目前只允许推荐事实使用截至次日的日桶。真实 B 的 `weight.smoothed` 总有该窗口；当天 `weight.representative`、满足条件后的 `energy.initialEstimate` 和 `weight.targetWeeklyChangePercent` 同样可能越过 asOf。
真实组合测试已复现 `weight.smoothed` 被拒绝，导致本地基础报告也不能生成。最小测试 `HealthReportIntegrationTests.testRealTrendDayBucketsAreAcceptedByReportBoundary` 保留；不删 B facts、不改变其日桶语义。唯一修复方为 E，等待主协调提供新固定 SHA。

## 验证证据

环境：Xcode 26.6 / iOS 26.5；专用模拟器 `B4FF3837-B382-4AD5-A24A-FEAC05A0ECAB`，DerivedData `/tmp/trainote-health-integration-derived`。其他工作树、服务和模拟器未操作。

- 初始骨架 94 单元、原子目标接入后 113 单元、C 真实装配后 145 单元分别通过；这些是历史阶段结果，不当作最终 head 全量回归。
- 公共 UI 输入修复 `3a093ed7c3b4f421fdb824d88e0d592c577063ff` 仅改两个原有测试文件。中心点击、等待键盘、全选替换、数值零/占位语义和回读验证，保留业务断言。取消编辑后重新打开原训练核对名称。四条原失败路径全部通过：`/tmp/trainote-health-integration-ui-input-final.xcresult`。
- 采用修复 `491a991` 的 8 项真实仓库/C 集成测试全部通过，含同 ID 修改体感/睡眠/轻微酸痛拒绝、仅前进 2 秒成功。`/tmp/trainote-health-integration-report-boundary.xcresult` 同时记录了 4 项报告边界失败，不是整次成功。
- D 原始崩溃为真实 RecoveryView 切列表时 `C3DSceneLock → SCNView.projectPoint → projectedAnchors → layoutSubviews` 的 EXC_BAD_ACCESS。原证据 `/tmp/trainote-health-integration-recovery-ui-ready.xcresult`；失败测试保留，D 修复后同一路径通过，继续验证肌群选择、疼痛保存与方法说明。
- `a7e418c` 通过 244 项单元和 2 项真实 UI（恢复原崩溃回归、按建议新建减量训练），结果 `/tmp/trainote-health-integration-advice-recovery.xcresult`。此轮明确排除了已知失败的 4 项报告组合测试。
- 新一轮完整 UI（暂不含上述报告路径）和撤回恢复测试正在执行；结果待回填。最终 E 修复后需重跑全部单元和报告路径，确认最终 head CI。

## 真机及发布剩余条件

尚未验证 iOS 17 真机、HealthKit entitlement/签名、拒绝/部分授权/系统撤回、锁屏与后台同步、真实 App Attest、DeepSeek API 条款/真实供应商回路、完整 VoiceOver、最终商店截图与公开隐私页部署。模拟器和合成测试不证明生理有效性或真实用户处理可上线。发布清单位于 [app-store/release-checklist.md](app-store/release-checklist.md)。

复核命令使用本任务实际 UDID：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote \
  -destination 'platform=iOS Simulator,id=B4FF3837-B382-4AD5-A24A-FEAC05A0ECAB' \
  -derivedDataPath /tmp/trainote-health-integration-derived \
  -parallel-testing-enabled NO -only-testing:TrainoteTests CODE_SIGNING_ALLOWED=NO test
```

UI 改为 `-only-testing:TrainoteUITests`。planning 文档审计只证明本地索引/链接，不替代产品验证。
