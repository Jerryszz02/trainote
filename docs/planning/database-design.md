# Trainote iOS v1 数据库设计

## 文档目的

定义本地 SwiftData 模型、关系、字段含义、校验和生命周期。

## 数据边界

动作目录是只读 JSON，不进入 SwiftData。SwiftData 只保存用户训练、routine、饮食模板、饮食日志和营养目标。

## 实体

| 实体 | 关键字段 | 关系与语义 |
| --- | --- | --- |
| `Workout` | `id`、标题、开始/结束时间、状态、备注、来源 routine 名称快照、可选休息截止时间 | 级联拥有多个有序 `WorkoutExercise` |
| `WorkoutExercise` | 上游动作 ID、中英文名称快照、顺序、记录模式、备注 | 级联拥有力量组；有氧指标由独立 `CardioEntry` 子对象保存 |
| `StrengthSet` | 顺序、重量 kg、次数、时长秒数、完成状态 | 必须属于一个训练动作 |
| `CardioEntry` | 时长秒数、距离 km、热量 | 属于一个训练动作 |
| `Routine` | `id`、名称、备注、创建/更新时间 | 级联拥有多个有序 `RoutineExercise` |
| `RoutineExercise` | 上游动作 ID、名称快照、记录模式、默认组数/次数/重量或时长/距离 | 必须属于一个 routine |
| `FoodPreset` | 名称、每份说明、每份卡路里/碳水/蛋白质/脂肪 | 删除不影响历史日志 |
| `MealTemplate` | 名称、备注 | 级联拥有多个有序 `MealTemplateItem` |
| `MealTemplateItem` | 名称和营养快照、数量、份量说明 | 不依赖 FoodPreset 后续变化 |
| `FoodLogEntry` | 时间、餐次、名称、数量、份量、四项营养总值 | 完整快照，可独立编辑 |
| `NutritionGoal` | 卡路里、碳水、蛋白质、脂肪、更新时间 | v1 只保留一份当前目标 |

## 枚举

- `WorkoutStatus`：`inProgress`、`completed`。
- `TrackingMode`：`strength`、`repetitions`、`duration`、`cardio`。
- `MealType`：`breakfast`、`lunch`、`dinner`、`snack`。

枚举在 SwiftData 中以稳定 raw string 保存；未知值必须显式回退并在测试中覆盖。

## 校验

- 重量、距离、卡路里、宏量营养素和数量必须为有限非负数。
- 力量次数和 routine 默认组数/次数必须为正整数。
- 有氧时长必须大于 0；距离和热量可选。
- 所有用户可见名称去除首尾空白后不得为空。
- 关系中的顺序使用从 0 开始的整数；读取时始终按顺序和 ID 进行稳定排序。

## 快照与生命周期

- 从 routine 开始训练时复制动作名称和计划参数，随后两者互不影响。
- 从 FoodPreset 或 MealTemplate 记录饮食时复制营养值，模板修改或删除不改写历史。
- 删除 Workout/Routine/MealTemplate 时级联删除其从属对象；删除 FoodPreset 不删除 FoodLogEntry。
- App 不提供自动过期或后台清理。

## 迁移策略

- v1 使用首个 SwiftData schema；1.1 新增可选 `Workout.restEndsAt` 与默认 0 的 `StrengthSet.durationSeconds`，保留原有枚举 raw values。磁盘旧库迁移有回归测试。
- 后续新增可选字段优先使用轻量自动迁移；破坏性字段或关系变更必须新增版本化 Schema 和 MigrationPlan。
- 不允许通过删除本地 store 来掩盖迁移错误。

## 验收标准

- 所有实体可在内存 ModelContainer 中创建、读取、更新和删除。
- 级联删除和非级联历史快照语义与本文一致。
- App 重启后进行中训练和所有历史记录保持一致。

## 待确认

1.1 备份格式版本为 1，包含全部 11 类持久化实体。先验证整个文件再通过独立 context 原子导入；同类型同 ID 保留本机版本并跳过，跨类型/子对象 ID 冲突拒绝。最多一场进行中训练。文件限制 20MB、100,000 个对象。营养数据为快照；备份不包含 AppStorage 中的入门提示和休息时长偏好。

