# P1：简体中文与 English 计划

状态：**计划中，待用户审阅；未添加 String Catalog 或修改应用代码。**

日期：2026-10-12（Europe/London）。诊断基线：`c970330a33208b9f7862ae6e960d5f5b98a17a1f`。关联：[性能计划](device-performance-plan.md)、[交互计划](first-use-interaction-plan.md)。

## 1. 交付目标

首批完整支持简体中文与 English。首次启动默认跟随系统；设置提供“跟随系统 / 简体中文 / English”，手动选择持久化，切回系统后立即恢复语言匹配。切换不重建正在记录的训练、不丢表单、不重置导航。

覆盖所有应用控制的按钮、导航、错误、空状态、表单、报告、辅助功能文字和必要说明。采用随 App 打包的 String Catalog 与已有双语动作数据；不引入运行时 AI 翻译、外部翻译请求或新遥测。

本改动只处理语言、呈现与格式化契约，不改变训练/营养/恢复算法、内部 ID、数据库字段含义、备份 schema 或用户原文。后续其他语言通过相同资源和解析策略扩展。

## 2. 当前诊断

| 事实 | 代码证据 | 计划含义 |
| --- | --- | --- |
| `project.yml` 的开发语言为 `zh-Hans`；当前 App 目录没有 `.xcstrings`、`.strings` 或 `.stringsdict` | [project.yml](../../project.yml)、资源清单 | 需要建立正式本地化资源，不能只设置一个 Locale |
| 设置只有固定公斤/公里展示，没有语言选择 | [SettingsView.swift](../../Trainote/Features/Settings/SettingsView.swift) | 添加独立语言偏好，不自动改变单位 |
| 动作目录 1,324 项均有非空 `nameZh/nameEn/stepsZh/stepsEn` | [ExerciseCatalog.json](../../Trainote/Resources/ExerciseCatalog.json) 的字段完整性检查 | 可以按语言选现有内容；字段非空不等于已完成人工翻译质量审核 |
| `displayName` 固定中文优先，动作详情同时展示两套说明 | [ExerciseCatalog.swift](../../Trainote/Services/ExerciseCatalog.swift)、[ExerciseViews.swift](../../Trainote/Features/Shared/ExerciseViews.swift) | 统一展示选择策略；双语搜索仍始终有效 |
| 训练/模板保存中英文动作名称快照；工厂写入默认标题、中文目标说明 | [WorkoutModels.swift](../../Trainote/Models/WorkoutModels.swift)、[RoutineFactory.swift](../../Trainote/Services/RoutineFactory.swift) | 展示选择不能写反快照；系统生成文本与用户输入要区别处理 |
| 标签、状态和错误分布在 View、DomainEnums、服务、分析和可访问性代码 | [DomainEnums.swift](../../Trainote/Models/DomainEnums.swift)、Features/Services | 不能依赖 View 字面量自动提取覆盖动态 String |
| 报告校验严格比较固定中文文案 | [ReportPolicy.swift](../../Trainote/Services/AIReports/ReportPolicy.swift) 的 `ReportText`、`validate` | 必须将显示翻译与 wire 校验分离，否则英文设置可能使合法报告被拒绝 |

此处为源码诊断；尚未实际验证英文系统首启、语言热切换、英文大字号、VoiceOver 或手机上的当前中文排版。

## 3. 语言解析与设置方案

### 状态模型

新增独立应用偏好 `system / zh-Hans / en`，通过 UserDefaults/AppStorage 保存，缺省为 `system`。将偏好与实际解析得到的界面语言分开；不能把第一次解析结果写回成手动选择。

| 情形 | 行为 |
| --- | --- |
| 从未选择；系统首选 English | 第一屏直接 English，不先闪中文再改 |
| 从未选择；系统首选简体中文 | 第一屏简体中文 |
| 系统多语言或其他语言 | 按系统/系统 App 语言偏好列表找受支持语言；本期没有匹配时使用 English。繁体中文不是已支持语言，不把简体文案标成繁体 |
| 选择简体中文或 English | 应用自有界面即时切换；关闭并重开仍保留 |
| 从手动切回跟随系统 | 清除手动覆盖语义，立即重新解析系统偏好，不沿用旧手动 Locale |
| system 模式下系统语言后来改变 | 下次启动/回前台重新解析；系统可能重启应用，草稿恢复仍走正常数据保护路径 |
| 手动模式下系统语言改变 | 应用选择保持，区域格式按下文约定处理 |

