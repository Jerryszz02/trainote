# 真实 AI 报告接通计划

状态：**开发签名访问规则已实现并通过本地验证，尚未合并/部署；完整 AI 接通仍为计划中**。核查日期：2026-10-10（Europe/London）。

来源：先按用户要求编写接通计划，随后用户明确要求实现“允许开发版也能调用 AI 服务”的校验规则。本轮仅实施该认证策略与对应 App entitlement、测试和说明；不配置凭据、不部署、不调用真实模型、不上传健康记录、不发布 App。基线为本次 fetch 后的 `origin/main` / canonical `main`：`170ad07bf7c5f4113c81a1ea213f12d1dd5544b4`。

本轮设计：增加服务端 `APPLE_ALLOW_DEVELOPMENT_BUILDS`，仅精确 `true` 开启，未配置或 `false` 保留现有 TestFlight/App Store 策略，其他值拒绝启动。开启时额外接受 Apple 签名证明中的 development 类别 3；attestation 与每次 assertion 均执行同一规则。App 明确配置 production App Attest，服务器继续只接收 production AAGUID/receipt，保留 Apple 信任根、App ID、精确构建号、nonce、请求签名和防重放校验。报告保持重点事实/建议加固定文案；不增加匿名访问或跳过认证的路径。

验收：用带真实密码学签名的本地合成证明复现默认拒绝开发类别，再验证显式开启后 attestation/assertion 通过；关闭开关后旧开发 key 的新 assertion 仍被拒绝。默认分发路径、非法类别/版本、伪造签名、错误身份、sandbox 环境和重放回归必须保持通过。真机签名及 Apple 服务实证另列，不能以合成测试代替。

## 1. 目标与推荐范围

先让用户自己的 iPhone 跑通完整链路：明确同意 → 手动生成 → 读取当前允许的数据 → HTTPS 代理认证 → DeepSeek → 双端校验 → 展示真实 AI 报告 → 保存只读历史。失败时显示基础报告及原因，关闭 AI 后停止后续发送。

第一版沿用现有计算与报告契约：数学规则计算趋势和恢复，AI 从已有事实和规则允许的建议中挑选重点，服务端用固定中文模板呈现，最多三项观察和三项建议。**接通并不等于新增长篇自由分析或聊天能力。** 若目标是自然语言教练式报告，应另行设计有证据引用的文本契约和验收，不在本计划中顺带扩展。

用户已选择允许开发直装版本访问，并确认保留重点事实/建议加固定文案。先做个人真机私测：开发签名使用 production App Attest，由服务端显式允许 category 3。TestFlight 仍可沿用默认策略，不是本轮前置要求。公开发布、多用户运营、订阅收费、扩充算法和自由文本报告不属于第一阶段目标。

## 2. 基线代码核查与实际缺口（实施前 `170ad07`）

| 环节 | 本次确认的事实 | 接通前需要完成 |
| --- | --- | --- |
| App 装配 | `HealthReportIntegration` 写死 `proxy: nil`；`AIReportAssembly` 已具备真实 transport 的构造逻辑 | 增加受控的构建配置并注入 HTTPS 地址，缺配置继续本地模式 |
| 可用状态 | `isRemoteAvailable` 只判断 transport 非空；`activateConsent` 只处理待撤回 | 区分已配置、已同意、认证失败、服务不可用和已生成；不能把“已启用”当作连通证明 |
| 请求触发 | `HealthReportsView` 的 `.task(id: type)`、前台切换和手动刷新都调用同一 `refresh` | 分开本地刷新与用户主动远程生成；避免接通后打开页面/切换类型/回前台自动发送 |
| 设备认证 | 客户端已有 App Attest 和设备 Keychain；entitlements 只有 HealthKit 项 | 核对签名、App ID prefix、Bundle ID、构建号、App Attest 环境和真机支持 |
| 分发限制 | 服务端要求 production AAGUID，且 `checkExtensions` 仅允许分发类别 2/4，即 TestFlight/App Store | 开发签名直装不满足当前策略；不能仅设置 production entitlement 就认为可用 |
| 模型 | 客户端与服务端均锁定 `deepseek-flash`；代理已有 JSON 选择、输入裁剪和输出验证 | 真实合成数据调用，验证模型参数、空响应、截断、耗时和实际用量 |
| 服务进程 | Node 服务监听 loopback，文件持久化、单进程锁，双启用开关默认关闭 | 确定主机、TLS、持久卷、进程管理、反向代理和预算；无部署实证 |
| 运维 | 已有配额、撤回、停用文件和本地降级 | 部署后验证重启、崩溃锁恢复、配额持久化、回滚和代理日志配置 |
| 报告 UI | 多处固定“尚未开放”；请求失败信息尚需与服务错误贯通 | 状态文案、加载提示、失败原因、历史与独立同意流程联调 |

