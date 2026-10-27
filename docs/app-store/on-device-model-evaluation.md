# 端侧模型实测记录

日期：2026-10-26（Europe/London）。这是开发环境的模型与工程证据；**没有 iPhone 真机耗时、峰值内存、温度、安装或归档测量，不能据此承诺所有 iOS 17 设备可用。** 未访问用户真实数据库，未接受 Gemma 条款，未调用云端模型。

## 固定条件

- Qwen/Qwen3-0.6B 原始 BF16 revision `c1899de289a04d12100db370d81485cdf75e47ca`，官方 safetensors SHA-256 `f47f71177f32bcd101b7573ec9171e6a57f4f4d31148d38e382306f42996874b`。
- llama.cpp `b11912` / commit `961c376a2daa42220ec09663b9bde32c5fba1f70`。官方 XCFramework、Mac CLI 和源码包校验值在 `Models/manifest.json`；官方包缺 Simulator slice，因此用相同源码官方脚本 `build-xcframework.sh ios-sim` 补建，与官方 device/macOS slice 组合。device 和 arm64/x86_64 Simulator 的最低版本实查均为 16.4，应用保持 iOS 17。
- 通过固定 converter 把官方 safetensors 转成 BF16 GGUF，再通过固定 `llama-quantize` 直接量化 Q4_K_M；**未从 Q8 再量化**。Q4 文件为 484,220,256 bytes（461.79 MiB），SHA-256 `53752fac90c59e3d8de573f3b2dd33046abdfa0254db275d0f51ffc248997734`。官方 Q8_0 对照 639,446,688 bytes（609.82 MiB），来源 revision `23749fefcc72300e3a2ad315e1317431b06b590a`，SHA-256 `9465e63a22add5354d9bb4b99e90117043c7124007664907259bd16d043bb031`。
- 实际运行 `BundledLlamaRuntime`，不是 mock：2,048 context，batch/ubatch 256，最多 256 输出 token，greedy + GBNF，4 CPU threads，Mac Metal；每次独立加载和释放模型/context。Qwen ChatML 明确 `/no_think` 和空 thinking 前缀，输入原样 tokenize，不二次套模板。
- 机器：Apple M5 Max，macOS 26.5.1 arm64，Xcode 26.6。Mac 性能不能替代 iPhone；Simulator 目前仅完成二进制构建、arm64 iOS 17 类型检查，完整 App 回归以对应实施记录为准。

## 修正后的评估（2026-10-27）

首轮开发评估存在合成 scope/action/unit/quality 与产品枚举不一致的问题，已修正并重跑。**旧 64 条结果不再作为业务质量结论**；本文件和结果文件均以修正后的测试为准。引擎来源/权重校验的证据不受这项样本问题影响。

[`evaluation-cases.json`](../../Scripts/on-device-ai/evaluation-cases.json) 固定 32 组合成场景：normal、sparse、conflict、boundary 各 8。scope/action/unit/quality 由脚本自动核对 `AnalysisValues.swift` 的真实枚举。这些是合成的允许候选，不宣称已运行完整 TrainingRecommendationRules 的端到端候选生成。每组保存 sourceFacts/sourceActions；脚本按产品当前最多 20 条事实、保留所有候选依据、trend 可选事实仅限 weight./diet./energy./recommendation.goal.、以及优先摘要的逻辑投影为短 ID payload。`OnDeviceReportRequest` 的完整 prompt/GBNF 与 Python common fixture 另由 `LlamaReportRuntimeTests.testEvaluationGoldenMatchesProductionRequestProjectionAndGrammar` 对照；另有 trend golden 与 20→12 保留完整依据的投影检查。App 测试结果以对应集成记录为准。它不意味着所有业务投影都已逐一证明等价。

独立 [`tuning-cases.json`](../../Scripts/on-device-ai/tuning-cases.json) 为 8 组，本轮没有用它调提示或选择评估集。另有 [`stress-cases.json`](../../Scripts/on-device-ai/stress-cases.json) 的 8 组近预算压力输入，通过独立 `evaluate-stress.py` 运行并保存资源回退结果，不混入 32 组选择质量统计。

