# Trainote iOS v1 测试计划

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
- 动作按目录分类固定为力量或有氧，训练和 routine 编辑器不能切换记录方式。
- 力量组数、完成条件和无效数值校验正确。
- 有氧时长必填，距离和热量可选。
- FoodPreset 按数量换算；MealTemplate 展开；模板修改不改变历史。
- 每日营养汇总、剩余和超标值正确，日期边界使用本地日历。

### SwiftData

- 使用内存 ModelContainer 覆盖全部实体 CRUD。
- 验证 Workout/Routine/MealTemplate 级联删除。
- 验证 FoodPreset 删除后 FoodLogEntry 保留。
- 验证进行中训练查询和恢复。

### UI

- 设置和修改营养目标。
- 开始空白训练、添加动作、完成力量组并结束。
- 从 routine 开始训练并验证预填值。
- 选择有氧动作后只能记录有氧字段，并验证必填状态。
- 直接记录饮食、从常用食物和固定餐记录。
- 编辑/删除历史、处理删除确认和所有空状态。
- 终止并重启 App 后数据仍存在。

## 人工检查

- 浅色/深色、高对比、最大 Dynamic Type、VoiceOver 顺序和标签。
- 数字键盘、焦点切换、长名称换行、中文/英文动作搜索。
- 训练中切后台、强制结束 App、再次打开并继续。
- 1,324 条动作滚动和筛选无明显卡顿。
- 关于页和第三方声明准确，App 包内无图片/GIF。

## 执行命令

完整 Xcode 安装后先运行：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

再选择已安装的 iPhone Simulator 运行：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote -destination 'platform=iOS Simulator,name=<已安装的 iPhone>,OS=latest' test
```

## 验收标准

- Build、单元测试和 UI 测试全部通过。
- 不存在崩溃、数据丢失、动作数据缺项、媒体许可违规或运行时网络请求。
- 人工检查项有记录，发现的问题在交付前修复或明确列为已知限制。

## 已知未覆盖风险

- 当前本机没有完整 Xcode，暂时无法确认 Simulator 和 SwiftData 的真实运行结果。
- App Store 签名、TestFlight 和正式设备测试不在 v1 本地实现验收范围内。
