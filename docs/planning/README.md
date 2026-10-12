# Trainote 规划索引

## 项目是什么

Trainote 是一款以本地记录为基础的 iPhone 健身与饮食 App，记录力量/有氧训练、训练模板及每日卡路里、碳水、蛋白质和脂肪。默认分支界面以简体中文为主；本分支已实现中英双语，验证与未验项见本地化计划第 11 节。动作文字目录来自 `hasaneyldrm/exercises-dataset` 的固定版本，人体图和演示媒体另有各自的来源/许可记录，见 [视觉资源说明](../nutrition-exercise-visuals.md)。

**计划阶段历史核查（2026-10-12，Europe/London）：** fetch 后 canonical `main` 与 `origin/main` 均为 `c970330a33208b9f7862ae6e960d5f5b98a17a1f`，代码诊断以此为基线。用户确认 Xcode 直装；连线后读取到 iPhone 17 Pro Max、iOS 26.6.2、Trainote 1.1（Build 2），但安装包的源码提交和 Debug/Release 仍待确认。Instruments 将设备列为离线，短时附加采样超时，没有有效性能 trace。详见 [真机性能计划](device-performance-plan.md)。

计划阶段仅新增三份计划。2026-10-12 用户已批准三计划并授权独立实现；本工作树执行双语计划，**尚未合并或发布应用改动**。当前 main 已包含开发签名准入与营养/视觉资源改动；完整 AI 接通仍见 [接通计划](ai-report-enablement-plan.md)，本轮未验证真实服务。旧文档内的构建/测试数量是对应日期和提交的历史证据，不代表本次性能或产品验收。

**历史记录：2026-10-03 13:56:54（Asia/Shanghai）** A–F 功能代码合入 main `06b2560` 并完成当时的仓库工程验收。F 提供五 Tab、趋势/恢复分析、训练建议、历史营养目标及本地报告入口；当时默认无远程 AI transport。规划 PR #3、A 的 #4、B 的 #6、C 的 #8、D 的 #5/#10、E 的 #7、F 的 #9 均已合并；详见 [交付快照](health-analysis-delivery.md)。历史实施对话使用 max；该记录不代表真实服务、真机兼容或发布验收。

## 文档信息

