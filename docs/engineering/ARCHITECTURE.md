# ECHO 工程架构与全量审计报告

ECHO 是一款 2.5D 回合制战术肉鸽。启动后从营地大厅进入瑟弗林的三关教学遗迹，或进入樱的「春之境」普通与困难探索。两种模式共用等距战斗和局外补给商行，各自持有局内状态。

## 技术栈与运行

| 范围 | 当前实现 |
|---|---|
| 游戏运行时 | Godot **4.7.2 Standard**、GDScript、2D Canvas 与 GL Compatibility；等距网格呈现 2.5D，默认视口 1280×720 |
| 场景与内容 | `.tscn` 场景、`.tres` 自定义 Resource、显式内容目录、随资源提交的 `.uid` 和导入元数据；无需 .NET 或运行时插件 |
| 本地数据 | `user://spring_run.json` 记录春之境进度，`user://atelier_stash.json` 记录局外残晶和打包栏。教学关的局内背包在 `RunState` 内存中 |
| 自动化 | Godot 无头 GDScript 套件；PowerShell、Bash 与 Windows 批处理入口；GitHub Actions 在 Ubuntu 和 Windows 采用同版引擎 |
| 发行与资产 | Windows Desktop x86_64 导出预设，内嵌 PCK；`tools/process_sprites.py` 是可选资产工具，依赖 Python、OpenCV、NumPy 与 Pillow；该工具的依赖版本尚未锁定 |

1. 用 Godot 4.7.2 Standard 导入根目录中的 `project.godot`，按 **F5** 启动。
2. 进入大厅，点击「选择地图」。教学遗迹依序推进三关。春之境普通模式选格并确认移动，困难模式先绘制以首领格为终点的路线。
3. 战斗中左键移动或选目标，`1–4` 选技能，`Q/E` 转镜头，`B` 打开背包，Enter/Space 结束回合。
4. 自动化先执行 `godot --headless --path . --import`，再从根目录执行 `GODOT=/path/to/godot bash tests/run_all.sh`。Windows 也可执行 `./tests/run_all.ps1 -Godot <Godot-console.exe>`，该入口包含导入。
5. 导出时安装匹配的 Windows 模板，创建 `build/`，运行 `godot --headless --path . --export-release "Windows Desktop" build/ECHO_Windows_x64.exe`。人工验收见 [Windows 验证说明](TESTER_WINDOWS_0.1.md)。

## 场景、状态与核心循环

```text
project.godot → scenes/menu/main_menu.tscn → scenes/lobby/lobby.tscn
                                              ├─ 黄昏补给商行 → AtelierStash → SaveFile
                                              ├─ 教学遗迹 → scenes/main/main.tscn → RunState
                                              └─ scenes/spring/spring_map.tscn → SpringRun → SaveFile
                                                         ↕ SpringBattleBridge
                                                   scenes/main/main.tscn
                                                         ↓
    InputRouter → BattleView → BattleController → Flow / Skills / Intents / Damage
                       ↑              │
          棋盘 / HUD / FX / 结算 ←────signals
```

- **战斗**。场景从教学关卡资源或春之境遭遇定义生成战场。控制器接受移动、攻击、技能和结束回合请求，核对格位、射程、视线、状态与 AP。敌方充能随玩家行动推进；意图规划生成可预览的动作，结算器按顺序执行并复验。伤害经防御、抗性、护盾和状态结算，最终以事件驱动表现。战术机制还包含容忍反击、破甲、击杀返 AP、Boss 狂暴与结界、危险地格。
- **春之境**。地图由种子选定模板与随机事件，移动消耗探索体力。事件、行商和战斗共享本局资源。战斗经桥接传递遭遇、生命与装备背包，返回后更新节点、发奖励或要求续行。Boss 胜利后按持久解锁和场景存在性决定是否进入下一层。存档恢复原地图、事件、行商库存、路线与未完成的选择。中断正在进行的战斗时，地图从战前检查点恢复。
- **工坊**。跨局残晶用于购买、打包或退款。教学出征通过桥接传入补给，春之境新局从工坊领用并立即存档。恢复已有春之境时保留工坊新打包的物品。春之境地图内的行商使用局内资源。
- **数据和资源**。`data/characters`、`enemies`、`levels`、`loot`、`summons` 供各目录加载。技能、春之境事件与地图模板也有编译进 GDScript 的显式目录。`assets/` 存放立绘、头像、背景、素材源图及导入配置。
- **工程边界**。`tests/` 负责引擎内回归和守卫，`docs/design/` 记录设计，`docs/engineering/` 记录现状和验证入口，`docs/archive/` 保留历史。以 [逐套件基线](BASELINE.md) 核对断言总数。

