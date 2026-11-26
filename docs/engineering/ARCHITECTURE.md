# ECHO — 当前架构

本文件描述 **`main` 当前实际存在的实现**，不是规划稿，也不承担进度汇报职责（进度见 `PROJECT_STATUS.md`，重构对照基准见 `docs/engineering/BASELINE.md`）。历史演进过程请查阅 git 记录。

最后核对：2026-11-26，`main`（PR #55 2.5D 新底层重构与测试基线对齐后；当前版本先行单角色瑟弗林验证，底层多角色框架保持兼容），Godot 4.7.2 导入零错误、**十八个测试套件 840 条断言 0 失败**（本机实测复核与 `docs/engineering/BASELINE.md` 一致）。

> **首次克隆提示**：克隆后须先在 Godot 4.7.2 Standard 中导入项目（GUI 导入，或执行 `godot --headless --path . --import`）生成 `.godot` 导入缓存，再运行测试；否则依赖 `.tres` 资源的套件会因资源未导入而报「crashed or failed to parse」。

## 目录结构

```
.
├── project.godot                     # Godot 4.7.2 工程配置（1280×720，横屏优先）
├── scenes/menu/main_menu.tscn        # 启动场景，挂载 main_menu.gd
├── scenes/main/main.tscn             # 战斗场景，挂载 battle_view.gd
├── scripts/
│   ├── main.gd                       # 极简入口脚本
│   ├── actors/battle_actor.gd        # 战斗单位运行时数据、技能充能与偷取装备状态
│   ├── battle/                       # 战斗规则、肉鸽单局状态、宝箱战利品目录与数据目录（见下）
│   └── ui/                           # battle_view.gd（2.5D 战斗编排）+ inventory_view.gd + main_menu.gd
├── data/
│   ├── enemies/                      # 三种敌人的 .tres 属性档案与动作清单（M1）
│   └── levels/                       # 三关 .tres 关卡配置（M1）
├── assets/
│   ├── actors/                       # 瑟弗林与三类敌人正/背面立绘与 portraits/ 大头头像
│   └── ui/                           # 主菜单背景图（main_menu_background.png）与图标
├── tools/
│   └── process_sprites.py            # 角色立绘抠图、规范尺寸与头像羽化批处理脚本
├── tests/                            # 18 个无头套件 + framework/（公共基类、文档守卫）+ run_suites.gd 统一运行器
└── docs/                             # 设计规范、状态记录、工程基线与验证清单
```

## 模块清单

表内行数是写作时的快照，用于判断模块体量，不参与任何断言。改动模块后顺手核对一眼，偏差变大就说明这里该更新了：

```bash
wc -l scripts/**/*.gd
```

### 战斗规则（`scripts/battle/`）

#### 控制器门面与子系统（M2 拆分）

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `battle_controller.gd` | 478 | **权威状态持有者与唯一 UI 入口**：状态字段、`request_*` 公共面、阶段枚举、信号与转发 | 子系统以 `battle` 实例参数操作状态，依赖单向；`PLAYER_MOVE_MAX_STEPS` 常量供 UI 读取 |
| `battle_flow.gd` | 315 | 回合边界、遭遇构建、终止判定 | — |
| `intent_planner.gd` | 419 | 敌方意图生成 | — |
| `intent_resolver.gd` | 223 | 敌方意图执行 | actor 锁定攻击按设计不可闪避（执行时不复查距离）；绝对守护嘲讽覆盖两格半径 |
| `skill_executor.gd` | 278 | 玩家技能校验与结算；施法者取自 `get_active_character()`；AP 退款走账本 | — |
| `damage_pipeline.gd` | 93 | 伤害结算与一切命中反应（誓约、反击、统计、阵亡清理） | **命中判据统一**：到达存活单位的伤害即命中，护盾全吸收也算；结算统计仍按实际扣血 |
| `summon_service.gd` | 98 | 猎人通灵 | — |

