# Trainote

Trainote 是一个支持简体中文与 English、默认跟随系统语言、离线可用的 iPhone 健身与饮食记录 App。它使用 SwiftUI 和 SwiftData，支持四种训练记录方式、训练模板、常用食物、固定餐、每日营养目标、周报与个人纪录。Apple 健康连接单独选择，原有记录不需要健康权限。

本分支在已有五个 Tab、趋势与恢复分析和训练建议之上，接入随 App 打包的 Qwen3-0.6B 本机报告及版本化首次使用须知。用户主动生成时，模型只挑选代码批准的事实和建议；失败显示规则报告。具体实现与验证边界见 [端侧实施记录](docs/app-store/on-device-implementation.md)，历史接口见 [集成交接](docs/health-integration-handoff.md)。

## 当前能力

- 动作按器械和运动形式默认选择重量×次数、次数、时长或有氧；随时可切换。
- 上次表现对照、沿用参数、组间休息、历史编辑与再次训练。
- 独立训练模板快照；修改模板不改变历史。
- 饮食支持每份/每 100g、改分量自动换算、最近食物、常用食物、固定餐与复制一餐。
- 周一至周日的每周回顾，显示训练积累、重量/容量 PR 和饮食记录完整度。
- 设置中可导出和恢复有版本的 JSON 备份；重复 ID 跳过、冲突和无效备份拒绝。
- 离线内置 1,324 个动作，按语言偏好显示名称和步骤，支持中英双语搜索；目录与搜索索引在后台准备。
- 饮食可按碳水/蛋白质/脂肪的 4/4/9 换算热量；恢复页使用可点击正背面肌肉图，动作演示目前仅有俯卧撑离线样片。
- 手动记录保存在本机，无账号、广告或遥测。
- 今日、训练、饮食、趋势、恢复五个入口；完整资料库可从今日以及训练/饮食进入，设置仍从今日齿轮打开。
- 健康数据连接后只读导入；可明确断开并清除导入缓存及依赖报告，保留手动记录。
- 首次同意须知后进入 App；可暂不同意或撤回，并保留导出和删除入口。Health 授权、本机 AI 开关及历史云端同意分别管理。
- 本机 AI 只在主动生成时运行；切换报告、普通刷新及回前台只读取规则/匹配缓存。关闭、取消、记录变化或内存/温度压力会停止生成，过时结果不写回。
- 当前无远端代理、运行时模型下载或模型 API 请求；模型来源和许可随包提供，旧云端接口保留为备选。

## 开发环境

- macOS
- Xcode 26.6（Build 17F113）；当前已激活 `/Applications/Xcode.app/Contents/Developer`
- 项目使用 Swift 5.9 language mode；当前工具链为 Apple Swift 6.3.3
- 最低支持 iOS 17；当前已安装 iOS 26.5 Simulator runtime
- Python 3.9+，用于重建动作目录及审计默认记录方式

项目使用本地 Swift Package `Packages/TrainoteLlama`，其固定版本 llama.cpp XCFramework 需要先准备。权重和引擎二进制受 Git 忽略，来源、校验值及脚本见 [Models/README](Models/README.md)。`Trainote.xcodeproj` 由 `project.yml` 生成并提交；修改文件清单时使用 XcodeGen 重新生成。

## 开始开发

1. 确认当前使用完整 Xcode：

   ```sh
   xcode-select -p
   xcodebuild -version
   ```

   如果开发目录不是 `/Applications/Xcode.app/Contents/Developer`，运行：

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   ```

2. 准备引擎及模型（首次会下载固定版本的构建输入）：

   ```sh
   python3 Scripts/on-device-ai/prepare.py
   ```

   仅运行规则/mock 测试可改用 `--engine-only`，不会下载模型权重。Debug 缺模型时允许规则模式，已有权重必须通过校验；Release 缺模型或 SHA 不符会构建失败。
3. 打开 `Trainote.xcodeproj`，选择 `Trainote` Scheme 和可用的 iOS 17+ iPhone Simulator，运行 App 或测试。

命令行构建：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

在当前已安装的 Simulator 上运行单元测试和 UI 测试：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -skip-testing:TrainoteUITests/StoreScreenshotUITests \
  test
```

