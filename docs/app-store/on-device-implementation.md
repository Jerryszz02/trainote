# 注册付费会员前的实施与验证

2026-10-27（Europe/London）。基线为计划 PR #20 合并提交 `2970459`；实施分支 `agent/trainote-local-ai`。本记录区分产品代码、本地测试、公开页面和仍需设备/账号的工作。App 尚未提交或公开分发。

## 已实现的行为

- 内置 Qwen3-0.6B Q4_K_M，固定 llama.cpp b11912。模型从官方 BF16 直接转换，权重和二进制不入 Git；准备脚本、来源 revision、SHA-256 和许可入库。App 运行时不下载模型、不配置远端 transport、不发送模型 API 请求。
- 模型仅选择已有事实和代码批准的候选建议 ID，最多各三项。GBNF 与 Swift 校验共同限制结构、数量、ID、文案及身份；中英模板呈现实际数值，模型不创造数字或自动采用建议。
- 输入最多 20 项事实并完整保留候选依据；趋势范围排除不相关恢复事实。实际 token 超限时仅再尝试一次 12 项输入；必要依据无法完整放下则回退规则，不截断依据。
- 普通刷新、进入报告、切换范围及回前台只读规则/匹配缓存。主动生成支持取消，离页/后台、关闭本机 AI、须知撤回、记录/选择变化、健康断开和资源压力使旧结果失效。模型完成/取消后释放上下文与权重。
- 缓存包含模型、量化与提示版本；规则、本机和旧云端来源分开。关闭本机 AI 后当前页面显示规则，历史只能主动打开，只读且可逐条删除。
- 版本化中英须知在业务 Tab 之前显示，确认成功持久化才进入；暂不同意/撤回后保留导出和确认删除。首次须知、可选 Health 授权、本机 AI 偏好与旧云端同意独立，备份不携带确认与偏好。
- 修复停止处理后旧 Health 刷新跨越重新接受继续执行的问题；刷新 epoch 在每个异步读取前后复核。关闭本机 AI 也不能恢复已被记录保存失效的旧输入。

现有 SwiftData 业务结构不迁移，手动记录与目标写入规则沿用原实现。本次只操作专用 Simulator 合成数据，未读取或修改用户手机数据库。

## 模型实际证据

详见 [完整模型评估](on-device-model-evaluation.md) 和 `model-evaluation/` 的逐项输入/输出、token 与耗时记录：

| 检查 | 结果与边界 |
| --- | --- |
| 固定基础场景 | Q4、Q8 各 32/32 结构通过；疼痛与 rest 优先各 8/8；修复后未再出现原先四个趋势/恢复范围问题 |
| 独立压力场景 | 各 8 组中 4 组生成、2 组超 token 后无法保留全部依据而回退、2 组初始必要依据超限而回退 |
| 缩减重试 | 20 facts / 1,894 tokens 拒绝后，12 facts / 1,246 tokens 真实生成成功 |
| Q4 与 Q8 中位耗时 | 0.392 s / 0.388 s，仅 M5 Max Mac 测试，不是 iPhone 性能 |
| 取消与超时 | 原生 runtime 合成冒烟通过取消、0.01 秒超时和随后恢复 |
| 模型选择 | 继续使用 0.6B；本组证据不支持仅因范围/长度问题升级 1B，未接受或下载 Gemma 条款受限模型 |

这些是固定合成样本和有限工程验证，不是健康效果、全场景质量或设备覆盖率结论。测试样本与单独的八组调优样本分开；完整规则→模型→UI 另有 Simulator 真实生成截图证据。

## 构建与本地验证

环境：Xcode 26.6 (17F113)，macOS 26.5.1；专用 iPhone 17 Pro 与 iPhone 17 Pro Max Simulator / iOS 26.5 (23F77)，默认字号。本地结果保存在工作树受忽略的 `.local-ai-cache/`，不把数百 MB 的 xcresult/模型加入 Git。

| 检查 | 当前结果 |
| --- | --- |
| 全部单元 + 首次须知 UI + 中英真实截图流程 | `final-validation.xcresult`：348/348 通过，0 失败/跳过；包含收尾英文修复前的 340 单元与 8 UI 场景 |
| 大屏 UI | `large-ui.xcresult`：8/8 通过；6 个截图场景及本机帮助/离线许可两个实际 UI 流程；默认字号，不是大字号验收 |
| 最终英文修复与完整截图重采 | `store-reviewed.xcresult`：每设备 13 个本地化/训练统计单元 + 6 个截图场景，双设备共 38 次运行全部通过，0 失败/跳过 |
| runtime 专项修复回归 | `runtime-scoped-fixed.xcresult`：9/9；覆盖生产 prompt/grammar golden、范围限制、依据保留和有界重试 |
| 须知、同步与报告定向回归 | 先前 `targeted-tests.xcresult`：17 单元 + 3 UI 通过；最终完整单元已覆盖后续修复 |
| iOS Release 设备归档 | 英文修复后 `Trainote-reviewed-unsigned.xcarchive` 重新归档成功，`CODE_SIGNING_ALLOWED=NO`；最低 iOS 17、iPhone-only、版本 1.1 (2) |
| 实际包内资源 | GGUF SHA-256 与 manifest 相同；Qwen/llama 许可与来源说明逐字节匹配 |
| 构建门禁 | 合成输入验证 Release 缺模型失败、SHA 不符失败、正确复制、Debug 缺模型清除旧资源通过 |

