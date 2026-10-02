# Trainote

Trainote 是一个中文优先、离线可用的 iPhone 健身与饮食记录 App。它使用 SwiftUI 和 SwiftData，支持四种训练记录方式、训练模板、常用食物、固定餐、每日营养目标、周报与个人纪录。Apple 健康连接单独选择，原有记录不需要健康权限。

本分支正在集成健康分析：五个 Tab、资料库上下文入口、分项引导与撤回已实现；趋势、恢复和 AI 模块仍待固定版本装配，不能把占位页当作已交付分析功能。具体接口与验证见 [集成交接](docs/health-integration-handoff.md)。

## 当前能力

- 动作按器械和运动形式默认选择重量×次数、次数、时长或有氧；随时可切换。
- 上次表现对照、沿用参数、组间休息、历史编辑与再次训练。
- 独立训练模板快照；修改模板不改变历史。
- 饮食支持每份/每 100g、改分量自动换算、最近食物、常用食物、固定餐与复制一餐。
- 周一至周日的每周回顾，显示训练积累、重量/容量 PR 和饮食记录完整度。
- 设置中可导出和恢复有版本的 JSON 备份；重复 ID 跳过、冲突和无效备份拒绝。
- 离线内置 1,324 个中英双语动作和中文说明。
- 手动记录保存在本机，无账号、广告或遥测。
- 今日、训练、饮食、趋势、恢复五个入口；完整资料库可从今日以及训练/饮食进入，设置仍从今日齿轮打开。
- 健康数据连接后只读导入；可明确断开并清除导入缓存及依赖报告，保留手动记录。
- 无真实代理配置时 AI 入口说明开放条件，不保存预先同意、不向 DeepSeek 发送健康记录。

## 开发环境

- macOS
- Xcode 26.6（Build 17F113）；当前已激活 `/Applications/Xcode.app/Contents/Developer`
- 项目使用 Swift 5.9 language mode；当前工具链为 Apple Swift 6.3.3
- 最低支持 iOS 17；当前已安装 iOS 26.5 Simulator runtime
- Python 3.9+，用于重建动作目录及审计默认记录方式

项目没有第三方 Swift Package。`Trainote.xcodeproj` 由仓库根目录的 `project.yml` 生成并提交；普通开发不需要重新生成。

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

2. 打开 `Trainote.xcodeproj`，选择 `Trainote` Scheme 和任意 iOS 17+ iPhone Simulator；当前机器可使用 iOS 26.5 的 `iPhone 17`。
3. 运行 App 或测试。

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
  test
```

## 验证状态

2026-10-03 F 骨架：普通合并固定基础 `28500cf` 并接入手动目标原子写入后，113 项单元测试通过。UI 累计 23 条路径分次验证，其中本次基线复测手动目标保存回显和只读失败反馈；其余流程及深色/大字号在先前骨架上验证。独立 Simulator 实际构建通过。最终 B/C/E 联合验收、真机健康链路与供应商条件尚未完成。

以下为 1.1 的历史验证，不代表当前健康集成结果：

- 2026-09-19：Xcode 26.6 / iOS 26.5，Release generic iOS Simulator 无签名构建通过。
- 2026-09-19：最终完整回归通过 42 个单元测试和 16 个 UI 测试，共 58 项、0 失败。
- 动作默认方式审计覆盖 1,324 条：重量×次数 862、次数 371、时长 82、有氧 9。
- 真机、VoiceOver、长时间使用、签名与 TestFlight 尚未验证；详细证据与范围见 [测试计划](docs/planning/test-plan.md)。

## App Store 准备

App Icon、隐私政策、支持页、简体中文商店元数据、审核说明和截图规划已在本地准备。发布资料索引见 [App Store 发布清单](docs/app-store/release-checklist.md)。

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