## 验证状态

2026-10-27 本机 AI、首次须知和商店准备的本次验证见 [实施记录](docs/app-store/on-device-implementation.md) 与 [模型评估](docs/app-store/on-device-model-evaluation.md)。下列均为历史结果；本轮未连接用户 iPhone，不能用 Mac/Simulator 数据推定真机速度或内存。

2026-10-18 文档核查：PR [#14](https://github.com/Jerryszz02/trainote/pull/14)、[#16](https://github.com/Jerryszz02/trainote/pull/16)、[#17](https://github.com/Jerryszz02/trainote/pull/17)、[#18](https://github.com/Jerryszz02/trainote/pull/18) 已合入默认分支；当前功能基线为 `64af1f2`。#18 的 [iOS CI](https://github.com/Jerryszz02/trainote/actions/runs/38418266749) 成功，10 月 13 日交付记录为 308 项单元测试、52 项 UI 测试、零失败；本次仅运行文档检查，未重跑 App 测试。

2026-10-15 曾将 `64af1f2` 安装到 iPhone 并启动，安装前后数据库一致；这是历史安装证据，不代表同机 Release 性能对比、完整 HealthKit、VoiceOver 或新用户验收完成。该次 Personal Team 描述文件于 10 月 17 日 19:23（伦敦时间）到期，当前可启动状态未复验。安装包未启用 App Attest，代码仍为 `proxy: nil`，真实 AI 服务未接通；认证准入修改不等于端到端接通。

以下为 1.1 的历史验证，不代表当前健康集成结果：

- 2026-09-19：Xcode 26.6 / iOS 26.5，Release generic iOS Simulator 无签名构建通过。
- 2026-09-19：最终完整回归通过 42 个单元测试和 16 个 UI 测试，共 58 项、0 失败。
- 动作默认方式审计覆盖 1,324 条：重量×次数 862、次数 371、时长 82、有氧 9。
- 真机、VoiceOver、长时间使用、签名与 TestFlight 尚未验证；详细证据与范围见 [测试计划](docs/planning/test-plan.md)。

## App Store 准备

App Icon、中英隐私/支持页、双语商店元数据、审核说明、隐私问卷和截图工具已准备；公开联系邮箱经用户确认。发布资料、实际截图和未验事项见 [App Store 发布清单](docs/app-store/release-checklist.md)。付费会员、签名上传、TestFlight 和正式提交仍由后续发布流程处理。

## 动作目录

动作文字数据来自固定提交 `118e4bd6b14da6df0e36605d7169b65db18389a4`。重新生成：

```sh
python3 Scripts/import_exercises.py
python3 Scripts/audit_tracking_modes.py
```

只有需要补齐新的中文名称时，才启动本机 LM Studio 并运行：

```sh
python3 Scripts/import_exercises.py --translate-missing
```

导入器会验证 1,324 个唯一 ID，并剔除 `image`、`gif_url` 和其他媒体字段。Gym visual 图片/GIF 不在本项目中分发。

## 项目结构

- `Trainote/App`：根 ModelContainer、Tab 和依赖注入。
- `Trainote/Models`：SwiftData 模型和枚举。
- `Trainote/Services`：动作目录、routine 快照和营养汇总。
- `Trainote/Features`：五 Tab 导航、资料库、设置、分项引导和离线方法/隐私说明。
- `TrainoteTests`、`TrainoteUITests`：领域、持久化、数据和 UI 验证。
- `docs/planning`：PRD、技术设计、数据库设计和测试计划。

1.1 升级规则与验收场景见 [日常使用升级计划](docs/planning/daily-use-upgrade.md)。

后续开发先从 [规划索引](docs/planning/README.md) 开始。