## 逐模块索引

测试守卫会核对下表的行数和列数。修改脚本后可运行 `bash tests/run_all.sh --fix`，Windows 对应 `./tests/run_all.ps1 -Fix`。

### 春之境（`scripts/spring/`）

赛季地图与探索层。探索规则由 `SpringRun` 和 `ExplorationState` 持有。遭遇目录生成战斗定义，`SpringBattleBridge` 负责场景间交接与战后结算。

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `spring_place.gd` | 74 | 地图上的一个地点：坐标、类型、显示名、载荷 id | 不含内容逻辑；同一模板每次产出的坐标必须相同 |
| `spring_map_template.gd` | 81 | 5×5 模板容器：按格 / 按 id 查地点、空格枚举 | 生成后不再修改；随机事件的**身份**不在模板里，模板只占格位 |
| `spring_map_factory.gd` | 203 | 三套模板的文档数据（Boss 坐标、战斗 id、固定事件）与确定性布局 | 文档未给逐格坐标的部分由 `LAYOUT_ORDER` 推出，属**草案**；作者给出正式布局后替换此表即可 |
| `exploration_state.gd` | 165 | 探索体力与移动：曼哈顿成本、原子移动、恰好耗尽保留交互窗口、主动结束作废余量 | 不碰战斗 AP；不认地点内容 |
| `spring_run.gd` | 580 | 本局：模板 + 探索 + 资源（花钿 / 补给 / 四时花露 / 残页 / 遗物）+ 存档序列化与待决事项 | 与 `run_state.gd` 隔离（§4 禁止两模式共用局内资源）；文档未定的数值不预设 |
| `spring_run_storage.gd` | 28 | 组织春之境出征与战后结算的保存 | 工坊和本局快照经事务层提交 |
| `spring_map_view.gd` | 776 | 5×5 地图界面、资源栏、路径预览、结束探索确认与 Boss 结算交接 | 全部自绘；点击只预览，确认后才移动；困难模式委托路线浮层 |
| `spring_route_plan.gd` | 224 | 春之境困难模式定轨状态：绘线节点、体力校验、强制尾部为 Boss、锁轨游标与存档序列化 | 纯规则与状态，无 UI 依赖；旧存档无此字段自动默认普通模式 |
| `spring_route_overlay.gd` | 312 | 春之境困难模式地图路线绘制（连线/箭头/站序/王格提示）与战前绘线/定轨推进底栏交互 | 独立表现辅助层，保证 `spring_map_view.gd` 不突破存量行数上限 |
| `scripts/spring/spring_ending.gd` | 80 | 春之境留白式结局文案数据（可测试），表现层只绘制 | 暂不锁定结局，玩家陪伴樱决定 |
| `scripts/spring/spring_memory_thread.gd` | 90 | 归乡记忆线：从 event_log 只读拼合碎片、生成留白回响（§10.4 记忆拼合），表现层只绘制 | 不锁结局、不解锁区域、无数值收益 |
| `spring_encounter_catalog.gd` | 240 | 20 套遭遇的编成（十二场普通战、五场精英战、三场 Boss 战）与战场几何 | 编成是文档数据；战场坐标由「主角在南、远程在后排」一条规则推出，同 id 每次一致 |
| `spring_event_catalog.gd` | 579 | 十个事件（§10.2）+ 隐秘之地：选项、条件、效果、风险判定与结算 | 数值是草案集中一处；风险掷骰以（种子, 事件, 选项）定种，重放同一选择结果不变 |
| `spring_event_view.gd` | 109 | 事件浮层：标题、风险标签、正文、选项与结果 | 只报告点了哪个选项，不结算；可负担性由 catalog 判定 |
| `spring_shop.gd` | 378 | 春日行商：六栏库存、购买 / 出售 / 服务 / 刷新、价格修正、存档 | 交易原子；买过的商品刷新后不再上架；价格效果只作用于进入的那家店 |
| `spring_shop_view.gd` | 220 | 商店浮层：买入 / 出售 / 服务三页、翻页与刷新 | 只报告点击，不扣钱；行矩形与命中判定共用同一函数 |
| `spring_relic_catalog.gd` | 66 | 四件遗物（§5.5 来源，文档未点名具体遗物）与战斗属性加成 | 只做扁平属性加成：条件触发型需要尚不存在的 hook 系统，故不定义 |
| `spring_collectible_catalog.gd` | 115 | 六件藏品与稀有度、可用池（普通 / 精英 / Boss） | 效果限于本局能兑现的资源与属性；精英池排除史诗（§14） |
| `spring_battle_bridge.gd` | 298 | 地图 ↔ 战斗的场景间握手、战后结算与后续区域门禁（§11.2 / §11.3 / §14 / §15.4 / §16.1） | 静态字段跨场景传递；结算规则在此，不在界面层 |
| `spring_region_progression.gd` | 119 | 区域解锁记录持久化、后续区域状态判定与场景交接数据 | 独立于单局存档；必须同时满足解锁和场景存在才允许进入 |