语言选项固定以自称显示“简体中文”“English”；“跟随系统 / System Default”随当前界面语言显示。设置项与单位位于独立区块，不把英文等同于磅/英里。

### 技术约束

- 使用一个语言解析/文本呈现服务，SwiftUI 环境和普通 Swift 服务读取同一有效语言。普通 `String`、LocalizedError、图表和 UIKit/SceneKit 辅助功能文字必须显式经过本地化接口。
- 不仅设置 `.environment(\.locale, …)` 就宣称所有文案完成；动态字符串与 Foundation 层需要通过所选语言的资源 bundle/table 解析。禁止全局 swizzle Bundle 或写系统 `AppleLanguages` 来强制重启应用。
- 切换时更新呈现依赖，不对根 View 使用 `.id(language)`，不重建 ModelContainer、训练对象、表单持有者、媒体播放对象或 NavigationStack。
- 页面 sheet 和 navigation destination 都接收相同语言环境；toast/错误状态保存结构化 code/参数，显示时本地化，避免缓存旧语言的用户可见字符串。
- 系统授权弹窗由 iOS 管理：提供双语权限用途资源，遵循系统对 App 语言的选择；不能承诺进程内自选语言会即时改写系统弹窗。此限制在验收记录中单列，不把系统文本当成应用自有文案漏译。

## 4. String Catalog 与覆盖清单

采用稳定语义 key 与明确的翻译注释；建议以 English 为默认值，简体中文提供对应翻译。确定资源开发语言/默认回退时同步 XcodeGen 配置与已提交工程，避免二者漂移。一次迁移后的默认值不得继续留中文但声明为 English。

先采用一个 `Localizable.xcstrings` 和系统元信息用途的 `InfoPlist.xcstrings`，避免按每个文件拆出大量表。只有说明正文的规模确有需要时再分独立 table，所有查找统一经过同一入口。

| 区域 | 必须覆盖 | 主要文件范围 |
| --- | --- | --- |
| App 壳层、今日、首次使用 | Tab、日期、开始/继续训练、记录饮食、空状态、引导、设置入口 | AppShell、TodayView、TodayRecoveryCard、HealthOnboardingView |
| 训练与历史 | 名称占位、模式、组/次/时长、RIR、热身/工作组、计时、取消/完成/失败、上次表现、PR | TrainingView、ActiveWorkoutView、RoutineViews、WorkoutInsights、DomainEnums |
| 动作库 | 搜索、筛选、分类、步骤标题、无结果、目录错误、媒体状态 | ExerciseViews、LibraryView、ExerciseCatalog、ExerciseAnimationView |
| 饮食与目标 | 食物表单、份量、餐次、营养、固定餐、复制、日期、确认完整、保存错误 | NutritionView、FoodLibraryView、NutritionModels、NutritionSummary、Settings |
| 趋势、恢复、建议 | 图表/图例、数据状态、体感、肌群、建议与理由、版本/来源详情 | Trends、Recovery、Recommendations、Analysis/Contracts |
| 报告 | 摘要、事实标签、建议、有效期、历史、缺失、错误、依据页 | AIReports、HealthReportsView、ReportPolicy 的呈现层 |
| 设置、帮助、隐私、备份 | 语言/单位、操作结果、导入冲突、说明目录、许可引导、撤回 | Settings、HealthHelpView、BackupArchive、HealthFeatureAccess |
| 无障碍与系统元信息 | label/value/hint、图表替代描述、控件状态、HealthKit 用途文本 | 全 App、InfoPlist.xcstrings、project.yml |

处理复数、插值占位与语序：例如 `1 set / 2 sets`、`Set 3`、`12 reps`；不拼接“数字 + 中文单位”再翻译。资源中说明参数单位/含义，保持数值格式和占位类型一致。系统原始错误转为可行动的本地化主文案，底层错误详情只在需要诊断时展开。