首次全单元曾暴露一个 Health 刷新 epoch 回归，修复后通过；新增 golden/retry 测试一度错误复用非生产合同 fixture，改成正式契约输入后全部通过。未放宽产品校验器。两次本机 Xcode 的 clang 元数据探测阻塞在管道写入，终止本任务的构建进程后重跑完成；不归因于产品测试失败。

截图复核发现并修复英文周报动作名硬编码中文、首页完成组数单复数和协同肌群标签翻译问题；新增语言切换与 PR 指标保持不变的回归。最终全单元数量因此为 341；本地未重复整个集合，新增与受影响用例已在两台 Simulator 通过，完整集合由 PR CI 再次执行。

未压缩 App 文件总量为 **510,204,425 bytes**，未签名 archive 文件总量 **534,272,196 bytes**，其中模型 **484,220,256 bytes**。这不是 App Store 下载大小、实际手机占用或峰值内存。归档没有分发签名，不能直接上传或安装到手机。

复现要点：

```sh
python3 Scripts/on-device-ai/prepare.py
python3 Scripts/localization/build_catalog.py --check
python3 Scripts/verify_store_materials.py
xcodebuild -project Trainote.xcodeproj -scheme Trainote \
  -destination 'platform=iOS Simulator,id=YOUR_TEST_SIMULATOR' \
  -only-testing:TrainoteTests CODE_SIGNING_ALLOWED=NO test
xcodebuild -project Trainote.xcodeproj -scheme Trainote -configuration Release \
  -destination 'generic/platform=iOS' -archivePath /tmp/Trainote-unsigned.xcarchive \
  CODE_SIGNING_ALLOWED=NO archive
```

CI 先执行 `prepare.py --engine-only`，无模型权重，覆盖规则/mock 流程；真实模型截图套件从常规 CI 排除，不能把 CI 成功当成设备模型实测。最新 PR head 的 CI 状态以 GitHub 为准。

## 截图与商店资料

中英名称、副标题、推广、介绍、关键词、审核 Notes、隐私问卷、年龄/医疗声明填写边界与用户联系项已经准备。公开支持邮箱为用户确认的 `shen20060206@163.com`。字段长度、本地链接和许可一致性由 `Scripts/verify_store_materials.py` 检查。

截图来源是 DEBUG 专用、内存数据库中的合成数据，界面明确显示“示例数据 / Sample data”。截图通过实际 App 导航采集；AI 页面等待真实随包 runtime 生成并通过 Swift 校验，不使用 mock 来源标签。中英 × 两尺寸 × 七画面，共 28 张原始 PNG 已采集并逐图目视复核；1206 × 2622 和 1320 × 2868 均无 alpha，未加工图片内容。导航、示例标注、长标题、须知按钮和来源均可读。代理目视检查不代表发布者已确认商店最终选图。

最终图片与 manifest 在 [截图目录](screenshots/README.md)，源码快照 SHA-256 为 `9b8aa6ff86cc1b2504bd91a349f4bbe3ed5669b621ed68cbd64383926fe41dfb`；manifest 另记录实际可执行文件与每张图片散列。采集方法见 [截图计划](screenshot-plan.md)。示例数据种子和首启测试参数不进入 Release 路径。

## 已公开的隐私与支持站点

- [隐私政策](https://jerryszz02.github.io/trainote/privacy/) 与 [帮助支持](https://jerryszz02.github.io/trainote/support/) 均提供中英内容，邮箱和跨页导航已在 Chrome 核对。
- 发布分支 `agent/trainote-public-pages`，提交 [`b7634bf`](https://github.com/Jerryszz02/trainote/commit/b7634bf3564fe0bc304ec6dc8d1c1dd7a67508fc)。该分支只含首页、privacy/index.html、support/index.html 三个静态文件，无规划、审核草稿、模型或应用代码。
- Pages API 返回 `built` 且 HTTPS 强制启用；三个 HTTPS 页面均 HTTP 200，下载内容 SHA-256 与本地源文件逐字节相同。网页公开与 App 上架是两件事，页面仍准确注明对应候选版本。
- 后续维护先执行 `package_public_pages.py` 生成新的白名单目录，再以该专用发布分支现有 head 为父提交更新三文件并推送；不要将整个 docs 目录配置为网站，不要清理这个仍承担发布的分支。

## 仍需要设备或用户资料的工作

1. 配对 iPhone 当前不可连接，尚未验证真实手机的安装、离线生成、冷启动、峰值内存、温度、持续使用与 Health 权限。已询问用户是否现在连接；Simulator 与 Mac 不能替代这些结果。
2. 版权主体、App Review 私人联系人姓名/电话和开发者身份由用户按真实资料填写；不根据邮箱或 Git 身份猜测。
3. 付费会员注册/身份核验/付款、正式 Team 与 App Store Connect 配置、签名上传、TestFlight 和审核提交留到后续。无新增付费云服务或供应商账号。
4. 正式首发前按将上传的构建复核截图、披露、可用机型、大字号/VoiceOver、真实数据升级与健康建议适用性；本轮工程测试不等于公开发布验收。