#### 数据与规则件

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `grid_rules.gd` | 137 | 纯网格校验、路径合法性、候选寻路（`find_path`，仅供 UI 提示）、曼哈顿距离；正交视线与玩家侧直线视线 | 无状态，不持有战斗数据；寻路产物须由 controller 复验 |
| `ap_budget.gd` | 46 | 确定性 AP 账本：重置、消耗、退款、回合结束清零 | 仅在动作确认后扣除；退款走 `refund()`，不绕过账本 |
| `combat_math.gd` | 26 | 共享伤害公式，防御采用递减收益 | 物理走防御、法术走法抗 |
| `damage_types.gd` | 45 | 伤害类型的**封闭集合**（物理 / 法术 / 真伤）、抗性映射、真伤是否跳过减伤 | 集合外的类型在结算前被拒，避免拼写错误静默绕过全部防御 |
| `battle_intent.gd` | 59 | 敌方意图快照，actor / tile / area 三种锁定模式与 active→resolved/canceled 单向生命周期 | **预告展示与敌方执行使用同一份快照** |
| `battle_status.gd` | 48 | 单个状态实例：触发次数（-1 为无限）、到期边界、叠层策略 | — |
| `battle_status_collection.gd` | 218 | 按 actor 聚合状态，处理阶段边界过期与延迟 | 延迟接口保留，当前无调用方 |
| `skill_definition.gd` | 77 | 技能纯数据规格（Resource） | 不含执行逻辑 |
| `oathkeeper_v2_skill_catalog.gd` | 57 | **当前生效**的守誓者 V2 技能数据 + 被动不屈誓约 | 数值待实战验证；UI 技能栏由此生成 |
| `sakura_skill_catalog.gd` | 105 | 樱的四技能与被动（剑意 / 极意 / 残香 / 回锋所依赖的数据） | **当前版本不参战**，数据与框架保留待后续接入；测试仍覆盖 |
| `enemy_definition.gd` / `enemy_catalog.gd` | — | 敌人属性档案（Resource）与目录（M1） | 数值外置于 `data/enemies/*.tres`；`actions` 列表决定该原型按优先级尝试哪些行动 |
| `intent_planner.gd` | 419 | 按 `actions` 顺序挑行动；多怪目标分流（`claimed_cells` 防抢同一格）、远程风筝取位；生成意图预告 | 只读不写状态；行动的合法性在代码、组合在数据 |
| `encounter_definition.gd` | 63 | 单关数据与布阵自洽校验 | 只描述配置，不持有运行时状态 |
| `level_catalog.gd` | 29 | 三关 `.tres` 的固定播放顺序 | 不使用随机布阵与目录扫描 |
| `run_state.gd` | 317 | 单局 Roguelite 状态：跨关血量、武器/护甲装备槽、背包、技能铭文强化与 `reset()` 清空 | 仅存活于单局内存，通关开新局或战败重开时全部清空 |
| `loot_catalog.gd` | 222 | 遗迹宝箱战利品池：随机生成武器、护甲、消耗品与技能升级物品 | 玩家与敌人共享同一份物品属性结构，保证对称抢宝规则 |

### 角色层（`scripts/battle/`）

加一名角色 = 一个 `.tres` + 技能数据，不改控制器。

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `character_definition.gd` | 70 | 角色面板、五槽位技能 id、职业资源声明 | 纯数据；`skill_ids` 按槽位顺序 |
| `character_catalog.gd` | 48 | `data/characters/*.tres` 的显式名册 | 不用目录扫描，出战名单可评审 |
| `skill_registry.gd` | 78 | 跨角色技能解析（id → 定义） | 角色只写 skill id，不关心来自哪个目录 |
| `character_skill_runtime.gd` | 111 | 唯一入口：召唤前缀、技能归属校验、自目标补齐，再按 `executor_id` 分派；`can_aim()` 与剑意入账转发到效果层 | 执行器表是唯一分派点，缺登记即 `push_error` 并返回 false |
| `combat_geometry.gd` | 138 | 纯网格查询：射程、视线、矩形与十字落点、突进落点 | 不认识角色、机制或设计数值；极意的范围加成由调用方以参数传入 |
| `skill_effects.gd` | 565 | 各技能的结算分支：樱的剑意 / 极意 / 残香 / 回锋、通用普攻、守誓者三技的包装，以及伤害分段与剑意预算的公共记账 | 只按 `executor_id` 被调用；不算格子，几何一律问 `CombatGeometry` |
| `summon_definition.gd` / `summon_catalog.gd` | — | 通灵数据（`data/summons/*.tres`）与名册 | 通灵属于玩家，不属于角色面板 |
| `summon_service.gd` | 98 | 通灵的可用性、现身格与冷却 | 数值全部来自 `SummonDefinition` |

行数表覆盖承担逻辑的模块；`summon_definition.gd` / `summon_catalog.gd` 这类纯数据 Resource 合并成一行，不记行数。槽位见 `CharacterDefinition.SLOT_ORDER`：普通攻击、被动、主动一、主动二、终极。技能栏由当前角色的槽位生成，`Tab` 切换角色。