覆盖审计包含 UI 字面量、返回 String 的枚举/函数、字典值、错误 description、图片/3D accessibility、图表 axis、通知/导出名等实际存在的入口。静态脚本只提供候选清单；品牌名、ID、用户内容和协议常量有说明性的排除项，不能用“检出中文数量为零”替代验收。

## 5. 动作、用户内容与历史数据

1. 中文界面显示中文动作名/步骤，英文界面显示英文动作名/步骤；不再在每一行、每个详情同时堆两套说明。另一语言可在主动查看时获得，不作为常驻小字。
2. 两种语言都能搜中英文名称、部位/器械同义词；查询不依赖当前显示语言。沿用性能计划的一份双语索引，切语言不重新加载全库、不清空搜索词和筛选条件。
3. 部位、器械、肌群用稳定 raw value → 本地化标签映射，补齐目前直接显示的英文原始标签。内部 exercise ID、muscle ID、enum rawValue 与筛选 ID 不变。
4. `nameZhSnapshot` 永远写中文来源字段、`nameEnSnapshot` 永远写英文字段；不能在切为英文后让工厂把新的 `displayName` 写进中文快照。
5. 已有训练、模板按保存的双语快照选显示，不用最新目录名称重写历史；字段确实缺失时回退到另一语言，不改库。
6. 用户笔记、训练名、模板名、食物名、份量说明和自由文本保持原文。系统新建的默认名称/目标描述按创建时语言生成；历史未标记来源的名称即使看起来像默认值也不批量翻译。
7. 翻译质量抽查覆盖常用动作、长名称、有氧/时长、不同器械和带安全步骤的动作；修正文案不能更改动作身份或训练含义。

## 6. 报告、数字和日期

### 报告呈现

- 现有 wire 校验的固定文案、schemaVersion、actionID、evidenceID 和 inputFingerprint 保持协议语义稳定；不直接把 `ReportText` 中校验用的中文替换成跟随 Locale 的字符串。
- 显示层从已验证的事实/动作码、报告类型及模板版本生成本地化文案，复用 String Catalog；语言不参与营养/恢复数值计算，不触发新 AI 请求。
- 历史报告保留原始接收内容和证据。已知固定模板可按模板版本在展示层翻译；不能识别的历史自由文本保留原文并按内容类型处理，不运行时猜译或伪装成新生成报告。
- 语言切换后摘要、事实单位、日期、可访问性全部更新；重新打开历史仍是相同 reportID 与原始事实。界面显示缓存需区分 locale；分析事实缓存无需仅因翻译改变而失效。

### 日期、数值与单位

- 界面语言决定文案；日期顺序、12/24 小时、小数/分组分隔符尊重区域偏好，并与输入解析保持一致。用显式的 locale/FormatStyle，不散落固定 DateFormatter 和 String(format:)。
- 内部日期键、JSON 数字、时区、分析窗口与 Gregorian/POSIX 格式维持既有契约。英文不能改变“同一天”的归属、历史营养目标或恢复计算结果。
- 未提交输入保留原始文本，字段进入编辑时固定解析约定，提交后再按当前区域重新格式化；切换语言时不能把 `62.5`、`62,5` 或半输入小数错误转换/清空。候选非法格式显示字段错误，不默默变成 0。
- 重量单位与语言独立。本期默认保持现有 kg、距离 km，设置中独立展示；**English 不自动切成 lb**。如果需要可选 kg/lb，需另确认单位转换子项，覆盖输入、步进、历史、PR、导出和精度；不将其悄悄夹带进双语改动。

## 7. 排版与状态连续性

- 主要动作按钮不用固定中文宽度；英文长标题可换行或使用明确短标签。大字号下改纵向排布，不能通过缩小字体让按钮“勉强放下”。
- 单位紧邻对应数值，表单字段有持续可见标签，不仅靠 placeholder。训练组的重量/次数/完成区优先，RIR 等可选字段由交互计划决定层级。
- 保留稳定 accessibilityIdentifier，避免自动化测试依赖中文按钮标题；VoiceOver 的读出顺序、状态和提示随语言一致。
- 语言切换只更新文案。训练计时、休息倒计时、当前组、选择动作、食品草稿、焦点/键盘、模态页面和导航返回路径均需验证。系统重启时的数据恢复与性能计划的保存契约一致。

