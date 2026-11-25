# ECHO 项目框架与技术栈方案 v1.0

- 文档状态：提案（已部分实施——见下方「实施进度」），正文保留为评审快照
- 适用范围：ECHO Prototype 0.1 → 0.2 的重构基线
- 编写依据：`main` @ `75d1871` 的实际代码，非规划稿
- 相关文档：`docs/ARCHITECTURE.md`（现状）、`docs/PROJECT_STATUS.md`（进度）、`docs/skill_design_principles_zh-CN.md`（设计原则）

> **实施进度（2026-11-25，`main` @ `aa569bd`）**：
> - **M0 已完成**——测试套件迁入公共基类 `tests/framework/test_case.gd`，新增一键回归 `tests/run_all.*`。
> - **M1 已完成**——敌人属性外置为 `data/enemies/*.tres`（新增 `test_enemy_catalog`，断言 582 → 623）；三关外置为 `data/levels/*.tres`，`level_catalog.gd` 69 → 29 行。
> - **M2 已完成**——936 行控制器拆为门面（230 行）+ 六个协作模块，测试文件零改动，断言数不变。
> - M3（表现层拆分）与 M4（CI）尚未实施。
> 逐项断言对照见 `docs/engineering/BASELINE.md` 的变更记录；拆分后的现行架构见 `docs/ARCHITECTURE.md`。下文「现状盘点」中的行数与断言数为提案编写时（`75d1871`）的快照，保留作为决策依据，请勿当作当前数值。

---

## 一、现状盘点

### 1.1 规模与分布

| 类别 | 数量 | 行数 / 断言数 |
|---|---:|---|
| 脚本（.gd） | 17 | 2,445 行 |
| 场景（.tscn） | 1 | 单节点 |
| 资源（.tres） | **0** | 数据全部在代码里构造 |
| 测试套件 | 15 | 582 条断言 |
| 文档（.md） | 18 | 含本文 |

代码分布高度集中：

| 文件 | 行数 | 占比 |
|---|---:|---:|
| `scripts/battle/battle_controller.gd` | 936 | 38% |
| `scripts/ui/battle_view.gd` | 562 | 23% |
| 其余 15 个文件 | 947 | 39% |

**两个文件占了六成代码。** 这是当前所有结构性问题的源头。

### 1.2 模块职责与调用关系

```
main.tscn (Node2D)
   └─ battle_view.gd ──────────── 绘制 + 输入 + 状态呈现（562 行，全在一处）
         │
         ├─ 读取 ──> level_catalog.gd ──> encounter_definition.gd
         │
         └─ 持有 ──> battle_controller.gd（44 个函数）
                        ├─ grid_rules.gd            网格/路径/视线
                        ├─ ap_budget.gd             AP 账本
                        ├─ combat_math.gd           伤害公式
                        ├─ battle_actor.gd          单位（血量/护盾/能量）
                        ├─ battle_intent.gd         意图快照
                        ├─ battle_status*.gd        单位状态
                        ├─ battle_area_effect*.gd   战场区域
                        ├─ oathkeeper_v2_skill_catalog.gd   当前技能数据
                        ├─ oathkeeper_skill_catalog.gd      v1 遗留技能数据
                        └─ signals: battle_event / battle_finished
```

控制器内部承担了七件互不相干的事：回合流程、敌方意图生成、意图执行、伤害管线、技能执行、召唤调度、结算统计。它同时是状态容器、规则引擎和动作入口。

### 1.3 值得保留的设计

这些是现有代码里做对了的部分，重构时应作为约束而非负担：

1. **权威边界清晰**：UI 不计算任何结果，全部经 `request_*` 回到控制器。`docs/ARCHITECTURE.md` 已明文规定，且代码基本遵守。
2. **意图快照复用**：`battle_intent.gd` 让"预告展示"和"敌方执行"读同一份数据，从机制上排除了预告与结算不一致——这是本项目最核心的可读性保证。
3. **状态与区域分离**：状态挂在单位上，区域效果挂在格子上，两者生命周期不同却共用到期边界机制，模型干净。
4. **数据先于执行**：`skill_definition.gd` 是纯数据 Resource，不含执行逻辑；执行集中在控制器。
5. **测试先行**：582 条断言覆盖到边界条件（区域在角落被裁切、斜角视线被遮挡、反击不递归），密度高于多数原型。
6. **确定性优先**：固定布阵、固定优先级、无隐藏随机，符合 `skill_design_principles_zh-CN.md` 的关卡设计原则。