### 战斗规则（`scripts/battle/`）

#### 控制器门面与子系统（M2 拆分）

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `battle_controller.gd` | 628 | **权威状态持有者与唯一 UI 入口**：状态字段、`request_*` 公共面、阶段枚举、信号与转发 | 子系统以 `battle` 实例参数操作状态，依赖单向；`PLAYER_MOVE_MAX_STEPS` 常量供 UI 读取 |
| `battle_flow.gd` | 477 | 回合边界、遭遇构建、终止判定 | — |
| `intent_planner.gd` | 453 | 敌方意图生成（通用招式 + 分派） | 专属技转到 `elite_skills.gd` |
| `intent_resolver.gd` | 570 | 敌方意图执行 | 按锁定类型与动作规则复验；支持状态驱动的重定向 |
| `battle_threat_preview.gd` | 51 | 固定站位下按意图顺序推演承伤 | 使用独立防守者快照，棋盘与 HUD 共享伤害明细 |
| `skill_executor.gd` | 281 | 玩家技能校验与结算；施法者取自 `get_active_character()`；AP 退款走账本 | — |
| `damage_pipeline.gd` | 99 | 伤害结算与一切命中反应（誓约、反击、统计、阵亡清理） | **命中判据统一**：到达存活单位的伤害即命中，护盾全吸收也算；结算统计仍按实际扣血 |
| `tactical_pressure.gd` | 288 | 高博弈压力子系统：临机追身转向、近战 2 次容忍反击、护甲破防、击杀返 AP、Boss 50% 血狂暴亲卫与双动连招 | 无状态外置模块（不膨胀控制器行数）；近战容忍条仅近战触发、远程不涨、回合结束清空 |
| `summon_service.gd` | 103 | 猎人通灵 | — |

