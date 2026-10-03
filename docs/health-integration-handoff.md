# Health integration (task F)

2026-10-03：B/C/E 真实生产装配已进入 PR #9，分支 `agent/health-integration`，工作树 `392a/trainote`。
本任务交付可审阅 PR，由主协调统一审阅和合并。A 的 PR #4 已于 09:21（Asia/Shanghai）合入正式 main；F 普通合并准确 main `b24cd108222134d3cd3ba1d4169031cebc6226b3` 为 `f81651bf10951952725e12a3dae53b1bfac5d300`，合并 tree 与 `5aca4aa` 完全相同。包含 E 日统计窗口、A 持久撤回及真实报告服务重启回归的历史固定代码 `405d2f4` 曾完整通过 268 单元和 31 UI；后续 UI 修复另有定向证据。最新提交的 CI 以 [PR #9 检查](https://github.com/Jerryszz02/trainote/pull/9/checks) 为准，不能借用旧 head 的通过结果；真机、科学有效性和发布验收仍未完成。

## 固定依赖与工程

按主协调指定的准确提交合入，未复制算法或另建共享 DTO。除表内单独注明的 B 显示补丁外，依赖均普通合并：

| 依赖 | 已消费固定提交 | 当前用途 |
| --- | --- | --- |
| A/D 基础 | `967fa535`、`28500cf`、`59766ea` | schema 1.2、原子目标写入、备份 Date 精度 |
| C | `2d2703ef28033d952d0d61a3b950003afe5e97f2` | 真实恢复服务、审核映射、体感/校准和恢复页 |
| B | `27a026f88f1e6d21158313af6d1fb7e619ad82e0` | 趋势计算、目标采用/撤销、历史日目标和趋势页 |
| B 显示精度 | `94b502f21c7dd3a9e86709abd9b2e96998002ba5`，按主协调明确要求仅 cherry-pick 为 `92b017e` | 调整量使用两个展示目标相减；内部计算和保存精度不变 |
| A 持久撤回 | `149bbdb0a3f67f19d56383ea68b3d0654aef65fc`（含 `a343be8`） | 每 scope 独立日志覆盖旧主状态，新显式 grant 原子确认；默认 init/协议兼容 |
| A 推荐快照 | `d4ee483a5ff355e94e813b9ff760cb6333295772` | 一次求值收集推荐 facts 与候选；最终报告指纹包含上下文 |
| E | `a36d640ee4ba4b3fe375e477ec08c109ebac9fa2` | 真实报告缓存、最小化、客户端校验及撤回生命周期 |
| E 日桶边界 | `52fbb32110874f54d62d1c017f000b18149a4da0` | 保留真实 B 本地事实/依赖，仅 wire 投影已观测窗口，拒绝未来原始值 |
| E 重启撤回回归 | `415db319170247189bc9b8a9d270693ab38f33f5` | 真实 AIReportService 配合 fake transport，覆盖主授权文件写入失败、远端删除成功后的重启 |
| D 生命周期 | `a363195d480d1412d496336b674efc7c09dafaa8` | 普通合入 `e794a3c` 的 SceneKit teardown 修复 |
| 正式 main / A PR #4 | `b24cd108222134d3cd3ba1d4169031cebc6226b3`，普通合入 `f81651bf10951952725e12a3dae53b1bfac5d300` | A head `4ebdd3fe1a12b7cb4e5b1073aa36158a9949acad` 经 CI 后 squash 合并；保留 F 完整装配、历史复制语义、公共 helper `18793f4`、UI 修复 `d0fd48b` / `5aca4aa` 和 45 分钟工作流 |

正式 A/B/E/D main `60c02d7` 普通合并为 `43d11e4`，相对 F 前一提交仅更新 B/E 两份上游交接文档。C 的 PR #8 随后于 11:05:58（Asia/Shanghai）经当前提交 CI 后 squash 为 main `c439350e52baf15d3c1d5a3528be112c1ea6928d`；F 在保存失败 CI 产物后普通合入 `f66997bd0fb87cf1c976980434e9851b6c2205c7`，仅更新 C 交接文档及 RIR UI 测试对既有公共输入 helper 的调用。两次同步均未改变已装配的生产源码；XcodeGen 工程与合并前相同，诊断和 45 分钟工作流保留。核对记录 `/tmp/trainote-f-main-60-merge-verification.json`、`/tmp/trainote-f-main-c439-merge-verification.json`。