### 1.4 现存问题清单

按严重度排序，编号供后文引用。

| # | 问题 | 证据 | 影响 |
|---|---|---|---|
| P1 | **控制器是上帝对象** | 936 行 / 44 个函数 / 7 类职责 | 任何改动都碰同一个文件，冲突率高；单测只能整对象测 |
| P2 | **两套技能系统并存** | `oathkeeper_skill_catalog.gd`(v1) 与 `oathkeeper_v2_skill_catalog.gd`(v2) 同时存在 | 读代码的人无法判断哪套生效 |
| P3 | **6 个遗留接口无 UI 调用** | `request_player_attack` / `oathguard_stance` / `echo_counter` / `watchwall` / `judgment_mark` / `oath_severance`，UI 引用数均为 0 | 约 150 行死代码，被 5 个测试文件"养着" |
| P4 | **数据不落地** | 全仓库 0 个 `.tres`；技能用 `_make_skill()` 代码构造，关卡用 `_make_level()` 构造 | 无法在编辑器里可视化编辑，策划改数值要改代码 |
| P5 | **敌人属性硬编码** | `start_encounter` 里 4 层嵌套三元（`2000 if marksman else (2600 if ... else 3200)`） | 新增敌人类型要动控制器核心 |
| P6 | **UI 单体化** | 562 行单文件，`_draw()` 里串行画棋盘/单位/预告/HUD/技能栏/结算 | 无法单独调整某一块；Android 适配无从下手 |
| P7 | **即时模式绘制，无 Control 节点** | 唯一场景只有一个 `Node2D` | 布局全靠手算坐标（48/112/145/235…），改字号就错位；触控热区与视觉不一致风险高 |
| P8 | **数值与样式散落** | `battle_view.gd` 内 68 处颜色字面量、26 处硬编码坐标；控制器内约 37 处数值常量 | 换主题或适配分辨率需全局搜索 |
| P9 | **测试无公共框架** | 15 个文件各自实现 `_initialize/_check/quit` | 重复约 15×25 行；无法一次跑全部并汇总 |
| P10 | **无 CI** | 无 `.github/workflows` | 回归靠人工；项目规则明确禁止未经批准的 Actions，需先取得授权 |
| P11 | **文档无分层** | `docs/` 下 18 篇平铺，设计规格、进度、历史验证混在一起 | 新成员不知道从哪读起 |
| P12 | **中文硬编码在 UI** | `battle_view.gd` 内 175 处中文字面量 | Prototype 阶段可接受；若要多语言需重做 |

---

## 二、项目目标与范围

### 2.1 目标

在 **不扩大 Prototype 0.1 玩法范围** 的前提下，把当前"能跑但结构混乱"的原型，整理成**可持续迭代到 0.2 及以后**的工程底座。核心诉求：

1. 改一个系统时不必碰其他系统的文件。
2. 加一个敌人/技能/关卡时只加数据，不改控制器。
3. 换分辨率或上 Android 时不必重写布局逻辑。
4. 任何人读完 `docs/` 能在半小时内上手。

### 2.2 范围边界

**本次纳入**：代码分层、数据外置、UI 拆分、测试框架化、文档治理。

**明确不纳入**（依据 `docs/PROJECT_STATUS.md` 第五节）：

- 战斗内存档、检查点、恢复
- 章节推进、关卡解锁、局外成长、经济系统
- 回响契约、收藏系统
- 未经确认的新角色、新敌人、新地图
- 多语言、成就、云存档

**待授权后才做**：GitHub Actions CI（项目规则要求单独批准）。

---

## 三、目标分层架构

### 3.1 分层原则

四条硬规则，任何 PR 违反即打回：

1. **依赖单向**：上层可依赖下层，下层不得反向依赖上层。
2. **数据与规则分离**：数值、配置、文本属于数据层；判定逻辑属于规则层。
3. **单一权威**：同一状态只有一个持有者，其他层只读。
4. **表现可丢弃**：删掉整个表现层，规则层与数据层仍能跑通全部测试。