#### 数据与规则件

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `grid_rules.gd` | 137 | 纯网格校验、路径合法性、候选寻路（`find_path`，仅供 UI 提示）、曼哈顿距离；正交视线与玩家侧直线视线 | 无状态，不持有战斗数据；寻路产物须由 controller 复验 |
| `ap_budget.gd` | 46 | 确定性 AP 账本：重置、消耗、退款、回合结束清零 | 仅在动作确认后扣除；退款走 `refund()`，不绕过账本 |
| `combat_math.gd` | 35 | 共享伤害公式，防御采用递减收益 | 物理走防御、法术走法抗 |
| `damage_types.gd` | 48 | 伤害类型的**封闭集合**（物理 / 法术 / 真伤）、抗性映射、真伤是否跳过减伤 | 集合外的类型在结算前被拒，避免拼写错误静默绕过全部防御 |
| `battle_intent.gd` | 108 | 敌方意图快照，actor / tile / area 三种锁定模式与 active→resolved/canceled 单向生命周期 | **预告展示与敌方执行使用同一份快照** |
| `battle_status.gd` | 48 | 单个状态实例：触发次数（-1 为无限）、到期边界、叠层策略 | — |
| `battle_status_collection.gd` | 218 | 按 actor 聚合状态，处理阶段边界过期与延迟 | 延迟接口保留，当前无调用方 |
| `skill_definition.gd` | 72 | 技能纯数据规格（Resource） | 不含执行逻辑 |
| `oathkeeper_v2_skill_catalog.gd` | 54 | **当前生效**的守誓者 V2 技能数据 + 被动不屈誓约 | 数值待实战验证；UI 技能栏由此生成 |
| `sakura_skill_catalog.gd` | 103 | 樱的四技能与被动（剑意 / 极意 / 残香 / 回锋所依赖的数据） | 春之境出战；教学遗迹使用瑟弗林 |
| `enemy_definition.gd` | 86 | 敌人属性档案 Resource | 数值外置于 `data/enemies/*.tres` |
| `enemy_catalog.gd` | 88 | 从显式资源清单加载敌人和动作优先级 | 敌人动作由招式目录校验 |
| `elite_skills.gd` | 283 | 九条精英与 Boss 专属技的几何：给友军上盾、留地格、两段式锁命、带路径突袭、降防 | 与规划器同签名 `(battle, enemy, target)`；加一条专属技只改本文件与数据表 |
| `enemy_skill_catalog.gd` | 102 | 16 条敌人招式的数值表：倍率、射程、伤害类型、充能门槛、地格比例 | **所有敌人技能数字的唯一来源**；未注册的 action 会报错而不是退化成近战 |
| `enemy_skill_definition.gd` | 68 | 单条敌人招式的数据结构（Resource），与玩家侧 `SkillDefinition` 对称 | 带 `is_valid()`；`damage_multiplier == 0` 表示「用档案里的 skill_damage」 |
| `intent_support.gd` | 537 | 规划器与专属技共用的几何工具：三格带、路径搜索、风筝取位、意图 id | 无状态；不产生意图，只算格子 |
| `encounter_definition.gd` | 77 | 单关数据与布阵自洽校验 | 只描述配置，不持有运行时状态 |
| `level_catalog.gd` | 29 | 三关 `.tres` 的固定播放顺序 | 不使用随机布阵与目录扫描 |
| `run_state.gd` | 354 | 单局 Roguelite 状态：跨关血量、武器/护甲装备槽、背包、技能铭文强化与 `reset()` 清空 | 仅存活于单局内存，通关开新局或战败重开时全部清空 |
| `loot_catalog.gd` | 115 | 遗迹宝箱战利品名册：显式引用 13 张 `data/loot/*.tres`，`to_dict()` 维持字典契约；掉落 RNG 可播种（默认种子 0 供无头可复现，新局按时间播种并记入 `run_state.loot_seed`） | 玩家与敌人共享同一份物品属性结构，保证对称抢宝规则 |
| `loot_item_definition.gd` | 82 | 单件战利品数据（Resource）：类别、名称、描述、装备数值、消耗效果、铭文 `mod_id` 与敌方偷取载荷 `enemy_*` | 纯数据；改数值只动 `data/loot/*.tres` |

### 角色层（`scripts/battle/`）

加一名角色 = 一个 `.tres` + 技能数据，不改控制器。

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `character_definition.gd` | 70 | 角色面板、五槽位技能 id、职业资源声明 | 纯数据；`skill_ids` 按槽位顺序 |
| `character_catalog.gd` | 48 | `data/characters/*.tres` 的显式名册 | 不用目录扫描，出战名单可评审 |
| `skill_registry.gd` | 78 | 跨角色技能解析（id → 定义） | 角色只写 skill id，不关心来自哪个目录 |
| `character_skill_runtime.gd` | 200 | 唯一入口：召唤前缀、技能归属校验、自目标补齐，再按 `executor_id` 分派；`can_aim()` 与剑意入账转发到效果层 | 执行器表是唯一分派点，缺登记即 `push_error` 并返回 false |
| `combat_geometry.gd` | 138 | 纯网格查询：射程、视线、矩形与十字落点、突进落点 | 不认识角色、机制或设计数值；极意的范围加成由调用方以参数传入 |
| `skill_effects.gd` | 569 | 各技能的结算分支：樱的剑意 / 极意 / 残香 / 回锋、通用普攻、守誓者三技的包装，以及伤害分段与剑意预算的公共记账 | 只按 `executor_id` 被调用；不算格子，几何一律问 `CombatGeometry` |
| `summon_definition.gd` | 28 | 通灵数据（`data/summons/*.tres`） | 通灵属于玩家 |
| `summon_catalog.gd` | 34 | 通灵名册及 id 路由 | 内容资源显式注册 |
| `summon_service.gd` | 103 | 通灵的可用性、现身格与冷却 | 数值全部来自 `SummonDefinition` |

角色面板声明技能 id；技能目录定义玩法参数；`CharacterSkillRuntime` 按技能归属查找执行器。樱使用剑意与极意，瑟弗林使用终极能量。通灵请求经 `SummonService` 处理。

