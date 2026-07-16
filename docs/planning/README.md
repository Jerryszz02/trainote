# Trainote iOS v1 规划索引

## 项目是什么

Trainote 是一款中文优先、完全离线的 iPhone 健身与饮食记录 App。它用于记录力量训练、有氧训练、训练 routine，以及每日卡路里、碳水、蛋白质和脂肪。动作目录来自 `hasaneyldrm/exercises-dataset` 的固定版本，只内置 MIT 许可覆盖的文字和结构化数据，不分发需要单独授权的图片或 GIF。

## 文档信息

- 更新时间：2026-07-16
- 项目根目录：`/Users/jerryszz/Desktop/Projects/trainote`
- 计划标题：Trainote iOS v1 实施计划
- 已检查证据：根 README、`project.yml`、Xcode 工程、App/模型/服务/功能源码、单元与 UI 测试、动作资源、第三方许可证、当前 Xcode/Swift/Simulator 状态和实际构建结果

本文档仅根据当前仓库可见内容和本机验证结果整理；未找到证据的发布信息继续标记为 `待确认`。

## 从哪里开始

1. 阅读 [prd.md](prd.md)，确认用户流程和产品验收标准。
2. 阅读 [technical-design.md](technical-design.md)，了解 SwiftUI、动作导入、导航和隐私边界。
3. 阅读 [database-design.md](database-design.md)，维护 SwiftData 模型和快照语义。
4. 按 [test-plan.md](test-plan.md) 的顺序运行数据、业务、持久化和 UI 验证。

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

- 当前已激活 Xcode 26.6，Apple Swift 6.3.3；项目仍使用 Swift 5.9 language mode，最低部署目标为 iOS 17。
- 2026-07-16 已完成 generic iOS Simulator 无签名构建；当前可用 `iPhone 17`（iOS 26.5）运行测试。
- 单元测试、UI 测试和人工验收尚未在当前环境执行，不能仅凭构建成功视为 v1 已完成验收。
- 临时 Bundle ID 为 `com.jerryszz.trainote`，正式分发前需要与 Apple Developer 账号中的标识一致。
- v1 只支持 iPhone、iOS 17+、简体中文 UI、公斤和公里。