## 8. 实施拆分与验收

| 步骤 | 内容 | 验收门 |
| --- | --- | --- |
| L1 | 文案清单、术语表、String Catalog、语言解析与偏好 | 英文/中文首启、持久化、切回系统、缺失回退单测 |
| L2 | 今日/训练/动作/饮食/设置主流程完整迁移 | 两种语言都能完成三条记录流程，输入状态连续 |
| L3 | 趋势/恢复/报告/帮助/错误/无障碍完整迁移 | 全页面覆盖审计、报告协议回归通过 |
| L4 | 长英文、大字体、暗色和区域组合 | UI/真机截图与操作回读，无截断重叠，离线也完整可用 |
| L5 | 独立 PR 和未验证清单 | 不改内部 ID、备份兼容与核心功能通过；等用户决定合并/安装 |

这是一个独立的语言改动线，迁移按模块提交，最终才宣称“完整双语”。不把 L2 首页/主流程完成当作整项完成。若审查体积过大可分连续小 PR，但每个 PR 明确范围，完整验收前不对外宣布已支持 English。

### 必测矩阵

| 维度 | 用例 |
| --- | --- |
| 首次安装 | 英文系统→English；简体系统→简体；其他语言的偏好匹配/English 回退 |
| 持久化 | system→中文→重启；system→英文→重启；手动→system；system 模式修改系统语言 |
| 进行中训练 | 已输入重量/次数/备注、已有完成组和计时，切换后值/ID/状态不变，完成并重新打开一致 |
| 饮食/模板表单 | 半填未保存、含小数、正在键入中文，切换后返回不丢稿；取消不意外保存 |
| 动作 | 两种语言展示、双语搜索、筛选、详情步骤、模板/历史快照和媒体状态 |
| 报告 | 本地/历史固定模板、错误、缺失、撤回；中文 wire 校验与英文 UI 同时正确，无新增网络调用 |
| 格式 | zh-CN、en-GB、en-US，以及使用小数逗号的区域；午夜/时区切换内部日期键不变 |
| 外观/辅助功能 | 两种语言 × 明暗色 × 默认/最大辅助字号；VoiceOver、Reduce Motion、较窄屏与主验收真机 |
| 数据兼容 | v1/v2 备份、双语动作快照、用户原文、模型 rawValue/主键一致 |

在现有 `TrainoteTests`、`AIReportTests`、`AIReportRealContractTests`、`HealthBackupTests` 和主流程 UI 测试上添加必要用例；新增语言解析测试只验证选择语义，不镜像实现。UI 测试通过系统语言启动参数与应用内设置分别覆盖，不能只注入自定义 Locale 绕过首启解析。

## 9. 风险、回滚和待确认

- 最大风险是动态字符串漏译、语言切换引发 View 身份重置，以及报告校验误用本地化文案；三者分别设独立回归门。
- 移除/收纳冗余说明由交互计划负责，语言计划先保证存在的必要内容能正确显示；两条线共享语义 key，不同时重写同一页面的信息结构。
- 回滚移除语言覆盖、恢复默认显示即可；不需要数据库迁移或重置用户数据。持久化语言值可以保留为无害偏好，不删用户配置目录。
- 本次未运行双语 UI、生成资源、构建或测试；上述均为计划。现有中英文动作仅检查字段完整性，未声称逐条人工校译。
- 待审阅的范围点：English 作为不支持语言的回退；是否另行需要 kg/lb 切换。两者不影响“默认系统、英文系统首启英文”的必达要求。

## 10. 方法参考

- [Apple：Localizing and varying text with a string catalog](https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog)：本地化资源、插值与复数变体。
- [Apple：Preparing your app’s text for translation](https://developer.apple.com/documentation/xcode/preparing-your-apps-text-for-translation)：可提取的本地化 API 与动态文本覆盖。
- [Apple：Preparing views for localization](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization)：视图文案及译者上下文。具体的偏好状态、热切换、数据保护和报告适配是本项目方案，仍需验证。
