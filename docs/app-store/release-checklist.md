# Trainote 1.1 App Store 发布清单

## 本地已完成

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
- [ ] 如选择中国大陆区，按 App Store Connect 实际提示补充 ICP 备案信息

## 资料入口

- [商店元数据](metadata.zh-Hans.md)
- [审核说明](review-notes.zh-Hans.md)
- [截图规划](screenshot-plan.md)
- [隐私政策](../privacy/index.html)
- [支持页](../support/index.html)