`.pbxproj` 仅使用本树 XcodeGen 2.46.0 完整运行时从 `project.yml` 机械生成，工程登记单独提交；schema、entitlements 未改。主协调在确认旧 CI 30 分钟被取消后，授权仅把 `.github/workflows/ios.yml` 的作业时限改为 45 分钟，独立提交 `b3b2a1b`，测试/审计/证据上传步骤未减少。
2026-10-03 12:09（Asia/Shanghai）交付快照：PR #9 base 为 `main`，A/B/C/D/E 已合入正式 main `c439350` 并经 `f66997b` 同步到 F。上一固定 head `3df6541` 的完整 CI 为 297/299 通过，训练等待及固定餐输入已通过，仅断开确认和体感菜单失败。F 安装与 CI 相同的 iOS 26.4.1/23E254a 后复现两项失败；修复 `d1a343354c3f94191061b9e95a4ac813cb11cfdf` 将今日设置和体感弹窗统一交由 NavigationStack 外的 AppShell 呈现，原表单、服务、导航及业务断言保留。同运行时两项原路径及完整健康/RIR 11 项通过；主协调已审阅固定 diff，并在独立 iOS 26.5 设备确认两项兼容回归通过。新 head 仍须完整 CI；本次本地通过不替代 CI，也不声称已证明 Apple 内部机制。

## 页面与数据入口

- 五 Tab 各自保留 NavigationStack。资料库从今日/训练/饮食进入对应分区；设置、手动目标、备份、周回顾和原训练/饮食入口继续可用。首启引导、今日设置及今日体感由 AppShell 的统一 sheet 呈现，今日模板目的页注册保留；关闭弹窗仍执行原刷新及提示回调。
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

## 已闭合边界与当前待办

E `ReportFactSelection.wireWindow` 原先拒绝真实 B 当日 `weight.smoothed` 等日桶，导致本地报告失败。`52fbb321` 已普通合入 `27d7e17`，工程登记为 `f0e6346`；B 本地事实和依赖完整保留，wire 只投影已观测区间，未来原始健康数据仍拒绝。原 5 项 F 报告组合测试和 4 项 E 日期/DST 边界测试全部通过，真实基础报告→查看依据→只读历史 UI 也通过。

公共输入 helper 由 F 单独维护。`7dd8390` 的焦点/键盘处理之后，`18793f4ca2f2e780273aed98649ba5fc8d3f713e` 将固定搜索框排除出表单行滚动，并在一次输入后等待精确读回，未降低业务断言。后续 `d0fd48b3ca51c7d3f302f39662c2aff006c89372` / `5aca4aa749273a5600534b903aa6914c187b8aa6` 只修改三份 UI 测试：等待训练导航就绪、使用单次 0.15 秒触按并核对实际结果，以及固定趋势日期断言的中文 locale、同一本地时区和点击撤销前采样的参考时间。这些早期触按调整的根因当时未证明，不能将本地通过视为 CI 闭合。后续证据确认当前训练失败时页面实际已切换，是复合 AX 查询被外层等待中断；`9c53b39b6a437d99bacf8ae2a48060ff1c0ab460` 改为等待唯一目的页控件，再分别断言原有导航状态。固定餐输入前的无滚动重复聚焦打开自动填充弹层；`e9b2d5be41c32becf8275dc1d7f163845c29e407` 仅在实际滚动后重新聚焦，保留一次输入和精确读回。后续 `3df6541` CI 已确认这两项修复通过；当时未改的断开确认和体感菜单仍失败，取证与实际修复见下文。

诊断提交 `82580eea264b7d18f64cc8f3719a5d89d0b62343` 单独记录缺失的 App 动作阶段，仅在 DEBUG 且既有 `-ui-testing` 开关启用时输出事件名、单调时间和布尔值；不记录健康内容、不持久化日志、不增加业务状态或触按。断开确认记录 closure 入口、执行开始/成功/失败/结束；体感记录页面出现/退出与选择变化。两条原 UI 用例失败时各只补一份画面、完整控件树和原生菜单查询结果。该提交用于取得 CI iOS 26.4.1 的缺失证据，不是两项健康失败的修复；主协调已核对固定 diff、原始 trace、附件和 Debug/Release 二进制并批准推送。

健康弹窗修复 `d1a3433` 仅改 AppShell、TodayView、TodayRecoveryCard 三文件。原 CI 中断开确认未到达动作钩子，体感菜单触按后 sheet 内部 AX 子树更新并出现快速生命周期回调；这些证据不能单独证明 SwiftUI identity 或 State 丢失。在同版本运行时复现后，将今日弹窗呈现移到各 Tab 的 NavigationStack 之外，保留所有原控件、数据操作、模板导航和关闭回调；两条完整业务路径及相关 11 项 UI 回归通过。临时探针与未采用候选均已移除，`82580ee` 诊断保持不变。调查、失败候选与原始证据保存在 `/tmp/trainote-f-ci37090341843-investigation.md` 及 `/tmp/trainote-f-health-presentation-candidates/manifest.json`，新固定 head 的完整 CI 仍待验证。

