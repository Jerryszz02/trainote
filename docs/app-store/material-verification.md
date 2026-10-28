# 商店材料检查

官方资料核对：2026-10-26；实施与公开页面状态更新：2026-10-27。材料仍是 App 提交候选，未填写 App Store Connect、未提交审核；字数通过不表示功能、健康效果、名称可用性或审核已通过。

## 字段与自动检查

- 名称和副标题各不超过 30 个字符；推广文本不超过 170 个字符；描述不超过 4,000 个字符。
- 关键词采用更严格的 100 UTF-8 字节预算（中文按字节计算），使用逗号分隔，不包含其他 App 名称。
- 审核 Notes 不超过 4,000 UTF-8 字节。审核联系人姓名、邮箱、国际格式电话号码留给用户，不放入仓库。

运行 `python3 Scripts/verify_store_materials.py` 检查中英字段及页面本地链接。可加 `--screenshots /绝对路径` 检查按 `zh-Hans/`、`en-US/` 分组的 PNG 尺寸和透明通道；也可传入含 medium/large 子目录的根目录；这是素材结构检查，不替代逐图核对画面、隐私和功能。

## 公开材料与剩余边界

- 公开页面已由主代理发布并验收：专用分支 `agent/trainote-public-pages` / 提交 `b7634bf3564fe0bc304ec6dc8d1c1dd7a67508fc`，仅三个 HTML 文件。Pages 状态 `built`、HTTPS 强制；首页、privacy、support 均 HTTP 200 且 SHA-256 与源文件相同，Chrome 中英和跨页导航通过。App 本身仍未公开分发。
- Apple 的 Support URL 说明要求实际联系信息（例如合法地址、邮箱、电话号码，视当地要求）；用户已确认公开支持邮箱 `shen20060206@163.com`，页面提供 mailto 链接和 GitHub Issues。App Review 私有联系人姓名与电话仍由用户填写，不编造。
- 真机性能、无网络推理、健康权限与专业适用性审查仍需独立验收。预览截图和 mock 测试不替代这些条件。
- 年龄分级、Regulated Medical Device Status、版权权利人等依照最终功能和用户主体事实填写；不预判评级、不把免责声明当成医学有效性证据。

## 官方来源

- [App information：名称和副标题](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information)
- [Platform version information：推广、描述、关键词、支持和审核字段](https://developer.apple.com/help/app-store-connect/reference/app-information/platform-version-information)
- [Screenshot specifications：必需组、尺寸、数量和格式](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)
- [App privacy details：仅在设备处理不属于标签中的收集](https://developer.apple.com/app-store/app-privacy-details/)
- [Manage app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)

## 公开站点打包与已发布状态

运行 `python3 Scripts/package_public_pages.py --output /tmp/trainote-public-pages-candidate-1`。输出必须是不存在的新目录；脚本拒绝覆盖，不修改 Pages 设置，不调用网络。产物只含 `index.html`、`privacy/index.html`、`support/index.html`，不会将 planning、审核材料或整个 docs 目录公开。输出的 SHA-256 可用于后续核对部署内容。

本地预览可运行 `python3 -m http.server 8765 --directory /tmp/trainote-public-pages-candidate-1`，检查中英锚点、mailto 和跨页面导航。本轮已仅发布该三文件产物，未公开整个 docs 目录。后续更新仍沿专用发布分支进行，并核对部署后 URL 与内容哈希；打包脚本本身不部署或更改 Pages 设置。

## 本轮代码事实核对（2026-10-26）

已读取 `FirstUseNoticeStore`/`FirstUseNoticeView`、`TrainoteApp`、`HealthReportIntegration`/`HealthReportsView`、`SettingsView` 和 `LlamaReportRuntime`：

- 须知确认保存 `local-processing-v1` 与时间；AI 偏好在独立文件。接受不改 Health/云端同意，撤回标记持久化；限制页保留导出、删除手动记录及清除健康导入。
- `TrainoteApp` 在须知前挂载限制页，通过处理门控阻止恢复同步和分析；设置可独立关闭 AI、查看/撤回须知。
- 报告自动入口走 `refresh(generate: false)`；按钮走 `generateOnDevice`。离页、后台、记录/模板变化、内存警告和严重温度状态取消；关闭 AI 退回规则，历史保留为主动查看/删除。装配 `proxy: nil`。
- 本机 runtime 为 actor，按需加载随包 GGUF，Qwen3-0.6B / Q4_K_M / revision `c1899de289a04d12100db370d81485cdf75e47ca`，2,048 上下文、最多 256 输出 token；每次生成后释放上下文与模型。未见 runtime 网络入口。

这是代码核对，不是最终签名包、真实效果、真机性能或网站上线的验收证明。若上述代码后续改动，需要重新核对披露。

## 已核对的构建与测试证据（2026-10-27）

详细证据及复现见 [注册付费会员前的实施与验证](on-device-implementation.md)：

- Release 无签名设备归档 `.local-ai-cache/Trainote-reviewed-unsigned.xcarchive` 成功。App 文件总量 510,204,425 bytes，archive 文件总量 534,272,196 bytes；不是商店下载大小或实际安装占用。
- 模型 484,220,256 bytes，SHA-256 `53752fac90c59e3d8de573f3b2dd33046abdfa0254db275d0f51ffc248997734`。模型、Qwen/llama 许可与来源说明已在包内逐字节核对。
- 完整回归快照 340 单元 + 8 UI 共 348/348 通过，iPhone 17 Pro Max 大屏 Simulator（默认字号）8 UI 通过。真实模型合成和 Simulator 生成证据不代表 iPhone 性能、医学有效性或全部设备覆盖。
- 最终 28 张中英双尺寸截图已重采并由代理逐图目视核对，导航与示例标签无重叠，英文周报/单复数/肌群翻译已修复；受影响的 13 单元 + 6 截图流程在两台设备共 38 次运行全部通过。截图原图与 manifest 见 [截图目录](screenshots/README.md)。真机、VoiceOver/全页面人工验收、最终选图和用户私有审核资料仍按发布清单处理。
