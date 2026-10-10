# Trainote 规划索引

## 项目是什么

Trainote 是一款中文优先、以本地记录为基础的 iPhone 健身与饮食 App，记录力量/有氧训练、训练模板及每日卡路里、碳水、蛋白质和脂肪。动作目录来自 `hasaneyldrm/exercises-dataset` 的固定版本，只内置 MIT 许可覆盖的文字和结构化数据，不分发需要单独授权的图片或 GIF。

**2026-10-10（Europe/London）本次核查：** fetch 后 canonical `main` 与 `origin/main` 均为 `170ad07`，App 仍以 `proxy: nil` 装配本地报告。完整 AI 接通仍处于[计划阶段](ai-report-enablement-plan.md)。用户已授权的开发签名准入开关已在本分支实现并通过本地验证，尚未合并/部署；未验证外部服务、账号或真机状态。

**历史记录：2026-10-03 13:56:54（Asia/Shanghai）** A–F 功能代码合入 main `06b2560` 并完成当时的仓库工程验收。F 提供五 Tab、趋势/恢复分析、训练建议、历史营养目标及本地报告入口；当时默认无远程 AI transport。规划 PR #3、A 的 #4、B 的 #6、C 的 #8、D 的 #5/#10、E 的 #7、F 的 #9 均已合并；详见 [交付快照](health-analysis-delivery.md)。历史实施对话使用 max；该记录不代表真实服务、真机兼容或发布验收。

## 文档信息

