# Trainote 规划索引

## 项目是什么

Trainote 是一款中文优先、以本地记录为基础的 iPhone 健身与饮食 App，记录力量/有氧训练、训练模板及每日卡路里、碳水、蛋白质和脂肪。动作目录来自 `hasaneyldrm/exercises-dataset` 的固定版本，只内置 MIT 许可覆盖的文字和结构化数据，不分发需要单独授权的图片或 GIF。

**2026-10-03：F 已装配真实 A/B/C/D/E 服务，提供五 Tab、趋势/恢复分析、训练建议、历史营养目标及本地报告入口；联合验收仍在进行。** 默认无远程 AI transport，真实 DeepSeek 未启用。规划 PR #3、A 的 #4、B 的 #6、C 的 #8、D 的 #5/#10、E 的 #7 已合并，F 的 #9 仍开放；详见 [交付快照](health-analysis-delivery.md)。所有实施对话使用 max。分支实现、工程测试、科学验证、默认分支与发布是不同状态。

## 文档信息

- 更新时间：2026-10-03
- 工作模式：执行已批准的 F 集成任务，保留 v1 / 1.1 的历史设计与验证记录。
- canonical 项目根目录：`/Users/jerryszz/Desktop/Projects/trainote`
- 本次 F 工作树：`/Users/jerryszz/.codex/worktrees/392a/trainote`
- 固定代码基线：初始 `967fa5351838240b2bb6ca0c5cb8e777530e54c4`，后按主对话批准 SHA 普通合并 A/B/C/D/E；分支 `agent/health-integration` 已经 `f66997b` 普通合并正式 main `c439350e52baf15d3c1d5a3528be112c1ea6928d`（A/B/C/D/E），PR #9 base 为 `main`。最新完成 CI 在 `3df6541` 上为 297/299 通过；仅余两条健康弹窗路径。`d1a3433` 将今日弹窗统一移到 AppShell 呈现，在同一 iOS 26.4.1 上从原两项失败变为健康/RIR 11/11 通过，主协调审阅及独立 26.5 兼容回归 2/2 通过；新 head 完整 CI 仍待验证。各固定点见交付快照及交接。
- 本次检查证据：Git 状态与工作树、根 README、`project.yml`、已提交 Xcode 工程、AppShell/TrainoteApp、训练与营养模型、动作目录服务、备份服务、资料库/首页/设置页面、现有测试及 CI 配置；原始论文与研究仓库见证据矩阵。
- F 已执行 Simulator 构建及单元/UI 测试；逐项结果在 [交接](../health-integration-handoff.md)。签名、真机和发布状态未验证，旧 1.1 记录仍为历史证据。

本文档区分本次静态检查与历史运行结果；未找到证据的发布信息继续标记为 `待确认`。

1.1 新增功能与可靠性规则以 [日常使用升级计划](daily-use-upgrade.md) 为准；下列文档保留基础架构约定。

健康分析改变新版本的数据、网络和导航边界；旧 v1 文档中的“无 HealthKit/无网络/无体重分析”是旧版本背景，不能覆盖当前集成分支事实。相应源码、提案和交接共同说明实际行为与尚未验收的条件。

## 从哪里开始

F 实施记录（2026-10-03）：B/C/E 已实际连接，训练建议会复核最新事实后创建新训练；报告支持当前事实、历史只读和撤回/清理。
见 [F 集成交接](../health-integration-handoff.md) 的精确提交、通过/失败产物和待验条件。历史 `405d2f4` 的 268 单元、31 UI 曾完整通过；后续显示取整和 UI 修复另有定向通过证据。`f81651b` 普通合并正式 main 后与 `5aca4aa` 源码 tree 相同，历史复制冲突回归 1/1 通过；后续 `e9b2d5b` 去除输入框无滚动时的重复聚焦，`9c53b39` 拆开训练目的页等待与独立断言，分别有 2/2 和 3/3 定向通过证据；这些修复随后在 `3df6541` CI 通过。该 CI 余下两项健康失败已在匹配运行时复现，`d1a3433` 修复后的 11 项健康/RIR 回归及主协调独立 2 项兼容回归通过；最新 head 必须独立通过完整 CI。

1. 阅读已获批准的 [健康分析实施提案](health-analysis-plan.md)，遵循导航、目标调整、权限和计算边界。
2. 阅读 [研究证据与模型资产](health-analysis-evidence.md)，分清文献依据、产品参数与未验证部分。
3. 阅读 [并行交付计划](health-analysis-delivery.md)，遵循六条工作流、max 设置、A/D 固定基础依赖和集成授权。
4. 维护现有功能时阅读 [prd.md](prd.md)、[technical-design.md](technical-design.md)、[database-design.md](database-design.md) 与 [test-plan.md](test-plan.md)。

## 规划文档

| 文档 | 用途 |
| --- | --- |
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
| `release-plan.md`、`operations-runbook.md` | 代理已实现但未部署；运行命令、持久化限制和部署门槛见 Server 文档，App 发布条件见现有清单 |
| 独立开发者指南 | 根 README 与技术/数据文档已按 F 分支事实更新；暂不另建重复指南 |

## 配套文档与历史证据

- [App Store 发布清单](../app-store/release-checklist.md)维护发布准备；未来实现涉及权限和网络时需同步，当前不代表已获发布批准。
- [1.1 测试计划](test-plan.md)中的带日期执行表是历史记录；当前测试结果应取对应 PR head 的 CI 和本地运行产物。
- 新功能的工程验证、算法有效性、真实 AI 服务和发布条件分别见健康分析提案，不借用旧测试数量证明新功能。

## 文档检查记录

- 提案阶段曾只检查 `docs/planning/`；F 实施阶段同时维护实际源码、测试、交接及发布资料。
- F 检查命令：`git diff --check`，以及 `python3 /Users/jerryszz/.agents/skills/plan-project-docs/scripts/audit_planning_docs.py --root /Users/jerryszz/.codex/worktrees/392a/trainote`。
- 2026-10-03 上述两项文档检查通过。该审计只验证索引和本地链接，不验证论文结论、算法有效性或产品行为。

## 当前约束与待确认

- 用户已确认提案和分工，授权审阅及当前提交 CI 通过后合并本范围 PR；由主对话统一协调。尚未授权付费采购、正式部署或发布。
- 外部条件：AI 代理部署/预算、DeepSeek API 数据处理安排、真机/签名与专业审查，见提案。3D 已使用仓库原创 MIT 资产，许可不再列为未知；真机展示验收仍未完成。
- 当前代码配置 Swift 5.9 language mode、最低 iOS 17；F 在 Xcode 26.6 / Swift 6.3.3 / iOS 26.5 及匹配 CI 的 iOS 26.4.1 独立 Simulator 验证，详细结果见交接。
- B/C/E 已装配；A/B/C/D/E 已合入正式 main `c439350`，F 在保存上一 CI 失败产物后经 `f66997b` 普通同步。今日弹窗修复已获审阅及本地回归，新 head 的完整 CI 尚待通过。历史完整回归、后续 UI 定向结果和当前 head CI 分别记录；最新提交的 CI 和统一合并验收由主对话按 PR 当前检查确认，真机与发布条件另列。
- 临时 Bundle ID 为 `com.jerryszz.trainote`，正式分发前需要与 Apple Developer 账号中的标识一致。
- v1 只支持 iPhone、iOS 17+、简体中文 UI、公斤和公里。