第 4 条是关键——它让 UI 重构不必担心破坏战斗逻辑。

### 3.2 五层模型

```
┌─────────────────────────────────────────────────────────┐
│ L5 平台层  Android 导出 / 输入设备适配 / 分辨率策略        │
│            （当前仅桌面，P4 阶段填充）                     │
├─────────────────────────────────────────────────────────┤
│ L4 表现层  BattleScene → BoardView / HudView /            │
│            SkillBarView / SettlementView / InputRouter   │
│            只读规则层状态，只发意图，不计算结果             │
├─────────────────────────────────────────────────────────┤
│ L3 规则层  BattleFlow（回合/胜负）                        │
│            IntentPlanner（敌方意图生成）                   │
│            IntentResolver（意图执行）                      │
│            DamagePipeline（抗性→区域→护盾→终段）           │
│            SkillExecutor（技能执行）                       │
│            SummonService（猎人通灵）                       │
│            SettlementRecorder（结算统计）                  │
│            BattleController（门面，对外唯一入口）           │
├─────────────────────────────────────────────────────────┤
│ L2 领域模型 Status / AreaEffect / Intent / Actor / Grid    │
│            纯数据结构与自身不变量，不感知回合与 UI          │
├─────────────────────────────────────────────────────────┤
│ L1 数据层  SkillDef / EnemyDef / LevelDef / Balance       │
│            .tres 资源，编辑器可编辑，代码只读               │
└─────────────────────────────────────────────────────────┘
```

### 3.3 目标目录结构

```
.
├── project.godot
├── data/                          # L1 数据层（新增）
│   ├── skills/
│   │   ├── judgment_mark.tres
│   │   ├── oath_shield.tres
│   │   ├── absolute_guard.tres
│   │   ├── oath_vow.tres          # 被动
│   │   └── hunter_summon.tres
│   ├── enemies/
│   │   ├── vanguard.tres
│   │   ├── marksman.tres
│   │   └── area_controller.tres
│   ├── levels/
│   │   ├── lesson_charge.tres
│   │   ├── lesson_lane.tres
│   │   └── lesson_mixed.tres
│   └── balance.tres               # 全局数值：AP、护盾系数、能量上限
│
├── scripts/
│   ├── core/                      # L2 领域模型（从 battle/ 上移）
│   │   ├── grid.gd
│   │   ├── battle_actor.gd
│   │   ├── battle_intent.gd
│   │   ├── battle_status.gd
│   │   ├── battle_status_collection.gd
│   │   ├── battle_area_effect.gd
│   │   └── battle_area_effect_collection.gd
│   │
│   ├── rules/                     # L3 规则层（从控制器拆出）
│   │   ├── battle_controller.gd   # 门面，保留现有 request_* API
│   │   ├── battle_flow.gd
│   │   ├── intent_planner.gd
│   │   ├── intent_resolver.gd
│   │   ├── damage_pipeline.gd
│   │   ├── skill_executor.gd
│   │   ├── summon_service.gd
│   │   ├── settlement_recorder.gd
│   │   ├── ap_budget.gd
│   │   └── combat_math.gd
│   │
│   ├── data/                      # L1 类型定义
│   │   ├── skill_definition.gd
│   │   ├── enemy_definition.gd    # 新增
│   │   ├── level_definition.gd    # 由 encounter_definition 演化
│   │   └── balance.gd             # 新增
│   │
│   └── ui/                        # L4 表现层（拆分为多文件）
│       ├── battle_scene.gd        # 容器与生命周期
│       ├── board_view.gd
│       ├── hud_view.gd
│       ├── skill_bar_view.gd
│       ├── settlement_view.gd
│       ├── input_router.gd
│       └── theme_palette.gd       # 颜色/字号/间距常量
│
├── scenes/
│   └── main/
│       └── main.tscn
│
├── tests/
│   ├── framework/
│   │   └── test_case.gd           # 新增：公共断言与汇总
│   ├── run_all.sh / run_all.bat   # 新增：一次跑全部
│   ├── core/
│   ├── rules/
│   ├── ui/
│   └── data/
│
└── docs/
    ├── README.md                  # 新增：文档索引与阅读顺序
    ├── design/                    # 设计规格（作者维护）
    ├── engineering/               # 架构、状态、验证
    └── archive/                   # 历史记录，不再更新
```

