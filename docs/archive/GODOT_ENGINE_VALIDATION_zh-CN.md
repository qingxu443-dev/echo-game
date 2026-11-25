# ECHO — Godot 引擎验证记录

本文件记录 ECHO 在真实 Godot 引擎中的验证结果，用来替代此前长期挂账的「静态审查通过、未在引擎执行」状态。

## 2026-11-25 — Godot 4.7.2 首次完整验证

### 环境

| 项目 | 值 |
|---|---|
| 引擎 | Godot `4.7.2.stable.official.ed1daf0bf` |
| 平台 | Linux x86_64（headless） |
| 分支 | `prototype/0.1`，HEAD `dbfbbeb` |
| 依据 | 根目录 `README.md` 的「自动化测试」章节 |

Windows 桌面导入与交互验证仍待执行，见文末「未覆盖部分」。

### 版本对应关系

本文件记录了两轮运行，结论对应关系如下，后续引用请以完整 SHA 为准：

| 运行 | 源码版本 | 结果 |
|---|---|---|
| 首次（修复前） | `dbfbbeb` | 导入失败，`battle_view.gd` 解析错误，六个套件无法加载 |
| 修复后 | `dbfbbeb` + 修复提交 `9725756` | 导入零错误，300 条断言 0 失败 |
| **合并后复验** | `prototype/0.1` @ **`906d585`**（PR #2 合并提交） | **全新克隆，导入零错误，六个套件 300 条断言 0 失败，主场景无头运行 120 帧无错误** |

因此「300 条断言 / 0 失败」这一结论对应的最终源码版本是 **`906d585`**，不是修复前的 `dbfbbeb`。

### 一、发现并修复的阻塞缺陷

`scripts/ui/battle_view.gd` 中 `_on_skill_pressed` 的**函数体完整存在，但 `func` 定义头缺失**。

导入时的原始输出：

```
SCRIPT ERROR: Parse Error: Function "_on_skill_pressed()" not found in base self.
          at: GDScript::reload (res://scripts/ui/battle_view.gd:295)   [共 7 处调用点]
SCRIPT ERROR: Parse Error: Identifier "index" not declared in the current scope.
          at: GDScript::reload (res://scripts/ui/battle_view.gd:359)   [共 4 处]
ERROR: Failed to load script "res://scripts/ui/battle_view.gd" with error "Parse error".
```

影响分两层：

1. 所有调用点（数字键 `1`–`6`、技能栏点击）无法解析到该函数，产生 7 处解析错误；
2. 函数体失去作用域后，`index` 成为未声明标识符，另产生 4 处解析错误。

由于主场景脚本加载失败，任何依赖场景的验证都无法进行。这是项目此前长期停留在「静态审查」阶段的直接原因。

修复为补回一行函数签名，函数体逻辑未作改动：

```diff
 	queue_redraw()
 
 
+func _on_skill_pressed(index: int) -> void:
 	if index < 0 or index >= SKILL_BAR.size():
```

### 二、修复后的结果

| 步骤 | 命令 | 结果 |
|---|---|---|
| 项目导入 | `godot --headless --path . --import` | 通过，零错误 |
| 主场景运行 | `godot --headless --path . --quit-after 120` | 运行 120 帧，无运行时错误 |
| 六个测试套件 | 见下表 | 300 条断言，0 失败 |

| 测试脚本 | 断言数 | 失败 |
|---|---|---|
| `test_core_rules.gd` | 18 | 0 |
| `test_battle_status.gd` | 25 | 0 |
| `test_battle_area_effects.gd` | 43 | 0 |
| `test_battle_echo_counter.gd` | 38 | 0 |
| `test_battle_controller.gd` | 162 | 0 |
| `test_battle_view_skills.gd` | 14 | 0 |
| **合计** | **300** | **0** |

### 三、本次实际覆盖到的规则

- **网格与 AP**：正交一步/两步合法，斜向与三格拒绝，阻挡格与占用格拒绝；AP 上限、单次消耗、不足时不改写预算、结束回合清零、新回合重置。
- **伤害结算**：物理走防御、法术走法抗、抗性递减、技能倍率、致死截断、阵亡后不再受伤。
- **意图与预告**：距离 2 的敌人选择蓄力；蓄力锁定格而非锁定人；玩家移开后不追踪；空格取消；追击最多两格。
- **状态系统**：一次性触发、触发消耗、栈策略（additive / refresh）、阶段边界过期、裁决印记延迟一个敌方阶段。
- **守望壁垒**：五格十字、按队伍而非固定 ID 保护、命中时判定进出区域、20% 减伤、下一玩家阶段失效。
- **誓盾与回响**：35% 终段减伤、被公开意图命中后产出回响、回响反击 0.8× 且不递归、带印记时 1.0×。
- **UI 集成**：数字键激活技能、鼠标按钮施放、右键取消选目标、印记选中与确认、誓约裁断打断意图、三 AP 连续技。