### 单位（`scripts/actors/`）

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `battle_actor.gd` | 304 | 单位身份、阵营、格位、整数血量、护盾、终极能量、承伤与阵亡状态 | 终段减伤在防御/抗性之后应用 |

### 表现层（`scripts/ui/`）

主菜单与大厅负责导航。战斗界面负责输入、镜头与渲染，战斗控制器提供状态和事件。地图界面负责显示与调度地点交互，探索、路线、行商与结算由各自组件执行。

| 模块 | 行数 | 职责 |
|---|---|---|
| `battle_fx_state.gd` | 332 | 瞬态 FX 状态：角色视觉位置/跳跃插值/受击闪烁/突进、飘字与冲击环老化、敌方分步演出计时；`snapshot()` 生成下游 board/hud 视图只读消费的字典 |
| `battle_banner_text.gd` | 49 | 状态栏文案单一来源：部署提示、教学关分步引导与回落逻辑；只读不改状态 |
| `battle_view.gd` | 598 | 编排：关卡流程、点击分发、`Q/E` 旋转视角与 `B` 键背包切换、FX/文案组件委托；另有春之境单场模式，由 `spring_battle_bridge` 注入一场遭遇，结账后回地图 |
| `board_view.gd` | 260 | 编排层：等距石板棋盘与侧棱、移动/悬停/目标提示、目标谓词 `can_target()` / `can_target_ally()`；其余绘制转发给威胁层与实体层 |
| `board_threat_view.gd` | 561 | 威胁层：敌方攻击预告（警戒斜条纹）、落点伤害标签、打击闪爆、飘字、受威压呼吸红晕，以及全家族共用的 `is_cell_in_danger()` 查询 |
| `board_objects_view.gd` | 519 | 实体层：按等距深度排序的废墟立柱、遗迹宝箱、4 向动态立绘与受击动画、地面掉落光柱、血条/充能条与头顶徽标；持有精灵纹理缓存 |
| `skill_bar_view.gd` | 167 | 底部横向 4 技能条（悬停浮窗显示完整技能说明）、结束回合按钮与操作提示；`skill_rect()` 是唯一的按钮几何，`is_affordable()` 是唯一的按钮可用判据 |
| `theme_palette.gd` | 292 | 全部颜色与坐标常量、2.5D 等距菱形投影（`80×44`）与 4 对角 90° 旋转正反算（`cell_center` / `cell_at`）、共享绘制原语（闭合折线/等距椭圆）与立绘高度常量 |
| `hud_view.gd` | 492 | 左下角主角大头头像与血条/护盾/AP/能量、顶部关名与战况、右上角敌方行动顺序与技能充能情报卡 |
| `inventory_view.gd` | 163 | `[B]` 键开关的装备与背包弹窗：展示武器槽、护甲槽、背包物品与点击穿戴/卸下/使用交互 |
| `settlement_view.gd` | 169 | 结算面板、完好遗迹宝箱开箱战利品展示、三选一肉鸽强化与其点击区；`spring=true` 时只留「返回春之境」一个出口 |
| `input_router.gd` | 74 | 触屏 / 鼠标 / 键盘 → `tap` / `skill` / `cancel` / `end_turn` / `rotate_camera` / `toggle_inventory` |
| `main_menu.gd` | 188 | 启动菜单：黄昏背景与飘浮光尘、极简悬停横条、键盘与点击选中；两个选项（进入大厅 / 退出） |
| `lobby_view.gd` | 600 | 黄昏营地大厅：看板立绘互动、未尽之春断点状态展示，以及右下角「工坊整备」「选择地图」按钮与全屏连线章节选择 |
| `atelier_prep_overlay.gd` | 271 | 黄昏补给商行界面：残晶余额、六种补给、按余额购买/退款与打包 |

### 局外工坊（`scripts/meta/`）

| 模块 | 行数 | 职责 | 关键约束 |
|---|---|---|---|
| `atelier_stash.gd` | 213 | 工坊残晶、六种配方、购买退款、出征打包和局外存档 | 独立于春之境行商和战斗战利品 |

### 共享存储与历史入口

| 模块 | 行数 | 职责 |
|---|---|---|
| `save_file.gd` | 18 | 同目录临时文件写入 JSON 并替换目标；失败保留上一个文件 |
| `spring_save_transaction.gd` | 45 | 记录两份已计算的存档并在中断后重写，恢复期间阻止其他工坊写入 |
| `main.gd` | 7 | 历史 Node2D 样例脚本；场景启动路径以 `project.godot` 为准 |