代码依据：[App 装配](../../Trainote/Features/Onboarding/HealthReportIntegration.swift)、[报告页](../../Trainote/Features/Onboarding/HealthReportsView.swift)、[授权流程](../../Trainote/Features/Onboarding/HealthFeatureAccess.swift)、[客户端装配](../../Trainote/Services/AIReports/AIReportAssembly.swift)、[客户端传输](../../Trainote/Services/AIReports/ProxyReportTransport.swift)、[认证验证器](../../Server/src/app-attest.ts)、[服务入口](../../Server/src/main.ts)、[模型适配](../../Server/src/provider.ts)、[entitlements](../../Trainote/Trainote.entitlements)。

基线核查没有读取账户密钥或复验真机安装状态。本轮实现后的验证见文末；合成验证不证明真实服务或真机链路可用。

## 3. 分阶段实施

### P0：确认使用路径，优先排除设备认证阻塞

1. 开发直装路径已获确认；扩大到其他测试者仍需确定使用范围。
2. 核对实际 Apple 账号、签名能力、App ID prefix（不能直接假定等于 Team ID）、Bundle ID、构建号与手机系统版本。生成的工程与 `project.yml` 保持一致。
3. 验证开发签名 + production App Attest + 服务端显式开关。先使用不含健康事实的认证流程完成 challenge、attestation、assertion、session，并验证错误构建号、重放和错误签名被拒绝。
4. 本轮采用单一 production App Attest 环境，不引入 sandbox 兼容或鉴权绕过。账号是否支持所需 capability 以实际签名配置为准；首次开通使用明确指定的私测代理与独立状态目录。部署开关和客户端 entitlement 必须匹配。
5. 真机核对当前验证器要求的 signed category / bundle-version 扩展与 receipt 格式。对缺少扩展的系统保留本地报告，不能为通过测试直接删除校验；如需调整兼容策略，先记录证据与决策。

**验收**：目标分发方式下的真实手机完成认证往返，记录构建号、系统、服务提交和结果；账号、签名或证明格式不满足时明确阻塞，不能宣布“只差 API Key”。认证需要的私测服务须先按 P2 准备，报告开关保持关闭。

### P1：确认 DeepSeek 与数据处理，合成数据验证

1. 核对当前模型、JSON 与非思考模式参数。客户端和服务端模型/提示版本必须一致，变更时更新共同契约与回归。
2. 确认可用 DeepSeek 账号、余额与试验预算；密钥通过服务端环境变量或 secret store 注入，不写入 App、Git、聊天或日志。
3. 先做只使用合成 fixture 的真实 provider 调用，不需要先上传个人数据，也不需要绕过公开代理认证。提供受控、人工触发的验证入口，生产 HTTP 服务仍只接受正常认证。
4. 至少覆盖正常、记录稀少、缺失健康数据、无可选动作、接近输入上限五类合成样本；逐项验证真实返回可以通过现有解析与事实引用检查。故障注入覆盖空 JSON、截断、未知 ID、超时、限流及供应商错误。
5. 记录通过/失败数、输入输出 token、耗时和测量区间；小样本不推导线上成功率。当前适配器没有用量统计输出，需要为合成验证添加最小结果摘要，不能记录真实健康内容。
6. 核查适用 API 条款中的处理主体、地区、保留/删除及训练使用规则，形成具体版本的 App 说明；未确认的项目写待确认，不能默认“零保留”。同步本地、服务端和测试中的 consent version。

**验收**：真实合成调用可以生成符合现有契约的报告；成本/耗时有实际测量，说明文字与实际处理一致。正式健康数据请求仍需用户在 App 中独立同意。

### P2：准备小规模持久化代理

