# Trainote

Trainote 是一个中文优先、完全离线的 iPhone 健身与饮食记录 App。它使用 SwiftUI 和 SwiftData，支持力量训练、有氧训练、routine、常用食物、固定餐，以及每日卡路里和三大营养素目标。

## 当前能力

- 力量动作逐组记录重量、次数和完成状态。
- 有氧动作记录时长、距离和可选热量。
- 用户自建 routine，并从模板生成独立训练快照。
- 饮食按早餐、午餐、晚餐、加餐记录。
- 常用食物按份量复用，固定餐一次展开为多条日志。
- 离线内置 1,324 个中英双语动作和中文说明。
- 所有记录只保存在本机，无账号、后端、分析或遥测。

## 开发环境

- macOS
- Xcode 26.6（Build 17F113）；当前已激活 `/Applications/Xcode.app/Contents/Developer`
- 项目使用 Swift 5.9 language mode；当前工具链为 Apple Swift 6.3.3
- 最低支持 iOS 17；当前已安装 iOS 26.5 Simulator runtime
- Python 3.9+，仅用于手动重建动作目录

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

## 当前验证状态

- 2026-08-03：在 Xcode 26.6 下完成 generic iOS Simulator 无签名构建，结果为 `BUILD SUCCEEDED`。
- 2026-08-03：在 iPhone 17（iOS 26.5）Simulator 上通过 13 个单元测试和 10 个 UI 测试，共 23 项、0 失败。
- 真机与辅助功能人工验收尚未执行；范围与验收项见 [测试计划](docs/planning/test-plan.md)。

## App Store 准备

App Icon、隐私政策、支持页、简体中文商店元数据、审核说明和截图规划已在本地准备。发布资料索引见 [App Store 发布清单](docs/app-store/release-checklist.md)。

## 动作目录

动作文字数据来自固定提交 `118e4bd6b14da6df0e36605d7169b65db18389a4`。重新生成：

```sh
python3 Scripts/import_exercises.py
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
- `Trainote/Features`：今日、训练、饮食、资料库和设置界面。
- `TrainoteTests`、`TrainoteUITests`：领域、持久化、数据和 UI 验证。
- `docs/planning`：PRD、技术设计、数据库设计和测试计划。

后续开发先从 [规划索引](docs/planning/README.md) 开始。
