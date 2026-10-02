# 健康分析：研究证据与模型资产

## 文档状态与范围

- 状态：`实施中，联合验收未完成`；研究证据已整理，版本化产品规则及测试已进入 `agent/health-integration` 的 PR；用户试验、科学有效性与健康效果均未验证。
- 文档版本：`evidence-v0.2`；文献核查日期：2026-10-03（Asia/Shanghai）；实现状态按本分支当前源码核对。
- 原规划分支：`agent/health-analysis-plan`；本文件不代表默认分支或已发布能力。
- 目的：为体重趋势、摄入建议、肌群准备度和分析报告提供可追溯的证据边界。
- 来源：原始论文、PubMed/PMC、NIDDK/National Academies、研究团队官方仓库。
- 非目标：医疗诊断、损伤判断、个体营养处方、复制研究模型或外部服务代码。
- 现有实现与文献发现分开记录；通过工程测试只证明指定输入下的计算和流程行为，不证明生理预测准确。
- **研究证据及适用人群仍待运动营养、运动科学专业审查。**
- 文档入口由 [规划索引](README.md) 维护；具体产品默认值以[实施提案](health-analysis-plan.md)为准，工作树所有权见[交付计划](health-analysis-delivery.md)。

## 阅读方法

下文区分三类信息，不能相互替代：

| 类型 | 含义 | 实现时应如何使用 |
| --- | --- | --- |
| 文献发现 | 原研究在指定样本、干预和终点下得到的结果 | 保留适用范围、局限与来源 ID |
| 方法迁移 | 借鉴变量、分析过程、报告结构或评价方法 | 在本产品数据和目标人群中重新验证 |
| 产品参数 | 平滑窗口、更新周期、权重、阈值、颜色与分数映射 | 明确版本；通过测试和校准选择，不能冒充论文常数 |

文献汇总是定向检索，不是完成了预注册的系统综述或正式证据分级。
论文摘要可以核实研究设计和主要结果，不能替代完整偏倚评估。
本文件以简短转述为主，不复制图表、数据集或不明许可的代码。

## 体重与营养证据矩阵

### N01 — Mifflin / St Jeor，1990