1. 推荐沿用当前 Node 单进程和持久化目录，使用支持常驻进程与持久卷的主机。优先评估用户已有主机；不在此阶段默认采购云资源或迁移数据库。无持久磁盘的函数实例不能直接承载当前文件状态实现。
2. 配置域名与 HTTPS、loopback 反向代理、secret 注入、权限和进程停止/重启策略。部署包包含编译输出、运行依赖和 Apple 公共证书文件。
3. 配置 `APPLE_APP_ID`、`APPLE_BUNDLE_VERSIONS`、`REPORT_STATE_DIR`、`DEEPSEEK_API_KEY`；初始保持 `REPORTS_ENABLED` 与 `AI_DISCLOSURE_CONFIRMED` 关闭。在独立验证环境满足条件后才允许合成报告。
4. 验证单实例锁、磁盘故障、重启清除服务端授权但保留配额/计数器的行为。恢复备份不能回滚认证计数器或复活撤回状态，具体恢复方法在部署 runbook 中确定；崩溃锁仅在确认进程已退出后处理。
5. 保留每设备密钥每天五次、单设备一次并发的现有默认值。该配额按 key 计数，不能视为严格的“每人五次”或全局账单上限；上线前补齐与批准预算一致的全局限制/供应商限制及停用方法。
6. 检查反向代理共享 loopback 地址导致全局每分钟 60 请求的效果；边缘限流不信任外部随意提供的转发头。一次报告包含多个认证请求，容量测试必须按完整链路计数。
7. 禁止请求/响应体及 Authorization 日志。最小运维指标仅含状态码、耗时、错误类别和调用计数；新建外部遥测仍需单独授权，不默认接入第三方监控。

**验收**：TLS 与 `/healthz` 正常、未授权请求被拒绝、重启状态正确、可停用新请求且撤回接口仍可工作。`/healthz` 成功只证明服务进程健康，不证明 DeepSeek 可用。

### P3：接入 App，完善实际用户流程

1. 在 App 装配层注入经过检查的 HTTPS 配置，保持环境明确；默认未配置版本继续本地模式，App 内不携带供应商密钥。
2. 报告页展示“生成 AI 报告”或“重新生成”的主动入口。页面进入、类型切换、回前台只更新本地事实/缓存；授权本身不生成报告。撤回重试可以在前台进行，但不得夹带报告数据。
3. 将服务端失败映射成用户能理解的状态：未开通、未同意、设备不支持/认证失败、额度用完、服务暂不可用；显示“已改用基础报告”，保留已有本地记录和分析。
4. 更新 AI 同意页、设置、帮助及隐私说明中的固定“尚未开放”；按配置和授权状态呈现。区分“允许 AI 处理”与“这次真实生成成功”。
5. 保留显式同意、关闭与待撤回、历史只读和独立删除；新开通不得预先保存同意。切换记录/训练模板/授权时使在途结果失效，防止旧报告回填。
6. 连通后仍复用当前规则事实和建议验证；不允许模型直接修改营养目标、训练历史或恢复分数。

**验收**：无同意零报告发送；进入页面/切换类型/回前台零新增模型调用；手动操作触发真实报告；失败显示本地结果及原因；成功报告可查看依据与历史。

### P4：真机闭环、有限开通与回滚

1. 在目标真机和已批准的环境先用合成数据验证四类报告（今日、趋势、恢复、本周），再由用户明确同意使用自己的当前记录。成功结果必须来自真实 provider 并通过 App 校验，不能把本地降级或旧缓存截图当作成功。
2. 测试弱网、断网、超时、额度耗尽、服务禁用、App 退后台、记录变化和服务重启；无自动重复付费请求，失败远程内容不进入历史。
3. 测试生成中关闭 AI、离线撤回与重启恢复、断开健康后的派生报告清除、独立删除历史、未知值保留未知。
4. 保留最小验收证据：代码提交、签名构建/系统、部署版本、合成验证统计、用户主动操作与成功显示。不得记录密钥、认证证明或真实健康正文。
5. 首批仅对获准测试用户开放。停用时使用现有 `DISABLED` 开关阻止新请求并取消在途任务，保留撤回服务；先保全技术状态，再回滚到已验证服务版本。客户端仍可本地使用。

**最终验收**：目标 iPhone 在独立同意后，经真实认证和真实 DeepSeek 生成可核对事实的报告；费用有边界；断网/停用可降级；撤回闭环有效。公开发布仍是独立步骤。

## 4. 验证、交付与依赖顺序

