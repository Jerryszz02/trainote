# Trainote iOS 1.1 测试计划

## 文档目的

定义实现完成所需的自动化和人工验证，避免只以“可以编译”作为完成标准。

## 自动化测试

### 动作数据

- 导入结果数量恰好为 1,324，ID 唯一。
- 每条记录有英文名、中文名或合法英文回退、中英文说明和筛选字段。
- 输出 JSON 不含 `image`、`gif_url`、`media_id` 或媒体文件。
- `ExerciseCatalog` 可按中英文名、部位、器械和肌群搜索。

### 领域逻辑

- routine 复制保持顺序和默认值；修改原 routine 不改变训练快照。
- 1,324 个动作均有显式默认记录方式；训练和模板可在重量×次数、次数、时长、有氧之间切换，历史语义保持不变。
- 力量组数、完成条件和无效数值校验正确。
- 有氧时长必填，距离和热量可选。
- FoodPreset 按数量换算；MealTemplate 展开；模板修改不改变历史。
- 每日营养汇总、剩余和超标值正确，日期边界使用本地日历。

### SwiftData

- 使用内存 ModelContainer 覆盖全部实体 CRUD。
- 验证 Workout/Routine/MealTemplate 级联删除。
- 验证 FoodPreset 删除后 FoodLogEntry 保留。
- 验证进行中训练查询和恢复。

- 验证 1.0 磁盘数据库轻量迁移至 1.1，旧 ID、数值、完成状态保留。
- 验证备份 11 类实体往返、幂等导入、ID 冲突、活动训练冲突和无效备份不修改原数据。
- 验证只读存储保存失败可见且不显示成功。

### UI

- 设置和修改营养目标。
- 开始空白训练、添加动作、完成力量组并结束。
- 从 routine 开始训练并验证预填值。
- 选择有氧动作后默认显示有氧字段，可切换其他方式；验证当前方式的必填状态。
- 直接记录饮食、从常用食物和固定餐记录。
- 编辑/删除历史、处理删除确认和所有空状态。
- 终止并重启 App 后数据仍存在。

- 完成并再次训练，检查上次表现、休息计时、重量/容量 PR 和历史编辑取消。
- 每 100g 食物按实际克重记录、修改分量、最近食物再次记录、周报。

## 人工检查

- 浅色/深色、高对比、最大 Dynamic Type、VoiceOver 顺序和标签。
- 数字键盘、焦点切换、长名称换行、中文/英文动作搜索。
- 训练中切后台、强制结束 App、再次打开并继续。
- 1,324 条动作滚动和筛选无明显卡顿。
- 关于页和第三方声明准确，App 包内无图片/GIF。

## 执行命令

当前机器已激活 Xcode 26.6。先执行不依赖具体设备的无签名 Simulator 构建：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

再使用当前已安装的 `iPhone 17`（iOS 26.5）运行单元测试和 UI 测试：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' test
```

## 当前验证记录

| 日期 | 检查 | 结果 |
| --- | --- | --- |
| 2026-08-03 | 1.0 历史基线 | Simulator 构建、13 单元测试、10 UI 测试通过 |
| 2026-09-19 | Xcode / Runtime | Xcode 26.6（17F113），Swift 6.3.3，iOS 26.5 |
| 2026-09-19 | 1.1 Release 无签名构建 | generic iOS Simulator，`BUILD SUCCEEDED` |
| 2026-09-19 | 1.1 单元测试 | 42 项通过，包含旧磁盘库迁移、备份往返及冲突、数值边界、PR 和周边界 |
| 2026-09-19 | 1.1 完整 UI 回归 | 16 项通过、0 失败；与 42 个单元测试在最终同一轮 `xcodebuild test` 中通过 |
| 2026-09-19 | 动作默认方式审计 | 1,324 条全覆盖：862 重量×次数、371 次数、82 时长、9 有氧 |

本轮模拟用户流程包括：新建模板开始训练、记录四种方式、休息计时、完成后再次训练并突破 PR、历史编辑取消、强制终止后恢复训练与计时、饮食增删改、常用食物复用、每 100g 换算和修改分量、固定餐调整克重后复制到另一餐、周报、保存失败反馈。

本地验收结果保存在 `/private/tmp/trainote-upgrade/`：`acceptance-results.xcresult`、`acceptance.log`、`release-acceptance.log`。这些是当前开发机上的测试证据，不属于 App 包或仓库交付内容。

小屏视觉检查：iPhone SE（第 3 代）/ iOS 26.5，已检查首页浅色、深色、最大辅助字号与高对比截图。未完成所有页面的 VoiceOver 检查。最后一轮系统文件选择器人工点击因主机锁屏受阻；备份的格式、11 类实体往返、重复导入、冲突与原子性由自动化测试验证。

## 验收标准

- Build、单元测试和 UI 测试全部通过。
- 不存在崩溃、数据丢失、动作数据缺项、媒体许可违规或运行时网络请求。
- 人工检查项有记录，发现的问题在交付前修复或明确列为已知限制。

## 已知未覆盖风险

- Simulator 自动化覆盖启动、SwiftData 持久化、升级与核心交互；真机、VoiceOver 全流程、长时间使用和最低支持的 iOS 17 Runtime 尚未验证。
- 本地验证不代替签名 Archive、TestFlight、正式设备验收与公开隐私/支持页发布。