- 原始来源：[A new predictive equation for resting energy expenditure](https://pubmed.ncbi.nlm.nih.gov/2305711/)；DOI `10.1093/ajcn/51.2.241`。
- 设计：498 名健康成人，19–78 岁，含正常体重和肥胖者；间接测热与回归建模。
- 发现：由体重、身高、年龄及研究所用性别变量估计静息能量消耗（REE）。
- 可支持：将 REE 公式作为冷启动估计，随后利用可靠的个人记录修正摄入策略。
- 不能推出：公式直接给出总日消耗（TDEE）、个体真实代谢率，或对所有年龄/生理状态准确。
- 迁移边界：活动系数、性别变量输入方式及特殊人群处理属于另行设计，不由该公式解决。

### N02 — Hall 等，2011；NIDDK Body Weight Planner

- 原始来源：[Lancet 动态能量平衡模型](https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593/)；DOI `10.1016/S0140-6736(11)60812-X`。
- 官方背景：[NIDDK Research Behind the Body Weight Planner](https://www.niddk.nih.gov/research-funding/at-niddk/labs-branches/laboratory-biological-modeling/integrative-physiology-section/research/body-weight-planner)。
- 设计：成人代谢/体重动态模型，结合已有实验资料及模拟；不是 Trainote 的前瞻性试验。
- 发现：体重变化伴随能量消耗和身体组成变化，固定热量差不能无限线性外推体重。
- 可支持：区分初始估计和随时间调整的估计；长期预测应考虑动态适应与输入不确定性。
- 不能推出：用每日体重差乘 `7,700 kcal/kg` 就测得真实 TDEE，或 14 天数据必然足够校准。
- 迁移边界：简单趋势反馈算法只能称为借鉴能量平衡原则，不能称为完整复现 Hall 模型。
- 人群边界：[NIDDK 工具说明](https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner)针对成人，不适用于未成年人、孕期或哺乳期；不等于其他人群已通过本产品审查。

### N03 — Morton 等，2018

- 原始来源：[蛋白质补充与抗阻训练荟萃分析](https://pubmed.ncbi.nlm.nih.gov/28698222/)；DOI `10.1136/bjsports-2017-097608`。
- 设计：49 项随机试验、1,863 人，抗阻训练至少 6 周；分析补充蛋白对力量与去脂体重的影响。
- 发现：总蛋白摄入与去脂体重增益的分段回归拐点约 `1.62 g/kg/day`，95% CI 为 `1.03–2.20`。
- 可支持：健康成人抗阻训练时，蛋白目标按体重和训练背景设置，而非只取固定热量占比。
- 不能推出：每个人的精确需求都是 1.62，2.20 是个人安全上限，或该结果直接覆盖能量限制期。
- 更正核查：[2020 更正](https://pmc.ncbi.nlm.nih.gov/articles/PMC7513243/)补充作者与运动补剂企业的利益关系披露；不是上述剂量结果的修正。

### N04 — Iraki 等，2019

- 原始来源：[Nutrition Recommendations for Bodybuilders in the Off-Season](https://pmc.ncbi.nlm.nih.gov/articles/PMC6680710/)；DOI `10.3390/sports7070154`。
- 设计：自然健美非赛季营养的叙述性综述，并非验证完整 App 策略的随机试验。
- 发现：建议新手/中级选手约 10%–20% 热量盈余、每周增重约体重的 0.25%–0.5%；高级选手更保守。
- 可支持：增肌目标应随训练经验调整；`1.6–2.2 g/kg/day` 蛋白可作为该人群的参考区间。
- 不能推出：所有健身用户都应采用 20% 盈余，或达到该增重速度意味着增加的都是肌肉。
- 迁移边界：应与 N06 的后续实验及个人反馈共同考虑，不机械把综述建议变成自动处方。

### N05 — Garthe 等，2011

- 原始来源：[两种减重速度与运动员身体组成/表现](https://pubmed.ncbi.nlm.nih.gov/21558571/)；DOI `10.1123/ijsnem.21.2.97`。
- 设计：24 名精英运动员，分配至目标每周减重 0.7% 或 1.4% 的组，同时进行抗阻训练。
- 发现：较慢减重组在该实验中的去脂体重及部分力量结果更有利。
- 可支持：减脂速度选择应顾及力量、去脂体重及训练表现，不一味追求更快减重。
- 不能推出：0.7% 是所有成人最佳速度，或本产品选定的其他减重区间已在此研究中比较。
- 迁移边界：目标速度不等于实际达到的速度；运动员样本不能直接代表全部普通用户。

### N06 — Helms 等，2023

- 原始来源：[Small and Large Energy Surpluses](https://link.springer.com/article/10.1186/s40798-023-00651-y)；DOI `10.1186/s40798-023-00651-y`。
- 设计：21 名有训练经验者进入维持、约 5% 或 15% 盈余组；17 人完成 8 周、每周 3 次训练。
- 发现：更快增重与更大的皮褶增加关联较明确；肌厚/力量结果并非全面改善，高盈余组卧推有优势。
- 可支持：采用保守增重策略并观察身体组成相关信号与训练表现，不能只奖励体重增长。
- 不能推出：大盈余绝无益处、5% 为普适最优值，或短期无显著差异就证明两方案等效。
- 迁移边界：样本小、周期短、训练刺激特定；实际盈余与计划盈余不同，最佳速度仍需个体化。

### N07 — National Academies / IOM AMDR

- 官方来源：[Dietary Reference Intakes 原始报告](https://www.nationalacademies.org/publications/10490)；[成人比例说明](https://www.nationalacademies.org/read/10872/chapter/7)。
- 类型：膳食参考摄入范围，不是运动员增肌处方或某款推荐算法的试验。
- 参考范围：成人碳水 45%–65%、脂肪 20%–35%、蛋白 10%–35% 的总能量占比。
- 可支持：在营养目标中检查宏量分配是否偏离一般成人参考背景，并解释取舍。
- 不能推出：脱离总能量、体重、训练和疾病背景的精确克数，或范围边界是个人毒性阈值。
- 迁移边界：不是中国地区营养标准的替代；地区适用性及运动人群调整待专业审查。

### N08 — Shcherbina 等，2017（历史设备验证）

- 原始来源：[腕戴设备心率与能量消耗准确性](https://doi.org/10.3390/jpm7020003)；DOI `10.3390/jpm7020003`。
- 设计：60 人，7 款当时的设备；坐、走、跑、骑行，与遥测心率及间接测热比较。
- 发现：研究中能量消耗估计的误差显著，不能由心率较准推断热量同样准确。
- 可支持：把设备热量视为带误差的辅助信息，保留设备/来源；避免与活动系数重复计入。
- 不能推出：2017 年误差数值代表 2026 年 Apple Watch 或任何当前设备，也未验证抗阻训练的每肌群负荷。
- 迁移边界：新设备、固件与运动类型需要各自验证；不凭本论文生成跨品牌校正系数。

## 局部疲劳与全身状态证据矩阵

### R01 — Morán-Navarro 等，2017

- 原始来源：[Time course of recovery following resistance training](https://pubmed.ncbi.nlm.nih.gov/28965198/)；DOI `10.1007/s00421-017-3725-7`。
- 设计：10 名训练男性，卧推/深蹲三种组次方案，随访至训练后 72 小时。
- 发现：总次数相同的比较中，力竭方案引起更大即时表现下降，24–48 小时恢复较慢。
- 可支持：除重量与次数外，还记录工作组、距离力竭程度和经过时间。
- 不能推出：固定的每组疲劳百分比、所有肌群的统一 48 小时恢复时间。

### R02 — Refalo 等，2023

- 原始来源：[Proximity-to-Failure and Neuromuscular Fatigue](https://pubmed.ncbi.nlm.nih.gov/36752989/)；DOI `10.1186/s40798-023-00554-y`。
- 设计：24 名训练者，男女各 12；随机顺序比较 6 组卧推至力竭、1-RIR、3-RIR。
- 发现：越靠近力竭，即时举起速度下降越大；24 小时仍有差异，48 小时方案间差异消退。
- 可支持：把 RIR 纳入疲劳估计，并考虑训练者及训练安排差异。
- 不能推出：RIR 自报无误差、举起速度就是肌肉组织恢复百分比，或相同结论适用所有动作。

### R03 — Flatt 等，2019

- 原始来源：[Heart Rate Variability, Neuromuscular and Perceptual Recovery](https://pmc.ncbi.nlm.nih.gov/articles/PMC6835520/)；DOI `10.3390/sports7100225`。
- 设计：10 名训练男性，深蹲、卧推、下拉高负荷训练后比较 HRV、运动表现和主观指标。
- 发现：HRV、表现、主观感受恢复时序不同；各指标变化之间未发现显著相关。
- 可支持：全身自主神经相关信号与局部训练表现分别呈现，不能以一个指标替代另一个。
- 不能推出：手表 HRV 正常即胸/腿恢复正常；小样本未显著也不等于证明永远无关联。
- 迁移边界：论文测量协议与手表后台读数不同；须保留 HRV 定义、单位、设备及测量条件。

### R04 — Ramos-Campo 等，2021

- 原始来源：[Resistance training intensity, sleep and strength recovery](https://pubmed.ncbi.nlm.nih.gov/33795917/)；DOI `10.5114/biolsport.2020.97677`。
- 设计：15 名训练男性随机交叉，比较等次数力竭与非力竭训练，测量夜间睡眠/HRV及次日表现。
- 发现：力竭后次日力量表现下降，但两条件睡眠质量及 HRV 无显著差异。
- 可支持：局部负荷与训练表现不能被一次“睡眠良好/HRV正常”的判断覆盖。
- 不能推出：手表必然识别次日力量下降；研究也不是对任意睡眠分数的准确性验证。

### R05 — Nosaka 等，2002

- 原始来源：[DOMS does not reflect eccentric exercise-induced muscle damage](https://pubmed.ncbi.nlm.nih.gov/12453160/)；DOI `10.1034/j.1600-0838.2002.10178.x`。
- 设计：110 名男性学生，完成不同数量肘屈肌最大离心动作，观察至 4 天后。
- 发现：酸痛与力量、肌酸激酶等其他指标的相关性普遍较弱。
- 可支持：收集局部酸痛作为额外反馈，并与表现、活动受限等信息一起解释。
- 不能推出：不酸就完全恢复、很酸就严重损伤，或酸痛可以单独决定恢复分数。
- 迁移边界：特殊离心实验与日常力量训练不同；疼痛和损伤不能由此评分诊断。

### R06 — Knowles 等，2022

- 原始来源：[Sustained Sleep Restriction and Resistance Exercise](https://pubmed.ncbi.nlm.nih.gov/36136596/)；DOI `10.1249/MSS.0000000000003000`。
- 设计：10 名有训练经验女性随机交叉，比较 9 晚卧床 5 小时与至少 7 小时。
- 发现：持续睡眠限制对部分下肢动作速度和主观负担的影响，比对总训练量更明显。
- 可支持：把睡眠及训练感受加入全身状态，观察可比动作的表现变化。
- 不能推出：少睡 1 小时减固定恢复分，或用一晚睡眠判断某块肌肉的真实恢复程度。

## 从文献到产品规则

| 决策 | 文献能够提供什么 | 仍属于产品设计/待验证的部分 |
| --- | --- | --- |
| 初始能量目标 | N01 的 REE 估计，N02 的动态能量平衡原则 | 活动档位、初始盈余/缺口、有效人群和最低输入条件 |
| 体重趋势 | N02 支持避免单日变化和静态远期外推 | 7 日平滑、14–28 日校准等具体窗口、异常值处理 |
| 自动调整 | N02/N06 支持观察趋势与实际反馈 | 每周更新、每次 100–150 kcal 等步长/限幅都不是通用论文常数 |
| 蛋白目标 | N03/N04 的研究区间与适用条件 | 默认取区间何处、用实际/目标体重、肥胖及疾病背景处理 |
| 脂肪/碳水 | N04/N07 提供参考分配背景 | 哪项优先、冲突时如何降级、饮食偏好与地区适配 |
| 动作到肌群 | R01/R02 支持负荷与力竭程度有关 | 主辅肌群系数、动作技术差异、未知动作映射与人工修正 |
| 疲劳随时间变化 | R01/R02 显示恢复具有时间过程 | 指数衰减、半衰期、负荷叠加及肌群之间差异 |
| HRV/睡眠修正 | R03/R04/R06 支持增加全身上下文 | 个人基线窗口、偏离阈值、缺失数据与跨设备处理 |
| 显示 0–100 | 上述论文均未验证此产品量表 | 分数/区间、红黄绿阈值、解释与置信度标签 |
| 今日训练推荐 | 可综合目标、计划、负荷和反馈 | 减组数、RIR 调整、换日及周训练量约束的具体策略 |

**本项目若显示 70/100，只能表示版本化模型的预计准备度，不能宣称“肌肉已恢复 70%”。**
预测下一次可比训练的表现，不等于测量肌肉组织修复、神经恢复、糖原或损伤风险。
“100/100”也不能表示可以无限加量或不存在受伤风险。
数据不足时应输出未知/低信息量，不能把未记录训练等同于已充分恢复。
“低/中/高置信度”若仅按资料完整度划分，应注明它不是已校准的统计概率。
当前产品也不以论文名、3D 人体或更多小数位包装算法准确性。

### 当前方法版本与工程入口

以下数值是已写入代码的 **P 工程初值**，不是上述论文测得的通用生理常数；更改须同步版本、规则说明和回归用例。

| 规则 | 当前版本与实现入口 | 已实现的边界及对应测试入口 |
| --- | --- | --- |
| 体重和营养趋势 | [`TrendRules`](../../Trainote/Services/Analysis/Trend/TrendRules.swift) `trend-p-v1`、[`TrendCalculator`](../../Trainote/Services/Analysis/Trend/TrendCalculator.swift) | 7 日时间 EMA、21 日斜率、至少 14 日跨度/8 个观测日、近 14 个已完成日中至少 12 个明确饮食确认、7 日调整间隔及单次最多 100 kcal/5%；不完整记录、来源冲突和历史目标缺口会暂停建议。固定计算与原子采用/撤销见 [`TrendCalculatorTests`](../../TrainoteTests/TrendCalculatorTests.swift)、[`TrendWorkflowTests`](../../TrainoteTests/TrendWorkflowTests.swift)。 |
| 肌群与全身状态 | [`RecoveryParameters`](../../Trainote/Services/Analysis/Recovery/RecoveryParameters.swift) `recovery-v0.1`、[`RecoveryCalculator`](../../Trainote/Services/Analysis/Recovery/RecoveryCalculator.swift)、[`ExerciseMuscleMap`](../../Trainote/Services/Analysis/Recovery/ExerciseMuscleMap.swift) `exercise-muscles-v0.1` | 28 日局部窗口、初始衰减常数 36 小时、负荷尺度 6；缺 RIR、未审核动作、未分配力量活动、疼痛/活动受限均保留未知或覆盖限制，不推断成 100 分。合成回归入口为 [`RecoveryCalculatorTests`](../../TrainoteTests/RecoveryCalculatorTests.swift)、[`RecoveryCalibrationTests`](../../TrainoteTests/RecoveryCalibrationTests.swift)。 |
| 今日训练候选 | [`TrainingRecommendationRules`](../../Trainote/Services/Analysis/Recommendations/TrainingRecommendationRules.swift) `training-candidates-p1` | 最近训练观察 24 小时；减量候选保留 50%–75% 组数，提高 RIR 的建议范围为 2–4；疼痛优先于高分，只对用户显式选择且映射已审核的模板给可采用动作。候选与重新核对见 [`TrainingRecommendationTests`](../../TrainoteTests/TrainingRecommendationTests.swift)、[`TrainingAdviceIntegrationTests`](../../TrainoteTests/TrainingAdviceIntegrationTests.swift)。 |
| 分析报告 | [`ReportSnapshotBuilder`](../../Trainote/Services/HealthData/ReportSnapshotBuilder.swift)、[`AIReportAssembly`](../../Trainote/Services/AIReports/AIReportAssembly.swift) | 已实现新鲜快照、事实依赖、受限候选、撤回与本机缓存边界；默认没有远程代理。真实 B 日桶原先被 E 的传输窗口筛选拒绝；E `52fbb321` 修复后 F 的 9 项联合单元及真实报告 UI 通过，原复现保留为回归 [`HealthReportIntegrationTests.testRealTrendDayBucketsAreAcceptedByReportBoundary`](../../TrainoteTests/HealthReportIntegrationTests.swift)。 |

上表的单元测试入口和局部通过记录是工程证据，不能据此宣称当前最终提交已通过全量测试，也不能替代按人/时间划分的预测验证、真机授权及专业审查。日期边界由 E 统一修复，只调整 wire 观测窗口，保留 B 本地日桶事实/依赖并继续拒绝未来原始健康事实。

## 健康 AI 研究：可用资产与接入边界

### A01 — Google PH-LLM / PHIA

- PH-LLM：[官方 README](https://github.com/Google-Health/consumer-health-research/blob/main/phllm/README.md)；[2025 正式论文](https://www.nature.com/articles/s41591-025-03888-0)。
- PHIA：[原始预印本](https://arxiv.org/abs/2406.06464)；[2026 正式论文](https://www.nature.com/articles/s41467-025-67922-y.pdf)；[Google 官方研究说明](https://research.google/blog/advancing-personal-health-and-wellness-insights-with-ai/)。
- 用途：PH-LLM 对睡眠/健身数据作分析；PHIA 用通用 Gemini、代码计算及检索完成数据问答。
- 输入：日级传感器汇总、用户背景、训练负荷等；多模态适配器另需匹配其数值数据约定。
- 已核实资产：PH-LLM 案例、专家评价规则、评估及多模态适配器参考代码；不是完整产品。
- 未核实资产：完整 PH-LLM 微调权重、公开 PH-LLM/PHIA 专用推理 API；不能用普通 Gemini API 冒称已接入它们。
- 许可：PH-LLM 目录 [Apache-2.0 LICENSE](https://github.com/Google-Health/consumer-health-research/blob/main/phllm/LICENSE)；README 表明演示用途、非 Google 正式支持产品、非临床用途。
- 区别：该演示声明是用途/支持边界，不应改写成“Apache-2.0 法律禁止商用”；具体代码、数据、底座与服务条款须分别核对。
- 本项目可借鉴：结构化输入、先计算后解释、专家评分表；未见其验证本项目每肌群真实恢复百分比。
- PHIA 正式论文的数值问答结果不能移植为 DeepSeek 的准确率；论文明确没有验证真实部署中的行为改变或健康结果，领域建议仍需进一步验证。

### A02 — Google SensorLM

- 来源：[官方 README](https://github.com/Google-Health/consumer-health-research/blob/main/sensorlm/README.md)；[训练代码说明](https://github.com/Google-Health/consumer-health-research/blob/main/sensorlm/sensorlm_siglip/README.md)；[论文](https://arxiv.org/abs/2506.09108)。
- 用途：对齐可穿戴传感器与语言，研究活动识别、检索、描述及部分健康任务。
- 输入：论文采用一天的分钟级、多通道特征；并非任意品牌的几个每日汇总数值。
- 已核实资产：描述生成、常量/预处理和 SigLIP 训练参考代码；依赖 Big Vision。
- 未核实资产：官方完整预训练权重、可用完整预训练语料、托管推理 API；README 有数据字样不等于这些均可下载。
- 许可/用途：README 标示 Apache-2.0，演示、非生产/临床用途及非正式支持；底层依赖和数据许可另查。
- 本项目可借鉴：时间序列描述与评估方法；需要输入适配和目标任务验证，不能直接替代准备度算法。

### A03 — Google SensorFM

- 来源：[2026-07-09 官方介绍](https://research.google/blog/sensorfm-towards-a-general-intelligence-and-interface-for-wearable-health-data/)；[论文](https://arxiv.org/abs/2605.22759)。
- 用途：可穿戴基础表示、缺失数据建模及多种健康预测；可向健康 Agent 提供预测结果。
- 输入：来自 Fitbit/Pixel Watch 的 34 个分钟级特征、全天窗口，涉及 PPG、动作、皮电、温度和高度。
- 已核实资产：公开论文和研究说明；未核实官方完整权重、生产 SDK 或外部推理 API。
- 许可边界：能阅读论文不等于获得代码/权重/语料使用授权；本阶段不引入任何实现资产。
- 本项目可借鉴：缺失信息建模、固定计算结果供 LLM 解释；35 个研究任务不等于每肌群恢复已验证。

### A04 — MIT Health-LLM / HealthAlpaca

- 来源：[官方仓库](https://github.com/mitmedialab/Health-LLM)；[论文](https://arxiv.org/abs/2401.06866)；[权重获取问题](https://github.com/mitmedialab/Health-LLM/issues/5)。
- 用途：将生理数值和上下文文本化，研究总体准备度、压力、睡眠等健康预测任务。
- 输入：按研究数据集构建的数值摘要/提示；要适配本产品的字段、缺失模式与预测标签。
- 已核实资产：训练、数据构建及推理代码；本次未核实可下载的官方 HealthAlpaca 权重或托管 API。
- 许可：仓库 [MIT LICENSE](https://github.com/mitmedialab/Health-LLM/blob/main/LICENSE.md)不自动覆盖底座权重、外部数据或第三方模型 API。
- 本项目可借鉴：提示上下文和评价任务；总体准备度标签不是真实肌肉恢复率，也不能替代局部验证。
- 排除混淆：其他团队同名 PH-LLM 公共卫生/社媒项目，不是 Google Personal Health LLM。

### 资产复用决定

当前实现只借鉴研究方法和评价设计；没有下载上述研究模型权重、训练模型或复制其代码/数据进入 App。
“有论文”“有参考代码”“有完整权重”“有商用托管 API”“适配本项目且经验证”是五个独立状态。
后续若复用资产，应固定提交/版本、核对逐文件及数据许可、依赖条件与用途说明，再评估维护成本。
不得把研究案例评分、考试成绩或分类 AUC 写成本产品营养/恢复建议的准确率。
E 已提供受限事实传输与本地报告装配，当前 App 默认 `proxy: nil`，没有真实供应商请求或可用的 AI 报告授权入口。未来接入 DeepSeek 等服务仍需完成隐私、传输、供应商条款和真实回路验收；不能把本地装配写成已上线服务。

### D 人体展示资产的来源与许可

当前可旋转人体使用 Trainote 自行生成的几何资料，不取用上述研究模型或第三方解剖素材。原始数值轮廓生成脚本为 [`BodyMapPreview/generate_asset.py`](../../BodyMapPreview/generate_asset.py)，资产与映射的作者、生成日期、文件 SHA-256、许可及限制记录在 [`PROVENANCE.md`](../../Trainote/Resources/BodyMap/PROVENANCE.md) 和 [`LICENSE.txt`](../../Trainote/Resources/BodyMap/LICENSE.txt)。许可为该原始资产的 MIT；动作目录的文字许可不能用作人体素材许可。74 个封闭体积、左右同组的粗粒度展示只帮助选择肌群，不表示小肌肉或左右两侧有独立生理测量，也不验证准备度分数。

## 版本记录与复核入口

| 对象 | 本次定位的版本或固定证据 | 可变性 |
| --- | --- | --- |
| 科学文献 | N01–N08、R01–R06 的 DOI/原论文；N03 包含 2020 更正 | 论文稳定，后续更正和新证据须复查 |
| PH-LLM README | 文件最近提交 `dcfe32eb4affdb2b8af0ac83e5bc7dd759552d2a`（2025-08-14） | 不是已下载的模型版本 |
| SensorLM README | 文件最近提交 `58c8a04b0bf6e69bc67c3eae76ae9ba5107d9eb5`（2025-10-29） | 不是权重/部署版本 |
| Health-LLM README | 文件最近提交 `ca0958540317d2aea653293dd8f4d271406ac6ea`（2024-08-09） | 接入前重查资产发布状态 |
| SensorFM | 2026-07-09 官方博客、arXiv `2605.22759` | 未固定实现或服务版本 |

提交 SHA 来自本次 GitHub 公共 API 的文件历史查询；不代表仓库整体最近更新日期。
动态网页/README 的“未核实”是截至核查日的状态，不等于承诺未来永远不发布。
部分 PMC/PubMed 页面出现反爬限制；已结合原始摘要、期刊页面及官方全文接口核对，不声称全文均可直连。

## 当前工程证据与仍需完成的验证

- 专业审查：目标人群、能量/营养上下限、公式变量、特殊情境和建议措辞；尚未完成。
- 科学有效性：尚未开展 Trainote 用户试验，也没有本产品分数与生理恢复之间的验证数据。
- 计算验证：已有合成与固定案例覆盖单位、缺失、重复来源、平滑、限幅、体感清空、目标采用/撤销和建议重新核对；入口见上表。先前 F 阶段运行过排除报告组合路径的单元测试及 UI 路径，不能当作当前最终提交的全量通过。算术正确不等于生理预测正确。
- 营养验证：考察可靠记录下的趋势预测误差、调整稳定性和过度调整；先与简单基线比较。
- 准备度验证：目标先限定为可比训练的表现/主观准备度，不把该终点扩大成组织恢复或损伤预测。
- 比较基线：至少比较“距上次训练时间”及简单近期负荷，检验复杂模型是否实际增加信息。
- 数据划分：按人和时间避免训练/评估泄漏；缺失记录与自报误差应单独分析。
- 报告验证：已有引用、候选 ID、数字/缺失值、撤回和缓存的合成测试；真实 B/C/F/E 组合的日桶拒绝已修复并通过定向单元与 UI；最终全量回归及 A 撤回持久化补丁仍待完成。后续还须验证真实供应商只选允许候选、缺数据承认未知，且采用前仍重算规则。
- 设备验证：本轮没有检验任一设备/固件的当前测量准确性；N08 只提供历史方法依据。
- 模型可用性：未运行上述研究模型、未验证权重下载、未购买真实供应商服务；生产适配和许可审查尚未完成。
- 资料复用：没有复制受限全文、图表、训练语料或上述研究项目代码；D 原始人体资产另有明确来源和许可记录，未来引入其他资产仍须逐项登记。
- 用户确认：2026-10-03 已批准主规划和 A/D/B/C/E/F 分工，现有固定模块已进入 F 组合分支；批准及工程阶段成果均不等于科学验证或发布授权。

## 文档验收

- 每个候选规则能追溯到来源 ID，或明确标注为产品参数。
- 研究人群、输入和测量终点不被改写成本产品已验证效果。
- 专用模型不因有代码而被写成可直接调用的生产服务。
- 无未经证实的“真实恢复百分比”“精准消耗”或“专业审查已完成”声明。
- 与产品/技术规格及当前实现交叉检查，规划索引持续指向本文件，并记录实际文档检查结果。