### 3.4 依赖规则

| 层 | 允许依赖 | 禁止依赖 |
|---|---|---|
| L1 数据 | Godot Resource 基础类型 | 任何 scripts/ 下的逻辑 |
| L2 领域模型 | L1 | L3 / L4 / L5 |
| L3 规则 | L1 / L2 | L4 / L5（**不得 import 任何 ui 脚本**） |
| L4 表现 | L1 / L2 / L3 的只读 API | 不得直接改 L2 对象字段 |
| L5 平台 | L4 | — |

可用一条测试守护第 4 条原则：在无头模式下不加载 `scripts/ui/`，跑完全部规则与数据层断言。

**现状核实（2026-11-25）**：15 个套件中 14 个不依赖 UI，唯一例外是 `test_battle_view_skills.gd`——它主动 `instantiate` 主场景来验证 UI 到控制器的调用链，属于**有意的集成测试**。因此"删掉表现层"的实际含义是：删除 UI 后，14 个套件仍须全绿，`test_battle_view_skills` 随之失效并被一并删除或改为桩替身。这条要在 M3 之前明确，否则拆 UI 时会误以为有测试保护。

---

## 四、技术栈

### 4.1 选型与理由

| 组件 | 选型 | 理由 | 是否变更 |
|---|---|---|---|
| 引擎 | Godot 4.7.2 Standard | 2D 优先、GDScript 无需编译链、导出包小、`gl_compatibility` 覆盖低端安卓 | 不变 |
| 语言 | GDScript（逐步提高静态类型覆盖） | 与引擎深度集成、热重载快；静态类型能在编辑器期发现接口不匹配 | 不变，提高类型密度 |
| 渲染 | 2D，`gl_compatibility` | 目标设备为 Android 中低端，Vulkan 收益低而兼容风险高 | 不变 |
| 分辨率 | 1280×720，`canvas_items` + `keep` | 16:9 基准，等比缩放保证不同屏幕下不被裁切 | 不变 |
| 数据格式 | `.tres` Resource | 引擎原生、编辑器可视化编辑、可版本对比、支持继承 | **新增** |
| 测试 | 自建 SceneTree 无头脚本 | 零依赖、启动快、可在 CI 中跑；GUT 等框架会引入插件依赖 | 保留，抽公共基类 |
| 版本控制 | Git + 分支 + PR | 已有实践：`feature/*`、`fix/*`、`docs/*` | 不变 |
| CI | GitHub Actions（待批准） | 自动跑 582 条断言，防回归 | **待授权** |

### 4.2 各组件职责与集成

**`SkillDefinition`（Resource）**
字段：`skill_id`、`display_name_zh`、`description_zh`、`ap_cost`、`target_mode`、`min_range`、`max_range`、`damage_type`、`damage_multiplier`、`effect_id`、`duration_player_phases`、`requires_judgment_mark`、`is_passive`。
职责：纯声明。`SkillExecutor` 读取字段决定校验与结算分支，**不在 Resource 里写逻辑**。

**`EnemyDefinition`（Resource，新增）**
字段：`archetype_id`、`display_name_zh`、`health`、`attack`、`defense`、`magic_resistance`、`intent_priority`、`action_ids`。
集成点：`start_encounter` 用 `EnemyDefinition` 建 `BattleActor`，替换现有 4 层嵌套三元。

**边界说明（重要）**：数据化只覆盖**属性**。敌人的**行为**（先锋的蓄力锁格、神射手的射线、术士的十字区域）目前是控制器里的 `_generate_*_intent` 分支，**新增一种全新行为仍然要写代码**。数据化能解决的是"调数值"和"复用已有行为的新敌人"，不能解决"新机制"。这一区分要写进验收标准，避免对数据化收益的过度预期。