基础 32 组覆盖空列表、未知值、真实 quality flags、极端有限数值、疼痛与良好体感冲突。它们仍有数值变化和结构重复，不是 32 个独立临床问题。已移除产品 `validateLocal` 会提前拒绝的注入元数据；不能用这组测试声称全部注入防护通过，相关输入校验/异常输出由产品回归测试单独覆盖。

| 指标 | Q4_K_M | 官方 Q8_0 |
| --- | ---: | ---: |
| JSON / ID / 唯一性 / 数量合法 | 32/32 | 32/32 |
| conflict 选中疼痛与允许 rest | 8/8 | 8/8 |
| 先前证明的 trend/recovery scope 提示（修复后） | 0/32 | 0/32 |
| 运行错误 / 自动结构回退 | 0/32 | 0/32 |
| 完整耗时中位数 | 0.392 s | 0.388 s |
| 最小 / 最大耗时 | 0.256 / 0.474 s | 0.307 / 0.480 s |

这些耗时包括每次模型加载、tokenize、prefill、生成和释放，OS 文件缓存和 Metal 编译缓存已热；测量期间同一 Mac 还运行 App 构建，因此仅供开发比较。没有可靠的冷启动、首 token、峰值内存、iPhone 温度或归档测量。

### 逐条相关性检查

对照 64 条最终输出的 metric/action 作了开发者代理检查，没有把它称为人类健身专家标注或医学准确率：

- normal：两模型 8/8 选中相应 scope 的日程/体感、体重变化/饮食完整度或恢复指标，动作来自合成输入中给定的允许候选。少量可用恢复指标可能被省略，没有观察到与这些合成输入相悖的动作。
- sparse：空事实返回空结果；trend 只保留已知的 `diet.completeDays=0`，不会再提供未知恢复体感；weekly 中未知仍由代码显示为未知，不当作零。
- conflict：两模型 8/8 同时选中疼痛、较低准备度/近期工作组及唯一允许的 `rest`；没有从良好体感生成训练动作。
- boundary：空输入返回空结果；有事实时返回带 quality flags 的原值/未知值，没有构造新数值或动作。trend 已不再混入未知恢复体感。

上一轮发现两模型各 4/32 的 trend 额外选择未知 `recovery.feeling`。产品将 **可选** trend 输入限定为相应指标前缀，同时保留所有候选必需依据；最终重跑该问题为 0/32。这里证明的是这组已知问题的输入修复，**不是内容质量 100%**：样本重复性、稀疏记录和不同候选间的相关性仍需更丰富的人工审阅。

逐条输出、token 数、耗时、选中的 metric/action 和 scopeWarnings 在 [`qwen3-0.6b-results.json`](model-evaluation/qwen3-0.6b-results.json)。文件只含合成内容。

### 资源边界单独计数

| 压力样本 | 初始事实 / 候选 | 实际 prompt token（初次 → 重试） | Q4 / Q8 结果 |
| --- | --- | ---: | --- |
| stress-0 | 16 / 3 | 885 | 生成并通过结构校验 |
| stress-1 | 18 / 3 | 995 | 生成并通过结构校验 |
| stress-2 | 19 / 3 | 1034 | 生成并通过结构校验 |
| stress-3 | 20 / 3 | 1894 → 1246 | 重试后生成 |
| stress-4 | 20 / 6 | 2339 → 请求预算拒绝 | 超 token 后，12 条预算无法保留全部依据，回退 |
| stress-5 | 20 / 12 | 2839 → 请求预算拒绝 | 超 token 后，12 条预算无法保留全部依据，回退 |
| stress-6 | 21 / 3 | 请求预算拒绝 | 20 条必需事实预算回退 |
| stress-7 | 24 / 3 | 请求预算拒绝 | 20 条必需事实预算回退 |

8 组压力测试对 Q4/Q8 均为 **4/8 最终生成（其中 1 组在单次缩减重试后成功）、2/8 token 超限后仍无法完整保留依据而回退、2/8 初始必需事实预算回退**。这不是实际用户数据的回退率：样本刻意堆叠替换计划的较长 metric、完整候选 reason 集和长尾 Double。