- 更新时间：2026-10-10（Europe/London）
- 工作模式：保留真实 AI 接通计划，实施已获授权的开发签名准入开关、App entitlement、测试和使用说明；保留 v1 / 1.1 和 2026-10-03 的历史设计与验证记录。
- canonical 项目根目录：`/Users/jerryszz/Desktop/Projects/trainote`
- 本次关键证据：App 报告装配/触发/授权代码、AI transport、App Attest 验证器、Node 入口及文件状态存储、模型适配器、签名配置、既有测试清单，以及 Apple/DeepSeek 官方资料；详见接通计划的证据链接。本轮已运行服务端测试及 iOS 无签名构建；未运行外部服务探针。
- 历史工作树位置（不代表当前仍保留）：F 为 `/Users/jerryszz/.codex/worktrees/392a/trainote`；2026-10-03 文档收尾为 `/Users/jerryszz/.codex/worktrees/health-docs-closeout/trainote`。
- 固定交付证据：F 最终 head `f24b903236bb067ac02d3192c64db50df69815c4` 的 [完整 CI 37098998968](https://github.com/Jerryszz02/trainote/actions/runs/37098998968) 于 13:46:36（Asia/Shanghai）通过 299/299（268 单元、31 UI，0 失败/跳过/预期失败）。PR #9 于 13:56:54 squash 为正式 main `06b25608da2dfed720698f91106f90c429070aea`；两者 tree 均为 `6c1a7ef258d9512b80f2613585cd9bee25e32e7c`。初始 `967fa5351838240b2bb6ca0c5cb8e777530e54c4`、依赖同步、历史失败及修复固定点见交付快照和交接。
- F 历史实施检查证据：Git 状态与工作树、根 README、`project.yml`、已提交 Xcode 工程、AppShell/TrainoteApp、训练与营养模型、动作目录服务、备份服务、资料库/首页/设置页面、现有测试及 CI 配置；2026-10-03 状态收尾另核对 PR 合并 API、Git tree 和原始 CI 产物。原始论文与研究仓库见证据矩阵。
- F 已执行 Simulator 构建及单元/UI 测试；逐项结果在 [交接](../health-integration-handoff.md)。签名、真机和发布状态未验证，旧 1.1 记录仍为历史证据。

本文档区分本次静态检查与历史运行结果；未找到证据的发布信息继续标记为 `待确认`。

1.1 新增功能与可靠性规则以 [日常使用升级计划](daily-use-upgrade.md) 为准；下列文档保留基础架构约定。

健康分析改变新版本的数据、网络和导航边界；旧 v1 文档中的“无 HealthKit/无网络/无体重分析”是旧版本背景，不能覆盖已合并实现。相应源码、提案和交接共同说明实际行为与尚未验收的外部条件。

## 从哪里开始

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
| `project-brief.md`、`user-flow.md` | v1 内容在 PRD；新模块流程合并进健康分析提案，避免重复 |
| `architecture.md`、`decision-log.md`、`security-privacy.md` | 新数据流、权限和供应商边界已写入健康分析提案，当前无需另建重复文件 |
| `api-design.md` | 已有 [Server/README](../../Server/README.md) 和 [客户端交接](../../Trainote/Services/AIReports/README.md) 维护真实代理/API 契约，无需重复 |
| `release-plan.md`、`operations-runbook.md` | 2026-10-10 重新评估：开通顺序与回滚纳入接通计划，现有 Server 文档和 App 发布清单继续作为细节入口；实施选定环境后同步，不重复建文档 |
| 独立开发者指南 | 根 README 与技术/数据文档已按 F 分支事实更新；暂不另建重复指南 |

## 配套文档与历史证据

- [App Store 发布清单](../app-store/release-checklist.md)维护发布准备；发布前仍需核对实际权限和网络配置，当前不代表已获发布批准。
- [1.1 测试计划](test-plan.md)中的带日期执行表是历史记录；当前测试结果应取对应 PR head 的 CI 和本地运行产物。
- 新功能的工程验证、算法有效性、真实 AI 服务和发布条件分别见健康分析提案，不借用旧测试数量证明新功能。

## 文档检查记录

- 提案阶段曾只检查 `docs/planning/`；F 实施阶段同时维护实际源码、测试、交接及发布资料。
- 2026-10-03 文档收尾只同步索引、实施提案、交付记录、证据矩阵开头和 F 交接的交付状态；研究矩阵、历史失败产物及外部待验条件保留。
- F 文档收尾检查命令：`git diff --check`，以及 `python3 /Users/jerryszz/.agents/skills/plan-project-docs/scripts/audit_planning_docs.py --root /Users/jerryszz/.codex/worktrees/health-docs-closeout/trainote`。
- 2026-10-03 上述两项文档检查通过。该审计只验证索引和本地链接，不验证论文结论、算法有效性或产品行为。
- 2026-10-10 先新增接通计划，随后按用户授权实施开发版准入并更新 Server 使用/认证说明、计划和索引。服务端 71 项测试、离线 demo、iOS Debug 无签名构建及 entitlement 格式检查通过。`git diff --check` 及 `python3 /Users/jerryszz/.agents/skills/plan-project-docs/scripts/audit_planning_docs.py --root <本次工作树>` 均通过；这两项仅验证文档格式、索引覆盖和本地链接。

## 当前约束与待确认

- 用户已授权实现允许开发签名访问的规则，并确认固定文案报告；尚未授权采购、部署、上传健康数据或发布。历史 A–F 合并授权不延续为本次合并授权。
- 本次待确认：是否扩大到多人使用、Apple 账号能力、可用主机/域名、DeepSeek 账号与预算，见接通计划。开发直装与固定文案报告已确认。供应商条款与真机认证仍待验证。3D 已使用仓库原创 MIT 资产，许可不再列为未知；真机展示本次未复验。
- 当前代码配置 Swift 5.9 language mode、最低 iOS 17；F 在 Xcode 26.6 / Swift 6.3.3 / iOS 26.5 及匹配 CI 的 iOS 26.4.1 独立 Simulator 验证，详细结果见交接。
- A–F 的 `06b2560` 合并与 `f24b903` CI 为历史验收记录；当前基线是 `170ad07`，本次另验证开发签名准入的合成测试与无签名构建。后续改动须验证各自当前 head，真机、真实服务、科学验证和发布条件另列。
- 临时 Bundle ID 为 `com.jerryszz.trainote`，正式分发前需要与 Apple Developer 账号中的标识一致。
- v1 只支持 iPhone、iOS 17+、简体中文 UI、公斤和公里。