**执行层不认角色名**：施法者一律取 `active_character_id`，没有任何执行器假定某一个角色。机制则按「状态在谁身上」或「谁带这个被动」解析：

| 机制 | 归属依据 | 而不是 |
|---|---|---|
| 誓盾庇护 / 裁决印记 / 绝对守护的施法者 | `controller.active_character_id` | 固定瑟弗林 |
| 移动 | `controller.active_character_id` | 固定瑟弗林 |
| 不屈誓约累积 | `has_passive(actor_id, &"oath_vow")` | 硬编码目标 id |
| 绝对守护的嘲讽与反击 | `get_absolute_guardian()`，即持有 `absolute_guard` 状态者 | 硬编码瑟弗林 |

所以「谁在守」由状态决定，「谁的誓约」由被动决定，与角色 id 无关。

**终极能量**：上限是角色属性（`CharacterDefinition.ultimate_energy_max` → 单位的 `ultimate_energy_max`），释放终极消耗整池。因此执行器与技能栏都不再持有数字，不同角色可以有不同池深。

**极意（§19-23）**：剑意满层即极意，无需额外标志位。极意强化下一次主动技能（流风追加 40% 追击、落英范围与回锋提升），随后清空剑意，再按正常规则获取；普通攻击与终极既不消耗也不清除。

**通灵不是角色技能**：它属于玩家，任何角色都能使用，技能栏在角色槽位之后追加。技能 id 形如 `summon:yu_bubble`，运行时按前缀分派，因此新增一个通灵不需要改代码——只加一个 `.tres`。

### 单位（`scripts/actors/`）

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `battle_actor.gd` | 221 | 单位身份、阵营、格位、整数血量、护盾、终极能量、承伤与阵亡状态 | 终段减伤在防御/抗性之后应用 |

### 表现层（`scripts/ui/`）

表现层拆为十一个文件：棋盘渲染按职责再分三层——编排/地形/提示（board_view）、威胁预告（board_threat_view）与世界实体深度排序（board_objects_view），依赖单向向下，共享等距绘制原语住在调色板。原句：`main_menu.gd` 是唯一的启动场景，`battle_view.gd` 负责 2.5D 战斗编排（关卡流程、分步敌方回合演出、技能栏、装备背包弹窗与玩家意图），绘制分别转发给下面的视图，原始输入转发给 `input_router`。

| 模块 | 行数 | 职责 |
|---|---|---|
| `battle_view.gd` | 695 | 编排：关卡流程、分步敌方回合动画、4 技能栏构建、点击分发、`Q/E` 旋转视角与 `B` 键背包切换 |
| `board_view.gd` | 215 | 编排层：等距石板棋盘与侧棱、移动/悬停/目标提示、目标谓词 `can_target()` / `can_target_ally()`；其余绘制转发给威胁层与实体层 |
| `board_threat_view.gd` | 235 | 威胁层：敌方攻击预告（警戒斜条纹）、落点伤害标签、打击闪爆、飘字、受威压呼吸红晕，以及全家族共用的 `is_cell_in_danger()` 查询 |
| `board_objects_view.gd` | 423 | 实体层：按等距深度排序的废墟立柱、遗迹宝箱、4 向动态立绘与受击动画、地面掉落光柱、血条/充能条与头顶徽标；持有精灵纹理缓存 |
| `skill_bar_view.gd` | 154 | 底部横向 4 技能条（悬停浮窗显示完整技能说明）、结束回合按钮与操作提示；`skill_rect()` 是唯一的按钮几何，`is_affordable()` 是唯一的按钮可用判据 |
| `theme_palette.gd` | 272 | 全部颜色与坐标常量、2.5D 等距菱形投影（`80×44`）与 4 对角 90° 旋转正反算（`cell_to_iso` / `cell_at`）、共享绘制原语（闭合折线/等距椭圆）与立绘高度常量 |
| `hud_view.gd` | 353 | 左下角主角大头头像与血条/护盾/AP/能量、顶部关名与战况、右上角敌方行动顺序与技能充能情报卡 |
| `inventory_view.gd` | 125 | `[B]` 键开关的装备与背包弹窗：展示武器槽、护甲槽、背包物品与点击穿戴/卸下/使用交互 |
| `settlement_view.gd` | 151 | 结算面板、完好遗迹宝箱开箱战利品展示、三选一肉鸽强化与其点击区 |
| `input_router.gd` | 74 | 触屏 / 鼠标 / 键盘 → `tap` / `skill` / `cancel` / `end_turn` / `rotate_camera` / `toggle_inventory` |
| `main_menu.gd` | 184 | 启动菜单：新黄昏背景图与飘浮光尘、极简悬停横条动画、键盘与点击选中；继续/设置仅为占位 |