主协调复现的 LocalConsentStore 写盘失败后重启读回旧 granted 路径由 A `149bbdb0` 统一修复，F 已普通合入 `7f84015` 并用 `35ec339` 登记测试。主状态写盘失败时已持久的日志仍覆盖旧授权；不在 F 建立第二套标记。

E `415db319` 已普通合入 `405d2f4`，没有修改生产报告逻辑。测试重新打开实际存储、缓存和服务，在 transport 待撤回标记已清除时仍拒绝 AI 授权，并确认远端请求与健康 fresh 请求均为零、独立健康授权保留。该合并仅新增这项测试；重新生成工程无差异。

## 验证证据

环境：Xcode 26.6；F 专用 iOS 26.5 模拟器 `B4FF3837-B382-4AD5-A24A-FEAC05A0ECAB`，以及为 CI 复现新增的 iOS 26.4.1/23E254a 模拟器 `22052486-7D55-461B-A2AB-9634B87F727E`。DerivedData `/tmp/trainote-health-integration-derived`。F 未操作其他任务的工作树、服务或模拟器；下列主协调独立验收由其自行运行。

- **最新完整失败 CI**：`3df6541851734fd3f9b6c9a1a32c6331ea7c11b5` 的 [iOS run 37090341843](https://github.com/Jerryszz02/trainote/actions/runs/37090341843) 于 11:06:48 结束，299 项中 297 通过、2 失败、0 跳过，非超时；268 单元及 29/31 UI 通过。仅断开确认结果等待与体感菜单出现等待失败；`e9b2d5b` 和 `9c53b39` 对应路径通过。完整产物 `/tmp/trainote-f-ci-37090341843-evidence`，App 事件、附件和系统日志 `/tmp/trainote-f-ci37090341843-diagnostics/`。
- **同运行时复现及修复**：同步 main 后、未修改健康源码的 `f66997b` 在独立 iOS 26.4.1/23E254a 上复现原两项失败，`/tmp/trainote-f-health-ios2641-baseline.xcresult` 为 0 passed、2 failed。外层 presenter 修复后，同两条原测试完整通过，`/tmp/trainote-f-health-ios2641-shell-presentation-ready.xcresult` 为 2 passed、0 failed/skipped；事件包含断开 confirmation→begin→success→end 和三次体感操作，没有失败前的快速生命周期反复。
- **固定修复回归及审阅**：`d1a3433` 的完整 HealthIntegrationUITests 加 RecoveryRIRUITests 在上述 26.4.1 设备通过 11/11、0 failed/skipped（279.826 秒），产物 `/tmp/trainote-f-health-ios2641-routing-regression.xcresult`。主协调接受树 `9b7f32453e376333cc0b828a86327fa04c2fe7d2` 与固定源码 tree 相同，并在独立 iOS 26.5/23F77 设备运行原两条兼容回归，2/2、0 failed/skipped，产物 `/tmp/trainote-health-acceptance-sheet-d1a3433.xcresult`。三个修改 Swift 文件严格格式检查及 diff 空白检查通过。测试、825 诊断、工程和工作流均未因修复改变；不重复本地全部 299 项，新 head 将运行完整 CI。

- **正式 main 同步**：`f81651b` 的第二父提交是准确 `b24cd108222134d3cd3ba1d4169031cebc6226b3`。App 装配和历史复制冲突保留已有 F 实现，工程重新经 XcodeGen 生成后无差异；其 tree 与 `5aca4aa` 同为 `bb5d9d35253513966c441f77ccfa1e393bffc2de`。实际冲突定向回归 `RecoveryWorkflowTests.testNewWorkoutDefaultsWorkingHistoryPreservesRoleAndRIRAndRepeatClearsThem` 于 09:26 通过，1 项、0 失败，证据 `/tmp/trainote-f-main-b24-history-conflict.xcresult`。源码完全相同，因此未重复本地整套 299 项。
- **后续 UI 修复**：编辑前使用英文 runner / US region 复现趋势日期断言的中文与英文格式差异，3 项 UI 中 2 通过、1 失败，证据 `/tmp/trainote-f-ci-187-locale-repro.xcresult`；三个触按失败未本地复现。`d0fd48b` / `5aca4aa` 的四条原 CI 失败路径随后 4/4 通过（221.548 秒）；最后把日期参考点固定为点击撤销前，趋势采用/撤销另 1/1 通过（108.100 秒）。对应产物 `/tmp/trainote-f-ci-187-four-path-fix.xcresult`、`/tmp/trainote-f-ci-187-trend-final.xcresult`。主协调确认接受树 `f0da9ab3f775246b3e997fce1deb5658b56444a9` 与 `5aca4aa` tree 相同；该代码审阅不等同 CI 通过。
- **历史 CI 失败**：`18793f4` 的 [iOS run 37079917932](https://github.com/Jerryszz02/trainote/actions/runs/37079917932) 于 08:36 结束，268 单元通过，31 UI 中 4 项失败，非超时。截图与日志显示三次触按未产生预期结果及一次日期格式差异；保留原失败证据，不因本地通过将该运行写成成功。
- **前次失败 CI**：`5aca4aa` 的 [iOS run 37084609179](https://github.com/Jerryszz02/trainote/actions/runs/37084609179) 于 09:38:53 结束，268 单元通过，31 UI 中 4 失败，未超时；趋势日期路径已通过。同 head 的 [服务端 run 37084609091](https://github.com/Jerryszz02/trainote/actions/runs/37084609091) 已通过。失败为训练标签就绪等待、固定餐名称精确读回、断开确认后的结果等待、体感菜单出现等待。第一项已确认训练页和标签正确，AX 查询分别耗时 5.765 秒和 2.870 秒，第三项查询被外层 10 秒等待中断；固定餐视频显示第二次聚焦出现自动填充弹层。两项健康失败中，断开弹层消失但没有结果，体感触按进入 UIKit 菜单处理但没有持续可见的选项；现有证据不能证明断开动作是否执行或菜单为何关闭。原日志 `/tmp/trainote-f-ios-ci-37084609179.log`、完整 xcresult `/tmp/trainote-f-ci-37084609179-evidence` 已保留；该轮 CI 为 iOS 26.4.1，当时本地仅有 iOS 26.5；后续已安装匹配运行时并复现，见上方最新证据。修复后新 head 仍须独立通过 CI。
- **本轮两个实际修复**：`e9b2d5b` 的固定餐与分量/历史路径 2/2 通过（191.408 秒），证据 `/tmp/trainote-f-ci-5aca-helper-focus.xcresult`。专用模拟器冷启动后，`9c53b39` 的训练路径与两条未改健康路径 3/3 通过（114.188 秒），证据 `/tmp/trainote-f-ci-5aca-cold-transitions.xcresult`；健康路径的本地成功不闭合 CI 失败。主协调已独立审阅两笔固定 diff 和原始证据并接受，无需因相同源码再跑全部 299 项。
- **独立诊断验证**：`82580ee` 的两条原健康路径 2/2 通过（62.318 秒），产物 `/tmp/trainote-f-health-diagnostics-normal.xcresult`，13 条 App 事件摘录 `/tmp/trainote-f-health-diagnostics-normal-trace.txt`。一次临时 `XCTExpectFailure` 探针验证了单次三份可读附件，产物 `/tmp/trainote-f-health-diagnostics-attachment-probe.xcresult`；探针已移除，不计作业务回归或 CI 复现。Release Simulator 构建通过，Debug 中的 10 个诊断标记在 Release 二进制均不存在，记录 `/tmp/trainote-f-health-diagnostics-release-exclusion.json`。三个修改 Swift 文件严格 lint 通过；SettingsView 与父提交有相同的 8 项既存格式问题，没有新增 lint 项；diff 空白检查通过。
- **历史完整运行**：`405d2f4` 的全部 268 单元、31 UI 通过，07:24 完成；`/tmp/trainote-health-integration-full-final.xcresult` 汇总为 299 passed、0 failed、0 skipped。命令没有 `only-testing` 或排除项，完整覆盖 E 真实服务重启撤回、建议采用、真实报告、D 场景拆卸、体感、目标历史、原训练/饮食/备份及趋势采用/撤销。
- **后续显示修复**：主协调从截图发现 2240 与 2000 的目标显示配上 +242 原始差值；B `94b502f` 统一显示取整后，现有 `TrendAdoptionUITests` 增加精确“热量调整 +240 kcal”可见断言，同一真实采用/撤销路径再次通过。证据 `/tmp/trainote-health-integration-displayed-delta.xcresult`；内部计算与保存值未改，未无故重复整套本地回归。
- **主协调独立验收**：在与 `13619fc` tree 完全相同的接受树上，三个旧 CI 转场路径和趋势采用/撤销共 4/4 UI 通过，产物 `/tmp/trainote-health-acceptance-final-ui-13619fc.xcresult`；E `415db319` 真实服务撤回回归另独立 1/1 通过。该证据与 F 自身完整运行分开记录。
- 当前提交的 CI 结果见 PR 检查；服务端历史 65 项测试和 synthetic-offline demo、规划链接审计、1,324 条动作记录方式审计已通过；本轮格式与 diff 检查范围见上述诊断验证。下列保留历史失败及修复定位，不将分批结果相加替代完整运行。
- 初始骨架 94 单元、原子目标接入后 113 单元、C 真实装配后 145 单元分别通过；这些是历史阶段结果，不当作最终 head 全量回归。
- 公共 UI 输入修复 `3a093ed7c3b4f421fdb824d88e0d592c577063ff` 仅改两个原有测试文件。中心点击、等待键盘、全选替换、数值零/占位语义和回读验证，保留业务断言。取消编辑后重新打开原训练核对名称。四条原失败路径全部通过：`/tmp/trainote-health-integration-ui-input-final.xcresult`。
- 采用修复 `491a991` 的 8 项真实仓库/C 集成测试全部通过，含同 ID 修改体感/睡眠/轻微酸痛拒绝、仅前进 2 秒成功。`/tmp/trainote-health-integration-report-boundary.xcresult` 同时记录了 4 项报告边界失败，不是整次成功。
- D 原始崩溃为真实 RecoveryView 切列表时 `C3DSceneLock → SCNView.projectPoint → projectedAnchors → layoutSubviews` 的 EXC_BAD_ACCESS。原证据 `/tmp/trainote-health-integration-recovery-ui-ready.xcresult`；失败测试保留，D 修复后同一路径通过，继续验证肌群选择、疼痛保存与方法说明。
- `a7e418c` 通过 244 项单元和 2 项真实 UI（恢复原崩溃回归、按建议新建减量训练），结果 `/tmp/trainote-health-integration-advice-recovery.xcresult`。此轮明确排除了已知失败的 4 项报告组合测试。
- `/tmp/trainote-health-integration-ui-regression.xcresult`：16 项撤回/建议单元通过；29 项 UI 中 28 项通过，唯一失败为公共 helper 的零值营养输入全选。该轮明确排除当时阻塞的报告 UI。
- `/tmp/trainote-health-integration-real-report-ui.xcresult`：9 项报告相关单元及报告真实 UI 通过；同轮公共输入辅助用例仍失败，不把整轮写成通过。已查看报告截图，未知值保留未知，没有未启用的 AI 同意入口。
- Node 22.23.1 下代理 `npm test` 65/65 和 `npm run demo` synthetic-offline 通过，日志 `/tmp/trainote-health-integration-server.log`。没有真实供应商请求。
- 公共 helper `7dd83902594c00d524425f7097d302ff16fbbe9b`：`/tmp/trainote-health-integration-ui-helper-adoption-final.xcresult` 的双次搜索、固定餐、手动目标、真实 70 kg 报告 UI 通过；该轮趋势 UI 滚动断言失败，未称整轮成功。`/tmp/trainote-health-integration-consent-and-adoption.xcresult` 再验分量→最近记录→周回顾通过，且包含 A/E 的全体 267 单元通过，趋势采用/撤销 UI 同轮通过，整个运行成功。该测试以 DEBUG 且内存库中的旧版目标 fixture 开始，身体资料与体重均通过真实表单录入，验证 2000→2240→撤销恢复 2000、七日后复核、原建议模式和首页读回；不预造 proposal 或生成 revision。源码提交 `6926fb4`，工程登记 `e0ef426`。
- F 的 `c97e4f7` 只同步设置/体感表单转场和动态 Form 结果行，业务断言完整保留；三项定向 UI 全部通过，证据 `/tmp/trainote-health-integration-settings-transitions.xcresult`。主协调另独立确认 `7dd8390` 的双次搜索、分量/周回顾和旧目标编辑三项通过，证据 `/tmp/trainote-health-acceptance-input-7dd8390.xcresult`。
- 已查看趋势撤销后的目标/模式截图与真实报告依据截图：恢复为 2000 kcal、原建议模式保留，报告读回表单保存的 70 kg 并标明手动来源；缺失指标仍为未知。
- 原 `0ac8091` CI `37071374776` 因 30 分钟作业上限取消，另有旧报告/helper 及 F 表单转场等待失败；这些路径现已包含在本地完整成功运行。旧 CI 不能作为当前 head 的 CI 通过证据。

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
