import SwiftUI

/// Bundled prose remains readable without an internet connection.
struct HealthHelpView: View {
  enum Topic: String, CaseIterable, Identifiable {
    case quickStart, nutrition, methods, trends, recovery, calibration, health, ai, storage, backup,
      sources, contact
    var id: String { rawValue }
    var title: String {
      switch self {
      case .quickStart: "快速开始与术语"
      case .nutrition: "饮食计算与完整记录"
      case .methods: "分析方法与适用范围"
      case .trends: "趋势与每周营养建议"
      case .recovery: "恢复指数如何计算"
      case .calibration: "个体校准与重置"
      case .health: "数据与 Apple 健康"
      case .ai: "AI 与 DeepSeek"
      case .storage: "存储、撤回与删除"
      case .backup: "备份 v1 / v2"
      case .sources: "来源与许可"
      case .contact: "帮助与联系"
      }
    }
  }
  @Environment(HealthFeatureAccess.self) private var access
  @Environment(ExerciseCatalog.self) private var catalog
  var topic: Topic? = nil
  var requestsAIConsent = false

  // Load bundled license documents once. All text is available without a network request.
  private static let notices: [(String, String)] = [
    ("THIRD_PARTY_NOTICES", "md"), ("ANATOMY-PROVENANCE", "md"),
    ("ANATOMY-LICENSE", "txt"), ("EXERCISE-MEDIA-PROVENANCE", "md"),
    ("EXERCISE-MEDIA-LICENSE", "txt"), ("PROVENANCE", "md"), ("LICENSE", "txt"),
  ].map { name, ext in
    let text = Bundle.main.url(forResource: name, withExtension: ext)
      .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
    return (name, text ?? "许可文件暂时无法读取。")
  }
  var body: some View {
    ScrollViewReader { scroll in
      List {
        Section("目录") {
          ForEach(Topic.allCases) { destination in
            Button(destination.title) { scroll.scrollTo(destination, anchor: .top) }
              .accessibilityIdentifier("help.topic.\(destination.rawValue)")
          }
        }.id("contents")
        Section("快速开始与术语") {
          Text("今日点“开始训练”后选“直接开始”，不需要模板、身体资料或健康权限。已有进行中训练时，点“继续训练”回到原记录。")
          Text("添加动作后填写重量、次数或时长，点“完成本组”记录这一组；“结束训练”结束整场。返回和切换 Tab 会保留进行中训练。")
          Text("RIR 是这一组结束时估计还能完成的次数，可以不填；未填不等于 0。工作组用于分析负荷，热身组不计入。")
        }.id(Topic.quickStart)
        Section("饮食计算与完整记录") {
          Text(
            "按份记录时填写每份营养与份数；按每 100 克记录时填写每 100 克营养与实际克数。修改份量按当前单位营养缩放；修改总量后再改份量，按修正后的密度计算。常用食物保存当前单位营养。"
          )
          Text(NutritionMath.calorieCalculationNote)
          Text("直接记录以外，还可使用最近、常用食物、固定餐或复制一餐。复用会生成独立记录，原历史不变；取消来源选择会回到原草稿。")
          Text("没有填写营养与真实零摄入不同。确认所选日期饮食完整后，编辑记录会使确认失效；趋势统计只计截至昨天的完整日。")
        }.id(Topic.nutrition)
        Section("分析方法与适用范围") {
          Text(
            "趋势与恢复分析使用训练记录、饮食、体重、可选健康趋势及体感。趋势平滑、工作组负荷、RIR 与时间衰减等规则中的窗口、权重和阈值是有版本的工程初值，尚未证明能准确测量个人生理恢复。"
          )
          Text("恢复指数表示模型估计的训练准备度，不是肌肉恢复百分比、损伤概率或医疗诊断。缺少记录显示未知；疼痛和活动受限独立处理，不能被高分抵消。")
          Text(
            "通用营养建议面向健康成年人的日常健身。未成年人、孕哺期、疾病管理和其他特殊营养需求应保留手动目标或使用专业方案。目标采用需要明确选择；旧手动目标不会因升级而自动改变。")
        }.id(Topic.methods)
        Section("趋势与每周营养建议") {
          Text(
            "体重先按分析时区选择每天的代表值，不混合不同来源：优先你指定的读数，其次首选来源的晨间值或中位数。原始记录保留；没有记录的日期不补零，异常值会提示复核。趋势平滑采用 7 天时间常数，速度估计取最近 21 个完整日。"
          )
          Text(
            "每周调整至少需要跨越 14 天的体重记录、8 个有读数的日期和前后两周各 3 天记录；最近 14 天至少 12 天明确确认饮食完整。今天未结束，不计入已完成周的复核。饮食修改会使旧的完整确认失效。"
          )
          Text(
            "饮食摄入按每一天当时的目标比较；历史目标未知或偏差超过 15% 时先复核执行，不据此自动改目标。初始目标和资料更新后的新基线都需要明确采用。之后每 7 天最多调整一次，每次不超过 100 kcal 或当前目标的 5%，下限由当前静息能量估计与本周期初始估计共同约束；手表活动热量不再加回。"
          )
          Text("这些范围、权重与阈值是工程初值。摄入均值仅是已记录的摄入参考，不是实测总消耗。目标采用和撤销都会保留历史；撤销后暂停复核 7 天，再按你原先选择的模式执行。")
        }.id(Topic.trends)
        Section("恢复指数如何计算") {
          Text(
            "仅使用已完成、可映射的工作组；热身组不计入。历史组类型未知时暂按工作组，未填 RIR 使用默认努力程度，并保留缺失标记。主肌群权重 1、次肌群 0.5，同一肌群取最大权重；这些权重不是肌电比例。"
          )
          Text(
            "局部负荷取最近 28 天记录，随时间指数衰减，初始时间常数为 36 小时；恢复指数为 100 × exp(−残余加权负荷 / 6)，显示时取最近的 5 分。显示 80 及以上、50–75、低于 50 分为三档工程阈值，未经生理准确性验证。没有可用记录的肌群保持未知。"
          )
          Text(
            "当前动作表共 1,324 项，其中 38 项完成工程文本映射、1,175 项待核查、111 项不适用。未核查动作、未支持的记录方式或没有逐动作记录的外部力量活动都会留下覆盖缺口；时长不会换算成工作组。"
          )
          Text(
            "睡眠、静息心率和 HRV 单独呈现全身状态，不直接扣减局部肌群分数。个人基线需同一来源、设备、定义和情境的足够记录；未知来源不混合。疼痛和活动受限优先于分数，未回答不能当作无症状。"
          )
        }.id(Topic.recovery)
        Section("个体校准与重置") {
          Text(
            "校准读取最近 90 天，至少需要 6 对拟合记录和随后独立的 4 对验证记录。仅比较相同动作、记录方式、组顺序、重量和已填写 RIR 的表现；还需训练前体感回答，数据缺口会排除不合格的比较。"
          )
          Text(
            "候选参数必须在留出的后续记录上同时优于基础参数和当前参数，至少改善 5% 且超过 1 个平方误差点；最多每 7 天评估一次，每次调整不超过 10%，时间常数限制在 24–72 小时。它不能证明个人预测有效，器械实体、节奏与技术变化目前未被测量。"
          )
          Text("恢复页可重置个体校准，只保存重新积累的起始时间，保留训练和体感历史。计算时重新读取当前数据，编辑或删除记录后不复用旧的拟合结果。")
        }.id(Topic.calibration)
        Section("数据与 Apple 健康") {
          Text(
            "手动记录包括训练、RIR、饮食、目标、身体资料、体重和可选体感。只有主动连接后才请求读取体重、睡眠、静息心率、HRV SDNN、步数、活动能量和训练；不请求写入权限。")
          Text(
            "管理读取权限：打开 iPhone 上的“健康”App，依次轻点“摘要”→右上角头像或姓名首字母→“App”→“Trainote”，调整各项“从‘健康’读取数据”的许可。请按此路径操作。"
          )
          Text(
            "可只共享部分类型。没有样本、读取失败和未连接会分别处理，空数据不表示拒绝权限。导入数据用于本机分析，缓存最多保留 90 天；缓存及读取锚点不进入系统备份或导出的 JSON。"
          )
          Text(
            "同步随前台刷新和系统通知进行，不保证持续实时。系统内撤回读取权限不一定立即被 App 识别；需要清除已导入内容时，请在本 App 设置中使用“断开并删除健康导入数据”。")
        }.id(Topic.health)
        Section("AI 与 DeepSeek") {
          Text("基础报告在本机整理当前趋势、恢复事实和规则建议。查看依据可以核对数值与缺失记录；历史 AI 报告只读，训练采用需要回到当前建议重新确认。")
          Text("AI 同意与健康连接独立。启用后，必要的训练、饮食、体重和健康趋势汇总会通过代理交由 DeepSeek 处理。AI 不能修改目标或训练历史。")
          if requestsAIConsent {
            if access.reports.isConfigured {
              Text("关闭后停止后续发送与重试；已发送的数据不会因取消请求而自动从第三方删除。")
            } else {
              Text(access.reports.configurationMessage).accessibilityIdentifier(
                "health.aiUnavailable")
              Text("当前不会向 DeepSeek 发送记录，也不会预先保存 AI 同意。")
            }
          }
          Text(
            "启用后的报告仅发送必要的事实汇总、规则候选和缺失标记，不发送姓名、联系方式、自由文本备注、精确位置或完整心率序列。每次新报告重新确认健康数据可读，读取失败时不会用旧健康缓存补齐上传。"
          )
          Text("尚未核实供应商 API 的保留、再利用、退出和删除安排，因此这里不承诺第三方零保留或不用于训练。代理不保存正文不等于供应商不保留。")
          if requestsAIConsent && access.reports.isConfigured {
            Button("同意上述处理并启用 AI 报告") { Task { await access.enableAI() } }
              .disabled(access.isBusy || access.aiEnabled)
              .accessibilityIdentifier("health.aiConsent")
          }
        }.id(Topic.ai)
        Section("存储、撤回与删除") {
          Text("手动记录保存在本机，直到你删除。Trainote 不包含广告、分析追踪或新增遥测，不出售健康记录。健康缓存与同意记录独立存储，不随 JSON 备份转移。")
          Text("断开健康连接会停止同步、清除导入缓存和锚点，并删除依赖它们的分析报告，保留手动记录；不会删除 Apple 健康中的原始数据。失败会提示重试。")
          Text(
            "关闭 AI 会取消后续请求与重试，并撤回服务器授权；离线或失败时需要重试。健康连接与本地计算保留。历史 AI 报告可单独删除。已经发出的请求不能保证通过取消就让供应商删除数据。"
          )
        }.id(Topic.storage)
        Section("备份 v1 / v2") {
          Text(
            "当前导出 v2 JSON，可恢复 v1 和 v2，未来未知版本会被拒绝。旧版 App 不保证能读 v2。导出包括手动健康资料、目标历史、训练和饮食记录，不包括健康导入缓存、同步锚点、健康或 AI 同意、设备凭据和派生报告。"
          )
          Text(
            "恢复会检查并跳过已有相同 ID 的记录，不删除当前记录。恢复备份不能恢复授权，仍需重新选择。备份保存在你选择的位置，可能含个人健康信息；系统备份或你保存的副本由你及设备设置管理。"
          )
        }.id(Topic.backup)
        Section("来源与许可") {
          LabeledContent(
            "Trainote 版本",
            value: [
              Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion").map { "(\($0))" },
            ].compactMap { $0 }.joined(separator: " "))
          LabeledContent("动作数量", value: "\(catalog.items.count)")
          if let source = catalog.source, let url = URL(string: source.repository) {
            Link("打开数据集仓库", destination: url)
          }
          ForEach(Self.notices, id: \.0) { name, text in
            DisclosureGroup(name) {
              Text(text).font(.footnote).textSelection(.enabled)
            }
            .accessibilityIdentifier("help.license.\(name)")
          }
        }.id(Topic.sources)
        Section("帮助与联系") {
          Text("遇到问题可通过项目问题页反馈。请勿在公开问题中附上真实健康记录、完整备份或凭据。")
          Link(
            "在 GitHub 联系维护者",
            destination: URL(string: "https://github.com/Jerryszz02/trainote/issues")!)
        }.id(Topic.contact)
      }
      .onAppear { if let topic { scroll.scrollTo(topic, anchor: .top) } }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("目录") { scroll.scrollTo("contents", anchor: .top) }
            .accessibilityIdentifier("help.contents")
        }
      }
    }
    .navigationTitle("帮助与说明")
    .navigationBarTitleDisplayMode(.inline)
    .healthAccessError(access)
  }
}
