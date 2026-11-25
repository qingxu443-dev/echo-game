# ECHO — 当前架构

本文件描述 **`main` 当前实际存在的实现**，不是规划稿，也不承担进度汇报职责（进度见 `PROJECT_STATUS.md`，重构对照基准见 `docs/engineering/BASELINE.md`）。历史演进过程请查阅 git 记录。

最后核对：2026-11-25，`main` @ `2afcb0c`（PR #33 合并后），Godot 4.7.2 导入零错误、**十七个测试套件 716 条断言 0 失败**（本机实测复核与 `docs/engineering/BASELINE.md` 一致）。

> **首次克隆提示**：克隆后须先在 Godot 4.7.2 Standard 中导入项目（GUI 导入，或执行 `godot --headless --path . --import`）生成 `.godot` 导入缓存，再运行测试；否则依赖 `.tres` 资源的套件会因资源未导入而报「crashed or failed to parse」。

## 目录结构

```
.
├── project.godot                     # Godot 4.7.2 工程配置（1280×720，横屏优先）
├── scenes/main/main.tscn             # 唯一场景，挂载 battle_view.gd
├── scripts/
│   ├── main.gd                       # 极简入口脚本
│   ├── actors/battle_actor.gd        # 战斗单位运行时数据与伤害结算
│   ├── battle/                       # 战斗规则、状态与数据目录（22 个模块，见下）
│   └── ui/battle_view.gd             # 战斗界面：绘制、输入、技能栏、结算面板
├── data/
│   ├── enemies/                      # 三种敌人的 .tres 属性档案（M1）
│   └── levels/                       # 三关 .tres 关卡配置（M1）
├── assets/ui/summons/                # 猎人通灵的表现层图标
├── tests/                            # 17 个无头套件 + framework/test_case.gd 公共基类 + run_all 一键回归
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
| `battle_controller.gd` | 267 | **权威状态持有者与唯一 UI 入口**：状态字段、`request_*` 公共面、阶段枚举、信号与转发 | 子系统以 `battle` 实例参数操作状态，依赖单向；`PLAYER_MOVE_MAX_STEPS` 常量供 UI 读取 |
| `battle_flow.gd` | 225 | 回合边界、遭遇构建、终止判定 | — |
| `intent_planner.gd` | 129 | 敌方意图生成 | — |
| `intent_resolver.gd` | 188 | 敌方意图执行 | actor 锁定攻击按设计不可闪避（执行时不复查距离）；绝对守护嘲讽覆盖两格半径 |
| `skill_executor.gd` | 163 | 玩家技能校验与结算；施法者取自 `get_active_character()`；AP 退款走账本 | — |
| `damage_pipeline.gd` | 75 | 伤害结算与一切命中反应（誓约、反击、统计、阵亡清理） | **命中判据统一**：到达存活单位的伤害即命中，护盾全吸收也算；结算统计仍按实际扣血 |
| `summon_service.gd` | 98 | 猎人通灵 | — |

#### 数据与规则件

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `grid_rules.gd` | 137 | 纯网格校验、路径合法性、候选寻路（`find_path`，仅供 UI 提示）、曼哈顿距离；正交视线与玩家侧直线视线 | 无状态，不持有战斗数据；寻路产物须由 controller 复验 |
| `ap_budget.gd` | 42 | 确定性 AP 账本：重置、消耗、退款、回合结束清零 | 仅在动作确认后扣除；退款走 `refund()`，不绕过账本 |
| `combat_math.gd` | 17 | 共享伤害公式，防御采用递减收益 | 物理走防御、法术走法抗 |
| `battle_intent.gd` | 59 | 敌方意图快照，actor / tile / area 三种锁定模式与 active→resolved/canceled 单向生命周期 | **预告展示与敌方执行使用同一份快照** |
| `battle_status.gd` | 48 | 单个状态实例：触发次数（-1 为无限）、到期边界、叠层策略 | — |
| `battle_status_collection.gd` | 213 | 按 actor 聚合状态，处理阶段边界过期与延迟 | 延迟接口保留，当前无调用方 |
| `skill_definition.gd` | 78 | 技能纯数据规格（Resource） | 不含执行逻辑 |
| `oathkeeper_v2_skill_catalog.gd` | 60 | **当前生效**的守誓者 V2 技能数据 + 被动不屈誓约 | 数值待实战验证；UI 技能栏由此生成 |
| `enemy_definition.gd` / `enemy_catalog.gd` | 23 / 34 | 敌人属性档案（Resource）与目录（M1） | 数值外置于 `data/enemies/*.tres` |
| `encounter_definition.gd` | 58 | 单关数据与布阵自洽校验 | 只描述配置，不持有运行时状态 |
| `level_catalog.gd` | 29 | 三关 `.tres` 的固定播放顺序 | 不使用随机布阵与目录扫描 |

### 角色层（`scripts/battle/`）

加一名角色 = 一个 `.tres` + 技能数据，不改控制器。

| 模块 | 职责 | 关键约束 |
|---|---|---|
| `character_definition.gd` | 角色面板、五槽位技能 id、职业资源声明 | 纯数据；`skill_ids` 按槽位顺序 |
| `character_catalog.gd` | `data/characters/*.tres` 的显式名册 | 不用目录扫描，出战名单可评审 |
| `skill_registry.gd` | 跨角色技能解析（id → 定义） | 角色只写 skill id，不关心来自哪个目录 |
| `character_skill_runtime.gd` | 按 `executor_id` 分派技能；樱的剑意 / 残香 / 回锋；通用普攻；`can_aim()` 是射程与视线的唯一真源 | 数值来自数据，机制才写代码 |
| `summon_definition.gd` / `summon_catalog.gd` | 通灵数据（`data/summons/*.tres`）与名册 | 通灵属于玩家，不属于角色面板 |
| `summon_service.gd` | 通灵的可用性、现身格与冷却 | 数值全部来自 `SummonDefinition` |

槽位见 `CharacterDefinition.SLOT_ORDER`：普通攻击、被动、主动一、主动二、终极。技能栏由当前角色的槽位生成，`Tab` 切换角色。

**执行层不认角色名**：施法者一律取 `active_character_id`，没有任何执行器假定某一个角色。机制则按「状态在谁身上」或「谁带这个被动」解析：

| 机制 | 归属依据 | 而不是 |
|---|---|---|
| 誓盾庇护 / 裁决印记 / 绝对守护的施法者 | `controller.active_character_id` | 固定瑟弗林 |
| 移动 | `controller.active_character_id` | 固定瑟弗林 |
| 不屈誓约累积 | `has_passive(actor_id, &"oath_vow")` | 硬编码目标 id |
| 绝对守护的嘲讽与反击 | `get_absolute_guardian()`，即持有 `absolute_guard` 状态者 | 硬编码瑟弗林 |

所以「谁在守」由状态决定，「谁的誓约」由被动决定，与角色 id 无关。

**通灵不是角色技能**：它属于玩家，任何角色都能使用，技能栏在角色槽位之后追加。技能 id 形如 `summon:yu_bubble`，运行时按前缀分派，因此新增一个通灵不需要改代码——只加一个 `.tres`。

### 单位（`scripts/actors/`）

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `battle_actor.gd` | 188 | 单位身份、阵营、格位、整数血量、护盾、终极能量、承伤与阵亡状态 | 终段减伤在防御/抗性之后应用 |

### 表现层（`scripts/ui/`）

表现层拆为六个文件，`battle_view.gd`（293 行）只做编排：保留遭遇生命周期、技能栏与玩家意图，绘制全部转发给下面的视图，原始输入转发给 `input_router`。

| 模块 | 行数 | 职责 |
|---|---|---|
| `battle_view.gd` | 293 | 编排：关卡流程、技能栏构建、点击分发（敌人 / 友军 / 空地）、控制器信号 |
| `board_view.gd` | 199 | 棋盘、障碍、单位与状态标记、意图预告、目标圈（`can_target()` 转发 `can_aim()`，`can_target_ally()` 管友军） |
| `skill_bar_view.gd` | 185 | 五格技能栏、结束回合按钮、操作提示；`mode` 分 actor / ally / self，`skill_rect()` 是唯一的按钮几何，`is_affordable()` 是唯一的按钮可用判据 |
| `theme_palette.gd` | 124 | 全部颜色与坐标常量、棋盘几何（`cell_rect` / `cell_at`） |
| `hud_view.gd` | 103 | 标题、回合与资源读数、战术提示、敌方行动顺序 |
| `settlement_view.gd` | 71 | 结算面板与其点击区（`hit()` 同时拥有矩形与判定） |
| `input_router.gd` | 66 | 触屏 / 鼠标 / 键盘 → `tap` / `skill` / `cancel` / `end_turn` |

技能栏的规则数值（AP 消耗、目标范围）由 `OathkeeperV2SkillCatalog` 生成，单一数据来源；棋盘尺寸读 `controller.grid_size`；移动上限读 `BattleController.PLAYER_MOVE_MAX_STEPS`，候选寻路委托 `GridRules.find_path`。

输入约定：数字键 `1`–`5` 对应技能栏顺序；`Esc` 或右键取消目标选择；`Enter`/空格结束回合。自身技能按下即施放，目标技能需再点战场上的敌人确认。结算面板出现时，点击只响应「重开本关」与「下一关」。

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
| 标题菜单 / 关卡选择 | 不在 Prototype 0.1 范围；关卡只能经结算面板的「下一关」切换 |
| 战斗内存档与恢复 | 明确排除 |

## 验证状态

见 `docs/engineering/PROJECT_STATUS.md` 与 `docs/engineering/BASELINE.md`：2026-11-25 在 Godot 4.7.2（Windows）完成导入、十三个测试套件（483 条断言）与主场景运行。Windows 人工交互手感、画面观感、Android 真机表现仍未验证。更早的 Linux 无头运行记录保留在 `docs/archive/GODOT_ENGINE_VALIDATION_zh-CN.md` 作为历史参考。