### 四、未覆盖部分

以下项目无法在 headless 环境完成，仍需人工验证：

| 项目 | 原因 |
|---|---|
| Windows 端 F5 交互手感 | 需要真实鼠标、键盘与窗口 |
| 画面观感（布局、可读性、配色） | headless 不渲染画面 |
| Android 导出与真机表现 | 未安装导出模板，无设备 |
| 技能数值手感 | 属于「待实际对局验证的原型基线」，需人实际试玩 |

### 五、复现命令

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script res://tests/test_core_rules.gd
godot --headless --path . --script res://tests/test_battle_status.gd
godot --headless --path . --script res://tests/test_battle_area_effects.gd
godot --headless --path . --script res://tests/test_battle_echo_counter.gd
godot --headless --path . --script res://tests/test_battle_controller.gd
godot --headless --path . --script res://tests/test_battle_view_skills.gd
```

---

## 2026-11-25 补记 — 套件扩充与猎人通灵

上面第一至第五节记录的是 `906d585` 那一次运行，六个套件共 300 条断言，内容保持原样不改。本节记录此后新增的覆盖。

### 新增与补齐

| 套件 | 断言 | 说明 |
|---|---|---|
| `test_turn_bookkeeping.gd` | 49 | **新增**。覆盖此前零测试的回合账本基础函数 |
| `test_skill_definitions.gd` | 20 | **补齐**。该套件一直存在并持续通过，但此前未列入复现命令，也未计入总数 |
| `test_hunter_summon.gd` | 39 | **新增**。覆盖猎人通灵技，见下文 |

`test_turn_bookkeeping.gd` 覆盖的四组行为：

- **AP 账本**：初始满额、零成本放行、负成本拒绝、正好用完、超额拒绝；**扣减失败时账本不变**；部分扣减保留余额；`clear` 清空后零成本仍放行、正成本拒绝；`reset` 回到上限；负数上限被钳制为 0。
- **意图状态机**：新意图为 `ACTIVE`；`cancel` 成功后记录原因并进入 `CANCELED`；**重复 cancel 被拒且不覆盖首个原因**；`CANCELED` 不能转 `RESOLVED`；`RESOLVED` 不能重复标记、不能撤销为 `CANCELED`；被拒的转换不改变状态。
- **区域效果清理**：空集合清理返回 0；清理返回实际移除数量；清理后不可再取回；**重复清理幂等**。
- **占格查询**：存活单位各自占格；排除指定单位只移除其自身条目；空位不上报；**阵亡单位立即让出格子**，存活单位不受影响。

### 猎人通灵技

猎人不作为战场单位存在，而是一个通灵技：施放后出现在目标身旁、完成一次突袭即离场，不消耗行动点，两回合冷却。

`test_hunter_summon.gd` 覆盖的行为：

- **代价**：施放前后行动点不变；不生成单位、不占格、不进入敌方行动顺序
- **冷却**：首次可用 → 使用后剩余 2 → 下一回合剩余 1 仍不可用 → 再下一回合归零、恢复可用
- **被拒的施放**：冷却期间、目标非敌人、目标阵亡、四周无空位，四种情况均不造成伤害、不重启冷却
- **伤害**：原始伤害 1260（攻击 1400 × 倍率 0.9），对防御 700 的近战先锋实际造成 741
- **与其他系统**：击杀最后一个敌人时正确触发胜利，战斗结束后不可再用

数值为原型基线，待实际对局调整。

### 当前总数

九个套件，共 **408 条断言，0 失败**。命令见 `README.md` 的「自动化测试」章节，两个此前遗漏的套件已一并列入。

### 本次同时做的两处清理

- 删除 `BattleStatusCollection.get_status_count`：全仓库零调用（生产代码与测试均为 0），属死代码。
- `BattleController.ap` 补上 `APBudget` 类型标注，此前为无类型 `var`，是唯一未标注类型的公开成员。

两处均不改变运行时行为，既有断言全部继续通过，未出现回归。
