# Trainote App Store 发布清单

## 当前首发范围（2026-10-27）

仅美国 App Store、简体中文与 English、免费、面向普通用户公开下载。AI 保持重点事实与候选建议报告；已确认先试内置 0.6B，质量不足再评估 1B。首次须知同意入口已在代码中实现；具体接入与验证方法见 [详细计划](../planning/on-device-ai-and-first-use-plan.md)，发布顺序见 [首发计划](us-launch-plan.md)。本轮已在代码中实现随包 Qwen3-0.6B 与 llama.cpp 接入、主动生成、本机 AI 独立开关及首启须知的接受、暂不同意和撤回流程；包内许可与离线查看入口已补齐。Release 无签名设备归档、完整回归快照 340 单元与 8 UI（348/348）以及iPhone 17 Pro Max 大屏 Simulator（默认字号）8 UI 已通过本地验证；28 张中英双尺寸截图已重采和逐图目视核对；真机未完成。证据与边界见 [实施与验证记录](on-device-implementation.md)。

开发者 Apple Account 已注册，付费 Apple Developer Program 会员状态尚未核实。本轮仅完成付费注册之前可做的实现与材料；购买、身份核验、证书、App Store Connect、TestFlight 和商店提交留给用户后续安排。

## 本轮发布材料准备

- [x] 简体中文和 English (U.S.) 名称、副标题、推广、描述、关键词候选
- [x] 中英 App Review Notes、可选 Health/主动 AI/首启与撤回审核步骤
- [x] App 隐私问卷候选及仅在设备处理的判定依据
- [x] 隐私/支持页面中英内容同步端侧候选行为；公开页面已发布，App 尚未提交或分发
- [x] 官方字节/字符限制、截图规格核对，提供静态检查和当前 UI 原图采集脚本
- [x] Release 无签名设备归档、模型 SHA-256 与三份许可/来源包内字节核对
- [x] 340 单元 + 8 UI（348/348）及iPhone 17 Pro Max 大屏 Simulator（默认字号）8 UI 本地通过；真实模型合成/Simulator 证据见实施记录，不能替代真机
- [x] 28 张中英双尺寸商店截图原图、代理逐图目视检查与 manifest；发布者最终选图仍待确认
- [ ] 真机性能、健康权限、无网络流程及专业适用性审查
- [ ] 用户确认商店名称/版权权利人及私有审核联系人姓名/电话
- [x] 三个公开页面 HTTP 200、HTTPS 强制、内容 SHA-256 与源文件相同；Chrome 中英/跨页导航通过，发布提交 `b7634bf`

运行 `python3 Scripts/verify_store_materials.py` 检查字段限制与本地页面链接；截图检查方法见 [截图规划](screenshot-plan.md)。公开支持邮箱已确认：`shen20060206@163.com`；页面同时保留 GitHub Issues。私人审核联系人姓名与电话仍待用户填写。Apple 支持 URL 要求见 [材料检查说明](material-verification.md)。


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
- [x] 按 [截图规划](screenshot-plan.md) 准备无真实隐私信息的候选截图；正式提交前与上传构建核对
- [ ] 确认 App Icon 与商店名称作为 1.1 正式品牌方案
- [x] 仅将打包脚本产物中的 `index.html`、`privacy/index.html`、`support/index.html` 发布到专用 `agent/trainote-public-pages` 分支；提交 `b7634bf` 已验证以下地址公开可用。后续维护继续仅打包三文件，不直接发布整个 `docs` 目录：
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

- [注册付费会员前的实施与验证证据](on-device-implementation.md)

- [美区首发计划与端侧 AI 调研](us-launch-plan.md)
- [简体中文商店元数据](metadata.zh-Hans.md)
- [English (U.S.) 元数据](metadata.en-US.md)
- [English App Review Notes](review-notes.en-US.md)
- [App 隐私问卷草稿](privacy-questionnaire.md)
- [材料自动检查与官方来源](material-verification.md)
- [审核说明](review-notes.zh-Hans.md)
- [截图规划](screenshot-plan.md)
- [隐私政策](../privacy/index.html)
- [支持页](../support/index.html)