**`LevelDefinition`（Resource，由 `EncounterDefinition` 演化）**
新增字段：`enemy_definition_ids`（引用 `EnemyDefinition` 而非字符串兵种名）、`recommended_order`。
集成点：`BattleFlow.start_encounter` 按 ID 查表组装敌人。

**`Balance`（Resource，新增）**
字段：`player_ap`、`player_health`、`player_attack`、`oath_shield_ratio`、`ultimate_energy_max`、`oath_vow_max_stacks`、`area_reduction_percent` 等。
集成点：规则层所有数值从此读取，杜绝魔法数字。

**`BattleController`（门面）**
保留现有 `request_*` / `get_*` 签名不变，内部委托给各子系统。**这是重构的关键手法**——582 条断言不用改一行，就能验证拆分没有破坏行为。

**`DamagePipeline`**
固定顺序：基础伤害 → 防御/魔抗 → 区域减伤（可多个）→ 护盾吸收 → 终段减伤（誓盾）→ 结算破绽。当前这段逻辑埋在 `_apply_damage` 里约 40 行，抽出来后可单独测每一环。

**`InputRouter`**
把 `InputEventScreenTouch` / `InputEventMouseButton` / `InputEventKey` 归一化为语义意图（`MOVE_TO`、`CAST_SKILL`、`CANCEL`、`END_TURN`、`SETTLE_ACTION`），供 `BattleScene` 消费。当前 `_input` 里三种事件类型各自 if-else，且键盘直接调 `_on_skill_pressed(index)`，耦合了技能栏索引——这是 Android 适配的主要障碍。

### 4.3 明确不引入的技术

| 候选 | 不引入理由 |
|---|---|
| C# / .NET | 需要额外运行时与编译链，导出包增大，与现有 GDScript 代码需互操作层 |
| GUT / WAT 测试框架 | 引入插件依赖与学习成本；现有 582 条断言已覆盖关键路径，抽基类即可 |
| ECS 架构 | 当前实体规模（1 玩家 + 3 敌人）远未到需要 ECS 的复杂度，迁移成本远高于收益 |
| 行为树插件 | 三种敌人的决策规则是确定性 if 分支，行为树会掩盖"预告必须可读"这一核心约束 |
| 自研状态机框架 | Godot 的 `enum` + `match` 足够，框架化会稀释可读性 |
| 第三方 UI 框架 | 原生 Control 节点 + Theme 已足够，额外框架增加安卓适配风险 |

---

## 五、整合 / 重构 / 废弃清单

### 5.1 整合（两套并存 → 一套）

| 对象 | 动作 | 前置条件 |
|---|---|---|
| `oathkeeper_skill_catalog.gd`（v1） | **废弃**，迁移到 `data/skills/*.tres` 后删除 | v1 专属测试改为测数据文件 |
| `oathkeeper_v2_skill_catalog.gd` | 转为 `.tres` 资源集合，类保留为加载器 | 无 |

### 5.2 重构（拆解）

| 对象 | 现状 | 目标 |
|---|---|---|
| `battle_controller.gd` | 936 行 / 44 函数 / 7 职责 | 门面约 150 行 + 7 个子系统 |
| `battle_view.gd` | 562 行单文件 | 6 个文件，单文件 < 150 行 |
| `start_encounter` 敌人属性 | 4 层嵌套三元 | 查 `EnemyDefinition` 表 |
| 技能/关卡构造 | `_make_skill()` / `_make_level()` 代码构造 | `.tres` 资源文件 |
| 测试 | 15 份重复的 `_check/quit` | 继承 `TestCase`，加 `run_all` |

### 5.3 废弃（删除）

| 对象 | 行数估算 | 删除前提 |
|---|---|---|
| `request_player_attack` | ~20 | 确认普攻不再回归（PR #10 已移除 UI 入口） |
| `request_oathguard_stance` | ~15 | 同上，v1 技能已不在技能栏 |
| `request_echo_counter` | ~15 | 同上 |
| `request_watchwall` | ~30 | 同上；`battle_area_effect` 保留（绝对守护可能复用） |
| `request_judgment_mark`（v1） | ~28 | 由 `request_oathkeeper_judgment_mark` 取代 |
| `request_oath_severance` | ~30 | v2 已无此技能 |
| `_resolve_judgment_mark` 等配套私有函数 | ~60 | 随上项一并删 |