- 更新时间：2026-10-13（Europe/London）
- 请求：三份计划已获批准并分支实施；本工作树负责中英双语实现与验证。
- 工作模式：已获授权并行实现；本分支仅负责多语言实现与验证，其他两条线保持独立。
- canonical 项目根目录：`/Users/jerryszz/Desktop/Projects/trainote`
- 计划阶段证据：Git refs/工作树、App 启动与导航、动作库/搜索、编辑保存、分析仓库/刷新、图片视频/3D 生命周期、设置/说明/报告文案、现有测试源文件、动作双语字段完整性，以及 devicectl 的设备/安装包/进程读取。计划阶段未运行应用测试或构建；本分支的 Simulator 构建与测试结果见 [双语实施记录](localization-plan.md#11-本分支实施与验证2026-10-13)。未修改真机数据。
- 历史工作树位置（不代表当前仍保留）：F 为 `/Users/jerryszz/.codex/worktrees/392a/trainote`；2026-10-03 文档收尾为 `/Users/jerryszz/.codex/worktrees/health-docs-closeout/trainote`。
- 固定交付证据：F 最终 head `f24b903236bb067ac02d3192c64db50df69815c4` 的 [完整 CI 37098998968](https://github.com/Jerryszz02/trainote/actions/runs/37098998968) 于 13:46:36（Asia/Shanghai）通过 299/299（268 单元、31 UI，0 失败/跳过/预期失败）。PR #9 于 13:56:54 squash 为正式 main `06b25608da2dfed720698f91106f90c429070aea`；两者 tree 均为 `6c1a7ef258d9512b80f2613585cd9bee25e32e7c`。初始 `967fa5351838240b2bb6ca0c5cb8e777530e54c4`、依赖同步、历史失败及修复固定点见交付快照和交接。
- F 历史实施检查证据：Git 状态与工作树、根 README、`project.yml`、已提交 Xcode 工程、AppShell/TrainoteApp、训练与营养模型、动作目录服务、备份服务、资料库/首页/设置页面、现有测试及 CI 配置；2026-10-03 状态收尾另核对 PR 合并 API、Git tree 和原始 CI 产物。原始论文与研究仓库见证据矩阵。
- F 已执行 Simulator 构建及单元/UI 测试；逐项结果在 [交接](../health-integration-handoff.md)。签名、真机和发布状态未验证，旧 1.1 记录仍为历史证据。

本文档区分本次静态检查与历史运行结果；未找到证据的发布信息继续标记为 `待确认`。

1.1 新增功能与可靠性规则以 [日常使用升级计划](daily-use-upgrade.md) 为准；下列文档保留基础架构约定。

健康分析改变新版本的数据、网络和导航边界；旧 v1 文档中的“无 HealthKit/无网络/无体重分析”是旧版本背景，不能覆盖已合并实现。相应源码、提案和交接共同说明实际行为与尚未验收的外部条件。

## 从哪里开始

本次体验改进先阅读以下三份计划。默认顺序为性能 → 完整双语 → 交互收敛，三条线独立审查与验收；性能没有真机对比不能标为完成，其他两条线也不能仅靠编译通过验收。界面方案先保留五 Tab，四 Tab 的取舍见交互计划；所有说明文字集中到同一个离线页面。

1. [P0 真机流畅性](device-performance-plan.md)：实际安装基线、热点假设、同机测量、保存安全与回滚。
2. [P1 简体中文与 English](localization-plan.md)：默认系统语言、String Catalog、双语搜索、状态连续性及全页面覆盖。
3. [P1 第一次使用与说明收纳](first-use-interaction-plan.md)：三流程、首页线框、五/四 Tab 比较、单一帮助页面及验收任务。

以下为原有健康分析的历史交接入口，不能替代本次体验验收：

F 实施记录（2026-10-03）：B/C/E 已实际连接，训练建议会复核最新事实后创建新训练；报告支持当前事实、历史只读和撤回/清理。
见 [F 集成交接](../health-integration-handoff.md) 的精确提交、通过/失败产物和待验条件。历史 `405d2f4` 的 268 单元、31 UI 曾完整通过；后续显示取整和 UI 修复另有定向通过证据。`f81651b` 普通合并正式 main 后与 `5aca4aa` 源码 tree 相同，历史复制冲突回归 1/1 通过；后续 `e9b2d5b` 去除输入框无滚动时的重复聚焦，`9c53b39` 拆开训练目的页等待与独立断言，分别有 2/2 和 3/3 定向通过证据；这些修复随后在 `3df6541` CI 通过。该 CI 余下两项健康失败已在匹配运行时复现，`d1a3433` 修复后的 11 项健康/RIR 回归及主协调独立 2 项兼容回归通过，并在后续 `d57c3f8` CI 验证健康路径通过。该轮剩余固定餐缓存读回失败由 `e2de366` 最小修复，相关 2 项 UI 本地通过；最终 `f24b903` 完整 CI 299/299 通过。

1. 阅读已获批准的 [健康分析实施提案](health-analysis-plan.md)，遵循导航、目标调整、权限和计算边界。
2. 阅读 [研究证据与模型资产](health-analysis-evidence.md)，分清文献依据、产品参数与未验证部分。
3. 阅读 [并行交付计划](health-analysis-delivery.md)，遵循六条工作流、max 设置、A/D 固定基础依赖和集成授权。
4. 维护现有功能时阅读 [prd.md](prd.md)、[technical-design.md](technical-design.md)、[database-design.md](database-design.md) 与 [test-plan.md](test-plan.md)。
5. 接通真实服务阅读 [真实 AI 报告接通计划](ai-report-enablement-plan.md)，开发直装和固定文案报告已确认，主机/预算与实际签名能力仍待核对；旧 A–F 授权不替代本次部署授权。

## 规划文档

| 文档 | 用途 |
| --- | --- |
| [device-performance-plan.md](device-performance-plan.md) | 新增、计划中：实际设备/安装包核查、性能诊断假设、真机测量与改进顺序 |
| [localization-plan.md](localization-plan.md) | 已实现、本地自动验证通过：完整中英双语、语言设置、报告/动作呈现与兼容验收 |
| [first-use-interaction-plan.md](first-use-interaction-plan.md) | 新增、计划中：三条主流程、导航取舍、界面层级与通用说明集中收纳 |
| [ai-report-enablement-plan.md](ai-report-enablement-plan.md) | 真实接通计划及已授权开发签名准入的实施/验证记录，其余部署与接入仍待执行 |
| [health-analysis-plan.md](health-analysis-plan.md) | 新增：已批准的产品流程、算法候选、数据/API 契约、隐私、迁移和验收 |
| [health-analysis-evidence.md](health-analysis-evidence.md) | 新增：14 项营养/恢复来源、健康 AI 研究资产与推论边界 |
| [health-analysis-delivery.md](health-analysis-delivery.md) | 六条工作流、文件所有权、已执行依赖、实际 PR 快照及剩余验收 |
| [daily-use-upgrade.md](daily-use-upgrade.md) | 已有：1.1 日常使用与可靠性基线 |
| [prd.md](prd.md) | 定义用户场景、页面流程、业务规则和非目标 |
| [technical-design.md](technical-design.md) | 定义 App 壳层、状态归属、动作导入和隐私边界 |
| [database-design.md](database-design.md) | 定义 SwiftData 实体、关系、校验和历史快照规则 |
| [test-plan.md](test-plan.md) | 定义自动化与人工验收范围 |

## 有意跳过的文档

| 文档 | 原因 |
| --- | --- |
| `project-brief.md`、`user-flow.md` | 2026-10-12 重新评估：本次三流程/导航写入交互计划，各计划含目标、技术方案和验收，不另建重复文档 |
| `architecture.md`、`decision-log.md`、`security-privacy.md` | 新数据流、权限和供应商边界已写入健康分析提案，当前无需另建重复文件 |
| `api-design.md` | 已有 [Server/README](../../Server/README.md) 和 [客户端交接](../../Trainote/Services/AIReports/README.md) 维护真实代理/API 契约，无需重复 |
| `release-plan.md`、`operations-runbook.md` | 2026-10-10 重新评估：开通顺序与回滚纳入接通计划，现有 Server 文档和 App 发布清单继续作为细节入口；实施选定环境后同步，不重复建文档 |
| 独立开发者指南、根 README 和既有历史计划的全面整理 | 不在本次三份计划的范围；旧记录不能充当当前实现/验收状态，后续如需全库文档审计再处理 |

## 配套文档与历史证据

- [App Store 发布清单](../app-store/release-checklist.md)维护发布准备；发布前仍需核对实际权限和网络配置，当前不代表已获发布批准。
- [1.1 测试计划](test-plan.md)中的带日期执行表是历史记录；当前测试结果应取对应 PR head 的 CI 和本地运行产物。
- 新功能的工程验证、算法有效性、真实 AI 服务和发布条件分别见健康分析提案，不借用旧测试数量证明新功能。

## 文档检查记录

- 2026-10-12：新增三份计划，同步索引；设备元信息读取成功，Time Profiler 未产生有效采样。`git diff --check` 与 `python3 /Users/jerryszz/.agents/skills/plan-project-docs/scripts/audit_planning_docs.py --root /Users/jerryszz/.codex/worktrees/experience-improvement-plans/trainote` 通过；提交前同时检查暂存差异。这些只验证格式、索引覆盖和本地链接，不代表 App 测试。

- 提案阶段曾只检查 `docs/planning/`；F 实施阶段同时维护实际源码、测试、交接及发布资料。
- 2026-10-03 文档收尾只同步索引、实施提案、交付记录、证据矩阵开头和 F 交接的交付状态；研究矩阵、历史失败产物及外部待验条件保留。
- F 文档收尾检查命令：`git diff --check`，以及 `python3 /Users/jerryszz/.agents/skills/plan-project-docs/scripts/audit_planning_docs.py --root /Users/jerryszz/.codex/worktrees/health-docs-closeout/trainote`。
- 2026-10-03 上述两项文档检查通过。该审计只验证索引和本地链接，不验证论文结论、算法有效性或产品行为。
- 2026-10-10 先新增接通计划，随后按用户授权实施开发版准入并更新 Server 使用/认证说明、计划和索引。服务端 71 项测试、离线 demo、iOS Debug 无签名构建及 entitlement 格式检查通过。`git diff --check` 及 `python3 /Users/jerryszz/.agents/skills/plan-project-docs/scripts/audit_planning_docs.py --root <本次工作树>` 均通过；这两项仅验证文档格式、索引覆盖和本地链接。

## 当前约束与待确认

- 本次已授权三份计划的独立实现与验证；应用 PR 不自动合并或发布。以往某个 PR 的合并授权不能用于本次改动。
- 当前待确认：实际安装包源码/构建配置、Instruments 采样连通性、同设备同数据的性能证据；三流程实际走查与新用户验证；英文/大字号完整验收；四 Tab 是否值得采用，以及是否另行需要 kg/lb 单位切换。
- AI 服务的主机、预算和真机认证属于接通计划的独立待验事项，本轮不扩大到服务部署或健康数据外发。人体图/3D/媒体许可和真机表现分别核查，仓库存在资源不等于本次验证了渲染和内存。
- 当前代码配置 Swift 5.9 language mode、最低 iOS 17；F 在 Xcode 26.6 / Swift 6.3.3 / iOS 26.5 及匹配 CI 的 iOS 26.4.1 独立 Simulator 验证，详细结果见交接。
- A–F 的 `06b2560` 合并与 `f24b903` CI、2026-10-10 的开发签名准入合成测试/无签名构建均为历史记录。当前代码诊断基线为 `c970330…`；安装包即使版本号相同，也不能推定对应这一提交。后续改动须验证各自当前 head。
- 临时 Bundle ID 为 `com.jerryszz.trainote`，正式分发前需要与 Apple Developer 账号中的标识一致。
- 当前工程面向 iPhone、最低 iOS 17；现有界面中文优先、单位为公斤和公里。完整中英双语已在独立分支实现并通过本地自动验证；其他体验改进以各自独立计划/PR 为准。
