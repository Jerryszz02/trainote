# 中英 App Store 截图原图

2026-10-27。候选构建 1.1 (2)，iOS 26.5 Simulator，默认字号、浅色模式。每个尺寸各含简体中文和 English (U.S.) 七张，共 28 张原始 PNG。数据来自专用内存数据库中的合成记录；顶部明确显示“示例数据 / Sample data”。没有使用手机或个人 Health 数据。

| 顺序 | 页面 | medium 中文 | medium English | large 中文 | large English |
| --- | --- | --- | --- | --- | --- |
| 01 | 今日 | [查看](medium/zh-Hans/01-today.png) | [View](medium/en-US/01-today.png) | [查看](large/zh-Hans/01-today.png) | [View](large/en-US/01-today.png) |
| 02 | 进行中训练 | [查看](medium/zh-Hans/02-active-workout.png) | [View](medium/en-US/02-active-workout.png) | [查看](large/zh-Hans/02-active-workout.png) | [View](large/en-US/02-active-workout.png) |
| 03 | 动作详情 | [查看](medium/zh-Hans/03-exercise-details.png) | [View](medium/en-US/03-exercise-details.png) | [查看](large/zh-Hans/03-exercise-details.png) | [View](large/en-US/03-exercise-details.png) |
| 04 | 饮食记录 | [查看](medium/zh-Hans/04-nutrition.png) | [View](medium/en-US/04-nutrition.png) | [查看](large/zh-Hans/04-nutrition.png) | [View](large/en-US/04-nutrition.png) |
| 05 | 每周回顾 | [查看](medium/zh-Hans/05-weekly-review.png) | [View](medium/en-US/05-weekly-review.png) | [查看](large/zh-Hans/05-weekly-review.png) | [View](large/en-US/05-weekly-review.png) |
| 06 | 本机 AI 报告 | [查看](medium/zh-Hans/06-on-device-ai.png) | [View](medium/en-US/06-on-device-ai.png) | [查看](large/zh-Hans/06-on-device-ai.png) | [View](large/en-US/06-on-device-ai.png) |
| 07 | 首次使用须知 | [查看](medium/zh-Hans/07-first-use-notice.png) | [View](medium/en-US/07-first-use-notice.png) | [查看](large/zh-Hans/07-first-use-notice.png) | [View](large/en-US/07-first-use-notice.png) |

medium 为 iPhone 17 Pro 的原生 1206 × 2622；large 为 iPhone 17 Pro Max 的原生 1320 × 2868。图片未经拉伸、拼接、内容替换或绘图处理，无 alpha 通道；第七张也可单独用于审核辅助。商店最终选图与标题排版仍由发布者确认。

`StoreScreenshotUITests` 通过真实 App 导航采集，AI 页面必须等待随包 Qwen3 runtime 真实生成并出现本机来源标签。所有示例数据、首启测试参数和顶部标注均限 DEBUG + UI testing + 内存数据库路径，不进入 Release。生成时显示“未知”或需要补充选择是该组记录的真实输出，并不伪造更完整的结果。

[medium manifest](medium/manifest.json) 与 [large manifest](large/manifest.json) 记录设备、OS、构建、源文件快照散列、可执行文件散列、模型散列以及每张图的测试名、时间和 SHA-256。截图是在实施提交前采集，因此使用源文件快照散列绑定构建，不能把基线 commit 当成已安装构建。实际采集与复核结果见 [实施记录](../on-device-implementation.md)。

复现时先准备模型、选择专用测试 Simulator，再运行：

```sh
xcodebuild -project Trainote.xcodeproj -scheme Trainote \
  -destination 'platform=iOS Simulator,id=YOUR_TEST_SIMULATOR' \
  -only-testing:TrainoteUITests/StoreScreenshotUITests \
  -resultBundlePath /tmp/TrainoteStore.xcresult CODE_SIGNING_ALLOWED=NO test
xcrun xcresulttool export attachments --path /tmp/TrainoteStore.xcresult \
  --output-path /tmp/TrainoteStoreAttachments
python3 Scripts/verify_store_materials.py --screenshots docs/app-store/screenshots
```

尺寸检查不替代画面验收。这组图不证明真机性能、无障碍全覆盖、审核通过或 App 已发布；正式提交前需要与将上传的构建再次核对。