合计约 **200 行**，占控制器 21%。但注意：这 6 个接口被 5 个测试文件引用（`test_battle_controller`、`test_battle_area_effects`、`test_battle_echo_counter`、`test_battle_stats`、`test_diagonal_line_of_sight`），**删除必须先迁移测试**，不能直接砍。

**建议处置**：先标记 `@warning_ignore` + 注释 `# LEGACY: 计划在 0.2 移除`，等数据层迁移完成后统一删除，避免一次改动同时动代码和测试。

---

## 六、迁移步骤与优先级

原则：**每步都可独立验证、可回滚，且 582 条断言全程保持 0 失败。**

### M0｜基线与守护（优先级：最高，成本最低）

| 步骤 | 内容 | 验收 |
|---|---|---|
| M0-1 | 抽 `tests/framework/test_case.gd`，15 个套件改为继承 | 断言总数仍为 582，0 失败 |
| M0-2 | 加 `tests/run_all.bat`，一次跑全部并汇总 | 一条命令输出"15 套件 / 582 断言 / 0 失败" |
| M0-3 | 记录基线：当前 SHA + 断言数写入 `docs/engineering/BASELINE.md` | 后续每步都对比此基线 |

**为什么先做这个**：后面每一步重构都要靠它判断"有没有改坏"。没有一键回归，重构就是盲改。

### M1｜数据外置（优先级：高）

| 步骤 | 内容 | 验收 |
|---|---|---|
| M1-1 | 新增 `EnemyDefinition`，三种敌人写成 `.tres`，`start_encounter` 改为查表 | 嵌套三元消失；`test_battle_controller` 全绿 |
| M1-2 | `Balance` 资源，收敛散落数值 | 规则层无字面量数字（grep 校验） |
| M1-3 | 技能迁到 `data/skills/*.tres` | `test_skill_definitions`、`test_oathkeeper_v2_skill_catalog` 全绿 |
| M1-4 | 关卡迁到 `data/levels/*.tres` | `test_level_catalog` 全绿 |

**风险**：`.tres` 在版本控制里是文本，合并冲突比代码多。缓解：一个资源一个文件，字段顺序固定。

### M2｜控制器拆分（优先级：高，风险最高）

| 步骤 | 内容 | 验收 |
|---|---|---|
| M2-1 | 先抽 `DamagePipeline`（纯函数，无状态） | 伤害相关断言全绿；新增管线单测 |
| M2-2 | 抽 `IntentPlanner` + `IntentResolver` | 意图相关断言全绿 |
| M2-3 | 抽 `SkillExecutor` + `SummonService` | 技能与召唤断言全绿 |
| M2-4 | 抽 `BattleFlow`（回合/胜负/结算） | 回合与结算断言全绿 |
| M2-5 | `BattleController` 变为门面，`request_*` 签名不变 | 全部 582 条断言不改一行即通过 |

**关键约束**：M2 全程**不修改任何测试文件**。如果测试要改，说明对外行为变了，必须回退。

### M3｜表现层拆分（优先级：中）

| 步骤 | 内容 | 验收 |
|---|---|---|
| M3-1 | 抽 `theme_palette.gd`，颜色/字号/间距常量化 | 视觉零变化（截图对比） |
| M3-2 | 拆 `BoardView` / `HudView` / `SkillBarView` / `SettlementView` | 视觉零变化 |
| M3-3 | 抽 `InputRouter`，键盘不再直接调技能索引 | 键鼠操作与拆分前一致 |
| M3-4 | （可选）迁移到 Control 节点 + 锚点布局 | 1280×720 与 1920×1080 下布局均正确 |

**为什么 M3 在 M2 之后**：UI 拆分不改变规则，但需要稳定的规则层 API。先拆 UI 会让接口频繁变动，返工。

### M4｜治理与自动化（优先级：低，但长期收益大）

| 步骤 | 内容 | 验收 |
|---|---|---|
| M4-1 | 文档分层：`design/` `engineering/` `archive/`，加 `docs/README.md` 索引 | 新人能在索引里找到入口 |
| M4-2 | 废弃代码清理（第 5.3 节） | 控制器降至约 740 行 |
| M4-3 | CI（**需作者批准**） | 每次 PR 自动跑 582 条断言 |

