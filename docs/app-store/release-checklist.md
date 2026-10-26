# Trainote App Store 发布清单

## 当前首发范围（2026-10-26）

仅美国 App Store、简体中文与 English、免费、面向普通用户公开下载。AI 保持重点事实与候选建议报告；已确认先试内置 0.6B，质量不足再评估 1B。计划新增首次须知同意入口；具体接入与验证方法见 [详细计划](../planning/on-device-ai-and-first-use-plan.md)，发布顺序见 [首发计划](us-launch-plan.md)。当前只有本地规则报告，端侧模型和首次须知尚未实现；仓库已有云端传输代码，但服务当前未配置或接通。

开发者账号已由用户注册，付费 Apple Developer Program 会员/购买状态尚未核实；需在真实账号状态中确认，再进行付费团队签名与 App Store Connect 配置。

本轮已起草中英 [隐私政策](../privacy/index.html) 和 [支持页](../support/index.html)，尚未公开部署。模型实现后再按真实数据流更新披露。详细首发验收标准按用户要求后续再定；下列历史完整检查项保留作后续依据，本次没有运行或将其标为通过。

## 健康分析版本历史发布门（2026-10-03）

- [x] B/C/E 已实际装配；报告日统计窗口修复通过 9 项联合单元和真实报告 UI
- [x] A 撤回持久化修复与公共 UI 输入辅助定向回归通过；E 真实服务重启回归已纳入
- [x] F 固定代码 `405d2f4` 全部 268 单元/31 UI 本地通过；后续显示取整补丁及 +240 UI 断言定向通过
- [ ] 主协调核对最终 PR head 的 CI、完成统一审阅及合并验收（当前状态见 PR 检查）
- [ ] HealthKit entitlement、签名、真机拒绝/部分授权、系统撤回、锁屏/后台同步验证
- [x] 目标采用/撤销原子性、历史日目标、恢复未知/疼痛排除、建议采用快照的单元与 Simulator 联合验证
- [ ] VoiceOver、大字号、小屏、深浅色和正常 3D 完整流程验收
- [ ] 专业人员审查 P 参数与适用范围，并匹配宣传所需的有效性证据
- [ ] 若选择云端：核对 DeepSeek API 适用条款、保留/再利用/退出/删除、代理部署与预算；端侧路线按首发计划核对实际数据流、模型许可与兼容性
- [ ] 对最终构建更新隐私问卷、审核说明、截图、权限说明及实际公开隐私/支持页
- [ ] 版本号/构建号、真机签名与发布授权；本任务不部署或发布

下列勾选是 **1.1 历史准备记录**，不代表健康版本已经满足条件。

## 1.1 本地历史记录

- [x] Xcode 26.6 / iOS 26 SDK 工具链验证
- [x] iPhone-only target，与 v1 产品范围一致
- [x] 版本号 `1.1`、构建号 `2`
- [x] 1024 × 1024、无透明通道的 App Icon
- [x] 声明不使用非豁免加密
- [x] 隐私审计：无账号、后端、广告、分析、追踪、遥测或第三方在线 SDK
- [x] 隐私清单声明本 App 的偏好存储用途（休息时长和新手引导）
- [x] App 内隐私政策与支持入口
- [x] GitHub Pages 隐私政策与支持页源文件
- [x] 简体中文 App Store 元数据草稿
- [x] App Review 说明草稿
- [x] 五张 iPhone 商店截图规划
- [x] 42 个单元测试通过（2026-09-19）
- [x] 最终完整 16 个 UI 测试通过、0 失败（2026-09-19）
- [x] Release generic iOS Simulator 无签名构建通过（2026-09-19）
- [x] Release generic iOS 无签名构建通过，并确认隐私清单进入 App 包
- [x] 系统文件选择器导出、恢复、重复导入原生 UI 自动化验收

## 无需 Apple 账号但发布前仍需人工完成

- [ ] 在真实 iPhone（iOS 17 或更高）测试全部核心流程
- [x] 小屏首页浅色、深色、高对比和最大 Dynamic Type 截图检查
- [ ] 全页面 VoiceOver 人工验收
- [ ] 按 [截图规划](screenshot-plan.md) 准备无真实隐私信息的正式截图
- [ ] 确认 App Icon 与商店名称作为 1.1 正式品牌方案
- [ ] 将 `docs` 目录启用为 GitHub Pages，并验证以下地址可公开访问：
  - `https://jerryszz02.github.io/trainote/privacy/`
  - `https://jerryszz02.github.io/trainote/support/`

## 必须等待 Apple Developer 账号

- [ ] 注册或续费 Apple Developer Program
- [ ] 在 Xcode 选择 Team，并确认签名证书与描述文件
- [ ] 注册 `com.jerryszz.trainote` Bundle ID
- [ ] 在 App Store Connect 创建 Trainote App 记录并确认名称可用
- [ ] 填写年龄分级、价格、发布地区、内容权利和 App 隐私
- [ ] Archive、Validate App、Upload
- [ ] TestFlight 真机测试
- [ ] 提交 App Review 并发布
- 首发只选美区：中国大陆 App 备案不在本次范围；以后增加地区时重新核对。

## 资料入口

- [美区首发计划与端侧 AI 调研](us-launch-plan.md)
- [商店元数据](metadata.zh-Hans.md)
- [审核说明](review-notes.zh-Hans.md)
- [截图规划](screenshot-plan.md)
- [隐私政策](../privacy/index.html)
- [支持页](../support/index.html)
