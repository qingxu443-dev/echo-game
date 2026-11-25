# 工程基线（Prototype 0.1）

本文件是重构的对照基准。**任何结构性改动后，断言总数不得低于本表，失败数必须为 0。**
数字减少即视为覆盖下降，必须说明原因并取得评审同意。

## 基线快照

| 项目 | 值 |
|---|---|
| 分支 | `main` |
| 提交 | `e0ba84d`（main，M3 合并后）+ v1 移除分支 |
| 引擎 | Godot 4.7.2 Standard |
| 平台 | Windows 10/11 x86_64 |
| 套件数 | 13 |
| 断言总数 | **483** |
| 失败数 | 0 |
| 导入错误 | 0 |

## 逐套件断言数

| 套件 | 断言 | 归属 |
|---|---:|---|
| `test_battle_controller.gd` | 115 | 控制器场景 |
| `test_oathkeeper_v2_controller.gd` | 87 | V2 技能控制器 |
| `test_turn_bookkeeping.gd` | 44 | 回合账本 |
| `test_enemy_catalog.gd` | 41 | 敌人数据目录（M1） |
| `test_hunter_summon.gd` | 39 | 猎人通灵 |
| `test_level_catalog.gd` | 30 | 关卡数据 |
| `test_battle_status.gd` | 25 | 状态容器 |
| `test_diagonal_line_of_sight.gd` | 20 | 视线规则 |
| `test_battle_view_skills.gd` | 20 | UI 到控制器集成（含目标提示一致性） |
| `test_oathkeeper_v2_actor.gd` | 19 | 护盾与能量 |
| `test_core_rules.gd` | 18 | 网格 / AP / 伤害 |
| `test_battle_stats.gd` | 13 | 结算统计 |
| `test_oathkeeper_v2_skill_catalog.gd` | 12 | V2 技能目录 |
| **合计** | **483** | |

## 变更记录

| 日期 | 变更 | 断言变化 |
|---|---|---|
| 2026-11-25 | M0：套件迁入公共基类，新增一键回归 | 582 → 582（不变） |
| 2026-11-25 | M1：敌人属性外置为 `.tres`，新增 `test_enemy_catalog` | 582 → 623（+41） |
| 2026-11-25 | M1：关卡外置为 `.tres`，`level_catalog.gd` 69 → 29 行 | 623 → 623（不变） |
| 2026-11-25 | M2：控制器拆为门面 + 6 个子系统，936 → 230 行；测试文件零改动 | 623 → 623（不变） |
| 2026-11-25 | 文档补全：系统法则实现状态对照、决策待办、README 文档导航 | 623 → 623（不变） |
| 2026-11-25 | 修复通灵目标提示与绝对守护 AP 退还；补 5 条提示一致性断言 | 623 → 628（+5） |
| 2026-11-25 | 审计修复批：`damage_pipeline` 命中判据统一为 `was_hit`；`intent_resolver` 近战嘲讽半径与 actor 锁定追踪语义对齐；新增绝对守护真实敌方阶段端到端测试（+8）、护盾全吸收语义测试（+11）、近战距离重定向测试（+4）、AP 退款账本测试（+3） | 628 → 654（+26） |
| 2026-11-25 | M3：界面拆为 6 个视图 + 调色板，625 → 编排层；像素级零差异 | 654 → 654（不变） |
| 2026-11-25 | **移除 v1 技能组及其独占子系统**（区域效果、回响反击、誓盾架势、印记破绽），删除 3 个套件 | 654 → 483（**−171，已批准**） |
| 2026-11-25 | M4：`docs/` 分 design / engineering / archive 三层，21 篇文档全部就位，0 断链 | 483 → 483（不变） |

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

- `docs/engineering/FRAMEWORK_PROPOSAL_v1.0_zh-CN.md` 的 M0–M4 每一步，合并前都必须与本表对比。
- M2（拆控制器）期间**不允许修改测试文件**；若某步必须改测试，说明对外行为变了，应回退。
- v1 技能废弃会减少 `test_battle_echo_counter`、`test_skill_definitions` 以及部分 `test_battle_controller` 用例，届时本表需同步下调，并在变更说明中列出删除的用例清单。

## 例外记录：654 → 483

本表开头写着「断言总数不得低于本表」。v1 移除是本项目第一次**主动下调**，记录在此以便追溯。

**为什么不是覆盖下降**：减少的 171 条断言覆盖的是被删除的机制本身，不是仍然存在的代码路径。

| 删除项 | 断言 | 原因 |
|---|---:|---|
| `test_battle_area_effects.gd`（整份） | 43 | 区域效果的唯一生产者是 v1 守望壁垒，技能删除后无任何代码能创建区域效果 |
| `test_battle_echo_counter.gd`（整份） | 38 | 回响反击的唯一生产者是 v1 回响反击，状态不再被施加 |
| `test_skill_definitions.gd`（整份） | 20 | 测试的是 v1 技能目录本身 |
| `test_battle_controller` 的 v1 段落 | 47 | 誓盾架势减伤、v1 裁决印记、破绽、断誓、印记附着预告 |
| `test_turn_bookkeeping` 的区域效果清理 | 8 | 同第一项 |
| `test_diagonal_line_of_sight` 的断誓段 | 4 | 断誓技能删除 |

**保留并迁移的部分**：视线、AP、伤害、状态容器、敌人数据、关卡数据、通灵、V2 技能、界面集成全部改为走 V2 入口，断言数与删除前一致或仅因机制消失而减少，没有静默丢覆盖。

**如果以后重启这些机制**，需要按 V2 设计规范重新实现并补回对应测试，而不是从本文件的旧版本恢复。
