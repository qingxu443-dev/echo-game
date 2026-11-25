# 工程基线（Prototype 0.1）

本文件是重构的对照基准。**任何结构性改动后，断言总数不得低于本表，失败数必须为 0。**
数字减少即视为覆盖下降，必须说明原因并取得评审同意。

## 基线快照

| 项目 | 值 |
|---|---|
| 分支 | `main` |
| 提交 | `7f2da1c`（main，含 README 同步与系统法则 v1.0） |
| 引擎 | Godot 4.7.2 Standard |
| 平台 | Windows 10/11 x86_64 |
| 套件数 | 16 |
| 断言总数 | **623** |
| 失败数 | 0 |
| 导入错误 | 0 |

## 逐套件断言数

| 套件 | 断言 | 归属 |
|---|---:|---|
| `test_battle_controller.gd` | 162 | 控制器场景 |
| `test_oathkeeper_v2_controller.gd` | 75 | V2 技能控制器 |
| `test_turn_bookkeeping.gd` | 49 | 回合账本 |
| `test_battle_area_effects.gd` | 43 | 区域效果 |
| `test_hunter_summon.gd` | 39 | 猎人通灵 |
| `test_battle_echo_counter.gd` | 38 | 回响反击（v1 遗留） |
| `test_level_catalog.gd` | 30 | 关卡数据 |
| `test_battle_status.gd` | 25 | 状态容器 |
| `test_diagonal_line_of_sight.gd` | 24 | 视线规则 |
| `test_skill_definitions.gd` | 20 | 技能数据（v1） |
| `test_oathkeeper_v2_actor.gd` | 19 | 护盾与能量 |
| `test_core_rules.gd` | 18 | 网格/AP/伤害 |
| `test_battle_view_skills.gd` | 15 | UI 到控制器集成 |
| `test_battle_stats.gd` | 13 | 结算统计 |
| `test_oathkeeper_v2_skill_catalog.gd` | 12 | V2 技能目录 |
| `test_enemy_catalog.gd` | 41 | 敌人数据目录（M1 新增） |
| **合计** | **623** | |

## 变更记录

| 日期 | 变更 | 断言变化 |
|---|---|---|
| 2026-11-25 | M0：套件迁入公共基类，新增一键回归 | 582 → 582（不变） |
| 2026-11-25 | M1：敌人属性外置为 `.tres`，新增 `test_enemy_catalog` | 582 → 623（+41） |
| 2026-11-25 | M1：关卡外置为 `.tres`，`level_catalog.gd` 69 → 29 行 | 623 → 623（不变） |

## 如何复现

```sh
# 全部套件 + 汇总
tests/run_all.sh                       # bash
tests\run_all.bat                      # Windows 双击或 cmd

# 单个套件
godot --headless --path . --script res://tests/test_core_rules.gd
```

每个套件结束会打印一行机器可读结果：

```
RESULT test_core_rules assertions=18 failures=0
```

`run_all` 汇总 `assertions` 与 `failures`，任一非零即返回非零退出码。

## 与重构计划的关系

- `docs/FRAMEWORK_PROPOSAL_v1.0_zh-CN.md` 的 M0–M4 每一步，合并前都必须与本表对比。
- M2（拆控制器）期间**不允许修改测试文件**；若某步必须改测试，说明对外行为变了，应回退。
- v1 技能废弃会减少 `test_battle_echo_counter`、`test_skill_definitions` 以及部分 `test_battle_controller` 用例，届时本表需同步下调，并在变更说明中列出删除的用例清单。
| 2026-11-25 | 文档补全：系统法则实现状态对照、决策待办、README 文档导航 | 623 → 623（不变） |