推荐顺序：**P0 路径确认 → P1 合成验证与 P2 私测环境 → P0 真机认证验收 → P3 集成 → P4 有限开通**。认证验证与纯 provider 合成验证分别留证，两者通过不自动等于完整手机链路通过。

实现时优先更新现有 `AIReportTests`、`AIReportTransportTests`、`AIReportRealContractTests`、`AIReportTrendBoundaryTests`、`HealthReportIntegrationTests`、`HealthFeatureAccessTests` 与报告 UI 测试。重点新增配置注入、自动页面事件零远程发送、真实失败状态及撤回回归；Node 使用现有 `Server/test`。

已存在的服务端检查命令为 `npm test` 与 `npm run demo`（在 `Server/` 运行并使用其固定 Node 版本）。demo 是离线假响应，不能充当真实调用证据。iOS 定向测试完成后运行对应 PR head 的必要 CI；最低 iOS 17 和目标真机的 App Attest 兼容性单独验收。不将本次文档检查写成产品测试通过。

建议拆成三个实现交付：认证/部署准备、App 配置与用户流程、真实验证与开通记录。每批按仓库规则独立分支、检查、提交和 ready PR；开通/发布前呈现具体配置和验收结果，由用户确认相应动作。本轮仅获授权实施开发版准入规则；该 PR 的合并不代表部署、真实数据上传或发布授权。

现有 API 与运维细节继续以 [Server README](../../Server/README.md)、[认证说明](../../Server/APP_ATTEST.md) 和 [客户端交接](../../Trainote/Services/AIReports/README.md) 为入口。后续实施时修正其中历史“待集成”状态，并同步发布清单；本次不复制整套 API 或增加重复 runbook。

## 5. 执行前需要确定的事项

| 事项 | 本计划建议 | 待确认信息 |
| --- | --- | --- |
| 使用范围 | 先本人 iPhone 私测 | 是否需要其他测试者 |
| 安装方式 | 已确认允许开发直装，使用 production App Attest | 实际 Apple 账号/capability、签名和真机证明格式 |
| 服务位置 | 优先现有可持久化主机 | 主机、域名、运行环境及是否允许部署 |
| 费用 | 先限制合成试验，再设置日/月上限 | 已有 DeepSeek 账号、试验额度及每月总预算；本次不要求提供密钥 |
| 报告形态 | 已确认重点事实/建议加固定文案 | 无；长篇自由分析不在本轮范围 |

成本由主机/域名、实际 token 用量和所选分发路径的账号成本组成；尚无真实测量或资源选择，不给出虚构月费和固定交付日期。工期主要受账号/分发准备、真机证明格式、托管资源与条款核查影响。

## 6. 外部资料与本次验证边界

2026-10-10 查询官方资料：

- [Apple App Attest Environment](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment)：开发可选择 production 环境；环境选择不等于改变代码分发类别。默认仅接受 TestFlight/App Store 是本项目策略；本轮已增加开发签名显式准入开关。
- [Apple Preparing to use App Attest](https://developer.apple.com/documentation/devicecheck/preparing-to-use-the-app-attest-service)：开发/生产密钥隔离，真实设备认证需与对应环境匹配。
- [DeepSeek 模型与价格](https://api-docs.deepseek.com/quick_start/pricing/)：本次官方检索结果仍列出 `deepseek-flash`；实施前再次核对模型和计费。
- [DeepSeek JSON Output](https://api-docs.deepseek.com/guides/json_mode/)：JSON 输出仍须处理空内容和截断，不能跳过本地 schema/引用检查。

本轮先用新增的开发 attestation/assertion 用例复现失败，再实现显式开关。Node 22.23.1 下 `npm test` 通过 71 项（0 失败/跳过），离线 `npm run demo` 通过；Debug generic iOS 的 `CODE_SIGNING_ALLOWED=NO` 构建通过，entitlements 通过 `plutil -lint`。测试日志 `/tmp/trainote-dev-attest-tests.log`，构建日志 `/tmp/trainote-dev-attest-build.log`。文档检查为 `git diff --check` 和 planning 索引/本地链接审计。未执行签名构建、真机 Apple 认证、真实模型请求或部署探针；当前 App 仍以 `proxy: nil` 运行。PR 当前 head 的 CI 结果另行核实，不能把本地构建当作实际签名/接通成功。
