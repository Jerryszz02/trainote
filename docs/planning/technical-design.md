# Trainote iOS v1 技术设计

## 文档目的

定义 App 壳层、状态归属、动作数据导入、业务操作边界和隐私约束。

## 技术栈

- SwiftUI，最低 iOS 17。
- `project.yml` 使用 Swift 5.9 language mode；当前验证工具链为 Xcode 26.6、Apple Swift 6.3.3。
- SwiftData 只保存用户创建和修改的数据。
- Observation：共享只读动作目录使用根部持有的 `@Observable` 服务并通过 Environment 注入。
- XCTest/XCUITest；不引入第三方 Package。

## App 壳层

- 根 `App` 创建一个 `ModelContainer` 和一个 `ExerciseCatalog`。
- `TabView` 包含“今日、训练、饮食、资料库”，每个 Tab 拥有独立 `NavigationStack`。
- 页面局部状态使用 `@State`/`@Binding`；SwiftData 使用 `@Query` 和 `ModelContext`；不建立全局 ViewModel。
- 编辑器使用 `sheet(item:)`，由 sheet 自己校验、保存并 `dismiss()`。

## 动作目录

- 数据源固定为 `hasaneyldrm/exercises-dataset` 提交 `118e4bd6b14da6df0e36605d7169b65db18389a4`。
- 手动导入脚本从固定 raw URL 读取 JSON，校验数量、唯一 ID、双语说明和必需字段。
- 脚本合并中文名称映射，输出随 App 提交的 `ExerciseCatalog.json`；导入不作为每次构建的网络步骤。
- 输出字段仅包括 ID、中英文名称、部位、器械、目标、肌群和中英文说明；媒体字段必须被剔除。
- `ExerciseCatalog` 启动时一次解码，在内存中同步筛选 1,324 条数据；中文名缺失时回退英文名。
- 在 `THIRD_PARTY_NOTICES.md` 和 App 关于页保留数据集 MIT 版权与来源。

## 业务操作

- `RoutineFactory` 把 routine 复制成新的进行中训练；动作名称和默认参数形成快照。
- `NutritionSummary` 是纯值计算：按本地日历范围汇总日志，计算已摄入、剩余和超标值。
- 固定餐应用操作在一个 ModelContext 保存周期内展开全部食物日志；任一条校验失败则整批不保存。
- 完成训练前执行领域校验；进行中状态在每次编辑后持久化，不依赖页面仍在内存。

## 错误和回退

- 动作资源缺失或解码失败：保留错误信息并提供重试；开发/测试构建把错误视为测试失败。
- SwiftData 容器创建失败：App 显示不可恢复错误页，不静默切换临时内存库。
- 表单输入无效：禁用保存并在对应 section 显示中文说明。
- 删除训练、routine、预设或日志前显示确认；级联删除只影响明确从属对象。

## 隐私与许可证

- 所有健康相关记录仅保存在 App 沙盒，不上传、不分析、不记录内容日志。
- 不请求网络、相机、HealthKit、通知或定位权限。
- 不把用户饮食或训练内容写入控制台。
- 不复制上游 `images/`、`videos/`、`image` 或 `gif_url` 字段，因为仓库许可证明确说明媒体需要单独授权。

## 当前实现状态

- 原生 Xcode 工程、App 壳层、SwiftData 模型、动作目录、训练/routine、饮食/目标/今日汇总均已有对应源码。
- 单元测试、UI 测试、Preview 和第三方许可证文件已纳入工程。
- 2026-07-16 已在 Xcode 26.6 下通过 generic iOS Simulator 无签名构建；完整测试和人工验收状态以 [test-plan.md](test-plan.md) 为准。

## 维护顺序

1. 先同步 PRD、技术设计和数据库设计中的行为或数据约束。
2. 修改模型或纯业务服务，并补齐对应单元测试。
3. 修改依赖这些模型和服务的 SwiftUI 功能页面。
4. 涉及动作目录时重新运行导入校验，并复核媒体字段与许可证边界。
5. 最后执行构建、单元测试、UI 测试和人工辅助功能检查。

## 验收标准

- App 无第三方依赖和运行时网络流量。
- 根部只有一个生产 `ModelContainer`，Preview/测试使用独立内存容器。
- 页面没有不必要的共享 ViewModel，Tab 导航历史相互独立。
- 动作目录和用户历史使用稳定 ID/快照关联，修改模板不污染历史。

## 待确认

- 正式发布用 Bundle ID、签名 Team 和目标设备验证要在进入 App Store/TestFlight 阶段确认。
