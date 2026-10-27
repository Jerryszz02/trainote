# App 隐私问卷草稿 / App privacy questionnaire

2026-10-26 · 仅本地草稿，不是 App Store Connect 已保存的答案。对最终 Release 包及所有嵌入依赖重新审计后填写。问卷的“收集”与 App 在本机保存记录不同：仅在设备上处理的数据不属于 Apple 隐私标签中的收集。[Apple 定义](https://developer.apple.com/app-store/app-privacy-details/)

| 项目 / Question | 候选答案 / Candidate | 最终包核对条件 |
| --- | --- | --- |
| App 或第三方合作方是否收集数据 / Do you or third-party partners collect data? | 否 / No, we do not collect data from this app | 不向开发者或合作方发送记录、标识、分析或诊断；依赖无遥测；本机模型不联网 |
| 训练、饮食、体重、体感、HealthKit / Health and fitness data | 本机处理，不列为收集 / On-device processing, not collected | 规则和 Qwen3 选择在本机执行；无 cloud transport 装配；不把完整样本或备注发出 |
| 与身份关联 / Linked to user | 无收集，因此不进入分类 / Not applicable if no collection | 不存在账号、设备追踪标识或远端用户档案 |
| 追踪 / Tracking | 否 / No | 无广告网络、跨 App 数据关联或数据经纪商共享 |
| 位置、联系人、购买、搜索/浏览、使用、诊断等 / Other categories | 无收集 / Not collected | 检查全部依赖及最终二进制；不能只依据没有广告来推定 |
| 隐私政策 / Privacy Policy URL | 中英公开页面候选链接见元数据 | 需实际部署并验证，无登录可读 |
| 隐私选择链接 / Privacy Choices URL（可选） | 可使用政策中的删除与控制说明 | 公开页面与设置行为一致 |

## 不混淆的边界

- HealthKit 读取仍需独立系统授权，不能把“不收集”理解为不处理健康数据。首启须知、健康权限、本机 AI 开关分别管理。
- 模型随包交付；运行时没有模型下载、推理服务器、账号、广告或遥测。开发者构建时下载公开模型与引擎不是用户记录发送。
- 系统备份由 Apple 与用户设置管理；App 不提供自己的云同步。主动导出可能保存到用户选择的云盘，文件由该服务处理。不能写成“所有数据永不离开手机”。
- 支持邮箱 `shen20060206@163.com` 和 GitHub Issues 都是用户主动选择的外部反馈渠道；邮件会向邮箱服务和开发者提供发件地址与用户所写内容，Issues 有登录和公开网站处理。不要上传真实健康数据；不是 App 自动上传诊断的通道。该反馈是偶发、可选且非主要功能；提交前按 Apple 可选披露条件逐项核对，不能把支持邮件事实隐去。若将来内嵌反馈、自动附加日志、定期采集或用于广告营销，重新评估问卷。
- “未配置云端代理”不能代替最终包审计。任何未来远端处理都要重新说明接收方、用途、发送内容、保留政策和对应选择。

## 申报前保留的证据

- 最终 commit、构建号、模型 SHA-256、引擎版本和第三方 notice。
- Release 配置的网络入口审计、离线真机主动生成/取消/失败回退，以及 Health 可选行为。
- 确认前无同步/推理，关闭 AI 与撤回须知独立，导出不携带确认/报告/健康缓存。
- App 包内 `PrivacyInfo.xcprivacy` 及依赖清单与真实使用一致。隐私清单和 App Store 问卷是不同材料。

[填写规则与角色权限](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)。如功能、依赖或数据流改变，及时更新答案。
