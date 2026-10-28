# App Store 截图计划与采集

2026-10-27 · 采集规格与复现方法。仅 iPhone；每种语言使用同一套真实 App 画面、明确标注的虚构示例数据，不使用个人数据库或 Health 记录。实际候选截图、构建散列和验收结果见 [截图目录](screenshots/README.md) 与 [实施记录](on-device-implementation.md)，提交前仍应与最终构建核对。

## 当前 Apple 尺寸要求

[官方 Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications) 本次核对要求 iPhone with Dynamic Island **medium display** 至少一张；竖屏接受 `1179 × 2556` 或 `1206 × 2622`。本轮使用专用 iPhone 17 Pro Simulator 的原生 `1206 × 2622`。可额外提供 large 组：`1260 × 2736`、`1290 × 2796` 或 `1320 × 2868`；本轮使用 iPhone 17 Pro Max 的 `1320 × 2868`。提交时以当时 App Store Connect 的实际槽位重新核对。

每设备尺寸 1–10 张 JPEG/JPG/PNG，不能有透明或 alpha 通道。不拉伸旧图代替新尺寸的布局检查；App 当前仅 iPhone，不准备 iPad 组。

## 中英画面清单

| 顺序与文件名 | 实际页面 / 合成记录 | 中文标题候选 | English title candidate |
| --- | --- | --- | --- |
| `01-today` | 今日；示例营养目标、当日训练 | 训练和饮食，一页看清 | Your day, in one place |
| `02-active-workout` | 进行中训练；力量动作与已完成/未完成组 | 每一组都记录清楚 | Keep track of every set |
| `03-exercise-details` | 动作详情；当前语言的分类和动作说明 | 查看动作和训练说明 | Explore exercise details |
| `04-nutrition` | 饮食；示例餐次和营养汇总 | 每一餐，快速记下来 | Log your everyday meals |
| `05-weekly-review` | 每周回顾；合成训练积累与 PR | 看见每一周的积累 | Review your weekly progress |
| `06-on-device-ai` | 报告；真实内置模型生成，来源标签可见 | 主动生成，本机整理 | Generate a report on device |
| `07-first-use-notice` | 首次须知；可选操作与语言切换 | 阅读须知，自主选择 | Read first, then choose |

前五张为基础组。第六张仅在真实模型完成并通过包核对后采用，mock 报告不能作为本机 AI 宣传截图。第七张可作为审核辅助；是否放入商店由最终排版决定。趋势、恢复和需要确认的建议可作为补充，但不得用“恢复百分比”“保证防伤”或减重效果作标题。

## 可执行采集方法

1. 在专用测试 Simulator 安装本次构建。记录 commit、构建号、模型 SHA-256 与安装包来源，使用合成数据；不清空用户现有 Simulator。
2. 在 App 内选择简体中文或 English，浅色模式、默认字号。手动或已有 UI 测试导航到清单页面；确认数据与日期一致，关闭键盘与调试覆盖。
3. 用 `xcrun simctl list devices available` 选定 UUID。每页运行：

```sh
bash Scripts/capture_store_screenshot.sh SIMULATOR_UUID zh-Hans /tmp/trainote-store-captures 01-today
bash Scripts/capture_store_screenshot.sh SIMULATOR_UUID en-US /tmp/trainote-store-captures 01-today
```

脚本只捕获当前 UI，临时统一状态栏后清除 override；不会伪造界面、填充数据、启动模型或证明当前屏幕语言。每张旁边保存采集时间、Simulator 清单、仓库 commit 与 dirty 标记。同名文件拒绝覆盖。仓库 HEAD 不是已安装 App 版本的证明，采集者必须在 manifest 记录实际安装包。

4. 每种语言重复所有画面，若需要 large 组使用单独输出目录。运行：

```sh
python3 Scripts/verify_store_materials.py --screenshots /tmp/trainote-store-captures
```

5. 逐张检查：画面与当前功能一致、无真实隐私或调试信息、示例数据标注清楚、无意外裁切/乱码、来源标签正确、关键控件可读。双语标题可在实际截图外排版，不遮盖控件。原始图与排版图分开保存，不将设计图或 mock 界面冒充真实 App。代理目视检查与发布者最终选图确认分别记录。

最终 manifest 记录每张：语言、尺寸、实际设备/OS、安装构建与源文件快照散列、模型 SHA-256（若显示 AI）、场景步骤、合成数据来源、原始文件 SHA-256、核对方式及日期。提交前采集的构建不能仅用基线 commit 代替源码身份；缺少任一实际验证的内容保留为待完成。