### 6.1 优先级总表

| 优先级 | 阶段 | 理由 |
|---|---|---|
| P0 | M0 | 没有回归守护，后面所有重构都是赌博 |
| P1 | M1 | 数据外置收益最直接，风险最低，为 M2 铺路 |
| P1 | M2 | 解决最大结构问题，但必须靠 M0 + M1 保护 |
| P2 | M3 | 为 Android 适配做准备，可延后 |
| P3 | M4 | 长期收益，不阻塞功能开发 |

### 6.2 建议的落地节奏

不建议一次性做完。每个 M 阶段单独开分支、单独 PR：

```
docs/framework-proposal   ← 本文档（当前）
  └─ refactor/test-framework      M0
       └─ refactor/data-driven     M1
            └─ refactor/split-controller   M2
                 └─ refactor/split-view    M3
                      └─ chore/docs-and-ci M4
```

每阶段合并前必须：15 套件 0 失败 + 与 `BASELINE.md` 对比断言数不减。

---

## 七、风险与对策

| 风险 | 概率 | 对策 |
|---|---|---|
| M2 拆分时行为漂移，测试仍绿但手感变了 | 中 | 每抽一个子系统，额外写 3–5 条针对性单测，而不只依赖现有断言 |
| `.tres` 资源合并冲突 | 中高 | 一资源一文件；字段顺序固定；改数值前先 pull |
| 拆分后接口变化导致作者的其他分支冲突 | 高 | M2 保持 `request_*` 签名不变；合并前与作者同步 |
| 过度设计：为三种敌人引入过重抽象 | 中 | 每层只解决一个问题；L2 保持纯数据，不引入事件总线 |
| 文档分层后旧链接失效 | 中 | 移动文件时同步更新 `docs/README.md` 与代码内注释引用 |

---

## 八、验收标准

架构调整完成后，应满足：

1. `battle_controller.gd` ≤ 200 行，只做门面与依赖编排。
2. `scripts/ui/` 下无单文件超过 200 行。
3. `scripts/rules/` 不 import 任何 `scripts/ui/` 模块（可用 grep 断言）。
4. 规则层无魔法数字：所有数值来自 `Balance` 或数据资源。
5. 新增一种**复用已有行为**的敌人只需加一个 `.tres` + 一处关卡引用，不改控制器；新增**全新行为**仍需实现 `_generate_*_intent` 分支，并在本文档登记。
6. 新增一个关卡只需加一个 `.tres`，不改代码。
7. 一条命令跑完全部测试并汇总，输出 0 失败。
8. 15 套件断言总数 ≥ 582（不得因重构减少覆盖）。
9. `docs/README.md` 能让新人 30 分钟内定位到"我要改的东西在哪"。

---

## 九、已决策与待确认事项

### 已决策（2026-11-25，项目所有者）

1. **v1 技能废弃**：`oathkeeper_skill_catalog.gd` 及 6 个 v1 遗留 `request_*` 接口确认永久废弃，不再回归。
   - 处置调整：第 5.3 节的删除从「M4 延后」提前到 **M2 完成后的独立提交**，但**仍须先迁移那 5 个测试文件**。
   - 具体做法：`test_battle_controller`、`test_battle_area_effects`、`test_battle_echo_counter`、`test_battle_stats`、`test_diagonal_line_of_sight` 中涉及 v1 接口的用例，改为只测 v2 等价能力；v1 专属用例随接口一并删除，并在 `docs/archive/` 留一份用例清单，避免"删了测试等于降低覆盖"的争议。

### 待确认

1. **是否批准 CI**：项目规则明确要求 GitHub Actions 需单独批准。
2. **UI 是否迁移到 Control 节点**：M3-4 是可选步骤。若确定要做 Android 自适应布局，建议纳入；若 Android 只做固定横屏，immediate-mode 也够用。
3. **数值平衡阶段**：当前 12000 生命 / 2000 攻击的规模是否在 0.2 前调整？调数值会牵动 `Balance` 资源的字段设计。