## 审计范围、发现与处理

基线为 2026-11-27 的 `eacd485`。审计覆盖场景入口和场景交接、运行脚本与资源引用、测试与 CI、版本和导出配置、磁盘写入点及工程文档。在已跟踪的 GDScript、场景及资源中扫描了固定 `res://` 引用，未发现缺失目标。运行时入口中未发现网络客户端、远程命令入口或凭据读取。测试运行器仅启动已定位的 Godot 进程。安全核查聚焦本地文件与测试隔离。

| 级别 | 位置 | 影响 | 改动与验证 |
|---|---|---|---|
| 高 | `tests/test_main_menu.gd` `_test_spring_entry_loads()` | 测试删除真实春之境存档 | 测试使用进程独立路径，真实场景首次进入与恢复均使用该路径 |
| 高 | `spring_map_view.gd` `_choose_event_option()`、`_apply_returned_battle()` | 已生效的事件、精英领奖和败北续行在重开后失去待决选择 | 待决事项进入 `SpringRun` 存档，恢复事件及待决战后选择。回归验证事件面板、待触发遭遇、精英原候选和续行状态 |
| 高 | `lobby_view.gd` `activate_map()`、`spring_map_view.gd` `start_new_run()` | 恢复旧局清空新工坊补给，首次移动前退出会丢包 | 工坊补给只由新春之境出征领用，开始时写检查点；场景回归覆盖新局、立即重开与旧局恢复 |
| 中 | `spring_run.gd` `save_to_file()`、`atelier_stash.gd` `save_state()` 与购买退款 | 覆盖中断可破坏旧档，写入失败仍报购买成功 | 共用临时文件替换，购买退款在保存后更新内存，战斗切换要求保存成功。以目录占用存档路径验证交易失败和余额不变 |
| 中 | `tests/run_suites.gd` `_run()`、`tests/run_all.ps1` | 测试异常退出和 Windows 导入失败可能误报通过 | 统一运行器核对子进程退出状态；Windows 入口保留导入输出并传播失败 |
| 中 | `board_view.gd` `_draw_grid()`、`theme_palette.gd` 投影函数 | 矩形棋盘转向 90° 后遍历出界或漏绘 | 渲染按机位使用交换后的尺寸；6×9 网格在四个机位均覆盖 54 个逻辑格 |
| 低 | `skill_effects.gd` `_apply_knockback()`、`skill_executor.gd` `_knockback_one()` | 碰撞、位移和意图同步各有两套，收敛时须保留事件与击杀记账差异 | 暂缓合并。并行战斗账本分支已修改这两处，先在账本落地后对现行分支补等价测试 |
| 低 | `ARCHITECTURE.md`、`PROJECT_STATUS.md`、`TESTER_WINDOWS_0.1.md`、`test_battle_fx_state.gd` | 入口和职责描述过时，LF 规则与已入库的 CRLF 产生假脏文件 | 架构、运行指南和测试说明已校正，FX 文件行尾统一，文档守卫检查 |
| 低 | `export_presets.cfg` `exclude_filter` | Windows 试玩包带测试脚本和源图 | 导出过滤这两个目录，核对打包清单并用生成的可执行文件无头启动 |

### 后续优化

1. **把流程从绘制脚本移到场景自己的协调层**。先从 `spring_map_view.gd` 的场景切换、自动存档和弹窗编排入手，通过信号和场景注入传递交互。继续让控制器持有战斗权威状态，渲染消费状态和事件。 [Godot 场景组织](https://docs.godotengine.org/en/stable/tutorials/best_practices/scene_organization.html)
2. **给跨文件的记账增加可恢复的事务记录**。春之境出征和战后残晶已有可重放的双存档日志。后续补齐教学出征的确认边界和旧档嵌套字段校验。 [Godot 本地文件 API](https://docs.godotengine.org/en/stable/classes/class_fileaccess.html)
3. **把相互依赖的内容按功能收拢**。从小场景与其私有脚本开始，保留共享的角色、敌人和装备 Resource 目录。素材工具的依赖锁定、资源路径与 Windows 打包冒烟可独立验证；当前没有 Android 导出配置及真机结果。 [Godot 项目组织](https://docs.godotengine.org/en/stable/tutorials/best_practices/project_organization.html)

本次代码审计不替代 Windows 人工验收。鼠标焦点、可读性、动画手感和高 DPI 行为仍按人工验收清单验证。
