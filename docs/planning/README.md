# Trainote 规划索引

## 项目是什么

当前默认分支的 Trainote 是一款中文优先、完全离线的 iPhone 健身与饮食记录 App。它用于记录力量训练、有氧训练、训练 routine，以及每日卡路里、碳水、蛋白质和脂肪。动作目录来自 `hasaneyldrm/exercises-dataset` 的固定版本，只内置 MIT 许可覆盖的文字和结构化数据，不分发需要单独授权的图片或 GIF。

计划新增“趋势分析”“恢复分析”、Apple 健康读取和可选 DeepSeek 报告。**2026-10-03：A/D 已形成固定基础 `967fa535`；本 F 分支正在实现导航、同意和建议规则，B/C/E 实际装配仍待主对话给出已验证提交。** 不据此推断默认分支、真实 AI 或发布状态。所有实施对话使用 max。现有代码是实现事实的依据，规划描述目标，不代替测试、科学验证或发布证据。

## 文档信息

- 更新时间：2026-10-03
- 工作模式：执行已批准的 F 集成任务，保留 v1 / 1.1 的历史设计与验证记录。
- canonical 项目根目录：`/Users/jerryszz/Desktop/Projects/trainote`
- 本次 F 工作树：`/Users/jerryszz/.codex/worktrees/392a/trainote`
- 固定代码基线：`967fa5351838240b2bb6ca0c5cb8e777530e54c4`；分支 `agent/health-integration`，PR 暂以 `agent/health-foundation-integration` 为 base。
- 本次检查证据：Git 状态与工作树、根 README、`project.yml`、已提交 Xcode 工程、AppShell/TrainoteApp、训练与营养模型、动作目录服务、备份服务、资料库/首页/设置页面、现有测试及 CI 配置；原始论文与研究仓库见证据矩阵。
- F 已执行 Simulator 构建及单元/UI 测试；逐项结果在 [交接](../health-integration-handoff.md)。签名、真机和发布状态未验证，旧 1.1 记录仍为历史证据。

本文档区分本次静态检查与历史运行结果；未找到证据的发布信息继续标记为 `待确认`。

1.1 新增功能与可靠性规则以 [日常使用升级计划](daily-use-upgrade.md) 为准；下列文档保留基础架构约定。

健康分析提案改变将来版本的数据、网络和导航边界；旧 v1 文档中的“无 HealthKit/无网络/无体重分析”描述当前基线，不表示新增模块已完成，也不表示永久排除。批准实施后由对应 PR 同步实际现状文档。

## 从哪里开始

F 实施记录（2026-10-03）：本分支已从固定 A/D 基础 `967fa535` 开始导航、同意流程和推荐规则。
见 [F 集成交接](../health-integration-handoff.md) 的接口缺口和待验条件；它不代表最终集成或默认分支现状。

1. 阅读已获批准的 [健康分析实施提案](health-analysis-plan.md)，遵循导航、目标调整、权限和计算边界。
2. 阅读 [研究证据与模型资产](health-analysis-evidence.md)，分清文献依据、产品参数与未验证部分。
3. 阅读 [并行交付计划](health-analysis-delivery.md)，遵循六条工作流、max 设置、A/D 固定基础依赖和集成授权。
4. 维护现有功能时阅读 [prd.md](prd.md)、[technical-design.md](technical-design.md)、[database-design.md](database-design.md) 与 [test-plan.md](test-plan.md)。

## 规划文档

| 文档 | 用途 |
| --- | --- |
| [health-analysis-plan.md](health-analysis-plan.md) | 新增：已批准的产品流程、算法候选、数据/API 契约、隐私、迁移和验收 |
| [health-analysis-evidence.md](health-analysis-evidence.md) | 新增：14 项营养/恢复来源、健康 AI 研究资产与推论边界 |
| [health-analysis-delivery.md](health-analysis-delivery.md) | 新增：已批准的六条工作流、文件所有权、A/D 固定基础依赖及派发消息 |
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
| `api-design.md` | 当前实现仍无后端；新代理 API 和认证操作已在提案中定义，实施时再按实际契约维护 |
| `release-plan.md`、`operations-runbook.md` | 拟议发布条件/任务交付写入提案和交付计划；代理尚未创建，不编造运维命令；现有商店准备资料见下文 |
| 独立开发者指南 | 根 README 与技术/数据文档已按 F 分支事实更新；暂不另建重复指南 |

## 配套文档与历史证据

- [App Store 发布清单](../app-store/release-checklist.md)维护发布准备；未来实现涉及权限和网络时需同步，当前不代表已获发布批准。
- [1.1 测试计划](test-plan.md)中的带日期执行表是历史记录；当前测试结果应取对应 PR head 的 CI 和本地运行产物。
- 新功能的工程验证、算法有效性、真实 AI 服务和发布条件分别见健康分析提案，不借用旧测试数量证明新功能。

## 本轮文档检查

- 范围：仅 `docs/planning/`；未修改产品源码、测试、配置或依赖。
- 检查命令：`git diff --check`，以及 `python3 /Users/jerryszz/.agents/skills/plan-project-docs/scripts/audit_planning_docs.py --root /Users/jerryszz/.codex/worktrees/f626/trainote`。
- 2026-10-03 上述两项文档检查通过；最终提交仍会复查。该审计只验证索引和本地链接，不验证论文结论、算法有效性或产品行为。

## 当前约束与待确认

- 用户已确认提案和分工，授权审阅及当前提交 CI 通过后合并本范围 PR；由主对话统一协调。尚未授权付费采购、正式部署或发布。
- 外部条件：AI 代理部署/预算、DeepSeek API 数据处理安排、3D 资产许可、真机/签名与专业审查，见提案。
- 当前代码配置 Swift 5.9 language mode、最低 iOS 17；旧文档中的 Xcode 26.6 / Swift 6.3.3 / iOS 26.5 为此前核查记录，本轮未重新枚举运行环境。
- 本次未执行产品测试；实施时先确认当前工具链和 Simulator，再运行对应检查。
- 临时 Bundle ID 为 `com.jerryszz.trainote`，正式分发前需要与 Apple Developer 账号中的标识一致。
- v1 只支持 iPhone、iOS 17+、简体中文 UI、公斤和公里。