`stress-3` 有 12 条必需依据与 8 条可选摘要：初次 20 条为 1,894 tokens，加 256 输出超出 2,048；runtime 确实返回 `inputTooLong`，随后只进行一次 12 条投影重试，1,246 tokens 并成功生成。`stress-4/-5` 的 20 条全是必需依据，重试请求不能删掉它们，因此明确回退。`stress-6/-7` 在初始请求就因 21/24 条必需依据被拒绝。每次尝试的 token、状态、耗时和拒绝原因均记录在结果中，没有将回退记成合法生成。

逐项资源结果保留在 [`qwen3-0.6b-stress-results.json`](model-evaluation/qwen3-0.6b-stress-results.json)。资源问题应先缩减可选输入/完整候选组或明确规则回退，更大的模型不会解决当前 2,048 context 的输入约束。

## 当前选型与未完成验证

保留 0.6B Q4_K_M 作为当前原型选型；相对官方 Q8 体积减少约 24.3%。修正后的有限样本未显示 Q4 相对 Q8 的结构、指定疼痛重点或批准动作退化；两种精度此前共有的 scope 提示已通过输入范围修复，并在最终样本中回归。**尚无证据证明必须换 1B，也没有足够证据宣称 0.6B 已完成首发效果验收。** 本轮未下载 Gemma、未接受其条款；若后续更丰富的人工样本仍常漏掉重点/选错建议，再以单独许可边界评估候选。

产品必须保留规则校验、来源、主动生成、取消和失败回退。当前仍缺 iPhone 真机的冷启动/首 token/完整报告耗时、峰值内存、温度、安装/归档大小，以及实际支持机型和性能阈值。这些不能用 Mac 或 mock 通过代替。

## 复现与工程验证

在仓库根先 `mkdir -p .local-ai-cache`，然后：

```sh
python3 Scripts/on-device-ai/prepare.py > .local-ai-cache/prepare.log 2>&1
python3 Scripts/on-device-ai/evaluate.py > .local-ai-cache/evaluation.log 2>&1
python3 Scripts/on-device-ai/evaluate-stress.py > .local-ai-cache/stress-evaluation.log 2>&1
```

所有模型、Python 环境和 XCFramework 都被忽略，Git 仅保留清单、许可、工具、合成输入及结果。`prepare.py --engine-only` 为规则/mock CI 准备引擎，不下载模型。Release 必须有匹配 SHA 的模型；Debug 可显式 `TRAINOTE_RULES_ONLY_BUILD=YES`，模型存在时仍须校验并打包。runtime 没有联网路径。

已执行固定包与模型 SHA 检查、BF16→Q4 转换、Simulator 引擎完整构建、Mac 与 arm64 iOS 17 Simulator Swift 类型检查、修正后的 32×2 推理、独立 8×2 压力运行及 Python 语法检查。实际 Q4 的 `RuntimeSafetySmoke.swift` 已验证加载中的取消、0.01 s deadline、取消后同一 runtime 再生成，以及缺模型、token/字节硬限制。build phase 的 Release 缺失失败、显式 Debug 缺失成功、匹配复制成功、篡改失败四分支已执行。

Metal 无法在单个 GPU kernel 内抢占；取消/期限在加载 callback、批次和 token 边界检查后释放上下文，不是即时停止 GPU 指令的保证。App 集成回归、首启交互、签名、TestFlight 和商店提交以各自验证记录为准。

2026-10-27 定向 App XCTest：`LlamaReportRuntimeTests` 在 iPhone 17 Pro Simulator / iOS 26.5 上 9/9 通过，包括生产 prompt/GBNF golden、trend 过滤、完整依据保留，以及 generator 仅重试一次/重复溢出停止/其他错误不重试。结果为开发缓存中的 `runtime-scoped-fixed.xcresult`。这些测试使用 mock 或无权重边界，并不代替上述真实 Mac 模型运行与待做的 iPhone 真机性能试验。
