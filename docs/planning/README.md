# Trainote iOS v1 规划索引

## 项目是什么

Trainote 是一款中文优先、完全离线的 iPhone 健身与饮食记录 App。它用于记录力量训练、有氧训练、训练 routine，以及每日卡路里、碳水、蛋白质和脂肪。动作目录来自 `hasaneyldrm/exercises-dataset` 的固定版本，只内置 MIT 许可覆盖的文字和结构化数据，不分发需要单独授权的图片或 GIF。

## 文档信息

- 生成日期：2026-07-16
- 项目根目录：`/Users/jerryszz/Desktop/Projects/trainote`
- 计划标题：Trainote iOS v1 实施计划
- 已检查证据：用户确认的实施计划、空项目目录、当前本机 Xcode/Command Line Tools 状态、上游动作数据集及许可证

## 从哪里开始

1. 阅读 [prd.md](prd.md)，确认用户流程和产品验收标准。
2. 阅读 [technical-design.md](technical-design.md)，了解 SwiftUI、动作导入、导航和隐私边界。
3. 阅读 [database-design.md](database-design.md)，实现 SwiftData 模型和快照语义。
4. 按 [test-plan.md](test-plan.md) 的顺序完成数据、业务、持久化和 UI 验证。

## 规划文档

| 文档 | 用途 |
| --- | --- |
| [prd.md](prd.md) | 定义用户场景、页面流程、业务规则和非目标 |
| [technical-design.md](technical-design.md) | 定义 App 壳层、状态归属、动作导入和隐私边界 |
| [database-design.md](database-design.md) | 定义 SwiftData 实体、关系、校验和历史快照规则 |
| [test-plan.md](test-plan.md) | 定义自动化与人工验收范围 |

## 有意跳过的文档

| 文档 | 原因 |
| --- | --- |
| `project-brief.md`、`user-flow.md` | 项目背景和完整用户流程已合并进 PRD |
| `architecture.md`、`decision-log.md`、`security-privacy.md` | 单 App 离线架构、关键决策和隐私边界已合并进技术设计 |
| `api-design.md` | v1 没有网络 API、账号或后端 |
| `release-plan.md`、`operations-runbook.md` | 当前范围是本地 iPhone App，没有线上服务和运维流程 |

## 当前约束与待确认

- 本机尚未安装或激活完整 Xcode；编译、模拟器和 UI 测试要在 Xcode 可用后执行。
- 临时 Bundle ID 为 `com.jerryszz.trainote`，正式分发前需要与 Apple Developer 账号中的标识一致。
- v1 只支持 iPhone、iOS 17+、简体中文 UI、公斤和公里。