技能栏的规则数值（AP 消耗、目标范围）由 `OathkeeperV2SkillCatalog` 生成，单一数据来源；棋盘尺寸读 `controller.grid_size`；移动上限读 `BattleController.PLAYER_MOVE_MAX_STEPS`，候选寻路委托 `GridRules.find_path`。

输入约定：数字键 `1`–`4` 对应瑟弗林四个技能（`1` 誓刃、`2` 裁决印记、`3` 誓盾庇护瞬发、`4` 绝对裁决瞬发）；`Q / E` 左右旋转四对角视角；`B` 开关装备/背包面板；`Esc` 或右键取消目标选择/关闭弹窗；`Enter`/空格结束回合。结算面板出现时，点击响应「重开本关」与「下一关 / 重新开始」。

## 运行时数据流

```
main.tscn (Node2D + battle_view.gd)
   │
   ├─ 读取 ──> LevelCatalog(.tres)    三关固定配置
   │
   ├─ 创建并持有 ──> BattleController（门面 + 权威状态）
   │                    ├─ BattleFlow       回合边界 / 遭遇 / 终止
   │                    ├─ IntentPlanner    敌方意图生成
   │                    ├─ IntentResolver  敌方意图执行
   │                    ├─ SkillExecutor    玩家技能
   │                    ├─ SummonService    猎人通灵
   │                    ├─ DamagePipeline   伤害与命中反应
   │                    ├─ APBudget         AP 账本
   │                    └─ signals: battle_event / battle_finished
   │
   └─ 每帧读取 controller 状态并绘制 ──> 屏幕
        ▲
        └─ 输入事件 ──> controller.request_* 方法 ──> 状态变更 ──> queue_redraw()
```

UI 不计算任何结果：命中、伤害、死亡、意图取消、护盾吸收全部由 controller 及其子系统判定并发事件。

## 关卡与结算流程

1. `battle_view._ready()` 读取 `LevelCatalog`，调用 `_start_level(0)`。
2. `_start_level(index)` 取出 `EncounterDefinition`，调用 `controller.start_encounter(...)` 重建全部战斗状态（单位、状态、区域、意图、AP、结算统计）。
3. 战斗结束时 `battle_finished` 触发，界面进入结算面板。
4. 点击「重开本关」回到步骤 2；点击「下一关」进入下一索引，最后一关之后回到第 0 关。

## 权威边界（仍然有效）

1. 玩法系统持有权威状态；UI 只读取与呈现，不得独立计算结果。
2. 敌方意图的展示与执行必须使用同一份动作定义与结算规则。
3. 战斗事件必须按已文档化的确定性顺序结算（见 `docs/design/BATTLE_EVENT_TIMELINE_v0.1_zh-CN.md`）。
4. 局外进度与单局临时状态必须分离。
5. 单局状态不得序列化用于进程终止后的恢复。
6. 内容定义应尽量数据驱动，但不得因此掩盖规则或使原型复杂化。

## 当前未实现

| 项 | 状态 |
|---|---|
| Android 布局、触摸适配、导出与真机（P4） | 未开始；当前仅桌面鼠标键盘验证 |
| Windows 人工交互与画面检查 | 自动化与无头运行已通过，真人操作待做 |
| 关卡选择 | 不在 Prototype 0.1 范围；关卡只能经结算面板的「下一关」切换 |
| 主菜单的「选择存档」/「设置」 | 仅作为占位绘制，不可选中也不接受点击 |
| 战斗内存档与恢复 | 明确排除 |

## 验证状态

见 `docs/engineering/PROJECT_STATUS.md` 与 `docs/engineering/BASELINE.md`（**当前套件数与断言总数以 BASELINE 的「断言总数」行为准，不在本页写死**，避免随基线演进腐化）：2026-11-26 在 Godot 4.7.2（Windows）完成导入、全套无头回归与主场景运行。Windows 人工交互手感、画面观感、Android 真机表现仍未验证。更早的 Linux 无头运行记录保留在 `docs/archive/GODOT_ENGINE_VALIDATION_zh-CN.md` 作为历史参考。
