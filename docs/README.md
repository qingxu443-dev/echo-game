# ECHO 文档总览

`docs/` 按**文档用途**分为六类，每类只回答一个问题。找文档先看问题，再看目录，不要按文件名猜。

| 目录 | 回答的问题 | 是否随代码更新 |
|---|---|---|
| `design/world/` | 这个世界是什么、故事怎么讲 | 缓慢演进 |
| `design/systems/` | 规则如何运转、数值如何结算 | 随设计演进 |
| `design/characters/` | 角色是谁、技能怎么设计 | 随角色迭代 |
| `design/content/` | 赛季与关卡内容如何组织 | 随内容迭代 |
| `design/art/` | 画面、色彩与角色视觉规范 | 缓慢演进 |
| `engineering/architecture/` | 代码现在怎么分层、模块边界在哪 | 随代码更新 |
| `engineering/quality/` | 改完怎么验证、覆盖下限是多少 | 随测试更新 |
| `engineering/decisions/` | 哪些已定、哪些不许擅自决定 | 随裁决更新 |
| `planning/` | 现在做到哪、下一步做什么 | 每周更新 |
| `delivery/` | 怎么打包、怎么人工验收 | 随交付流程更新 |
| `archive/` | 已被取代但需要追溯的历史 | **只读** |

## 阅读顺序（新人）

1. [`planning/PROJECT_STATUS.md`](planning/PROJECT_STATUS.md) — 当前阶段与已完成范围。
2. [`planning/TASK_PLAN.md`](planning/TASK_PLAN.md) — 带 ID、依赖与验收条件的后续任务。
3. [`engineering/architecture/ARCHITECTURE.md`](engineering/architecture/ARCHITECTURE.md) — 代码分层与逐模块职责。
4. [`design/systems/ECHO_COMBAT_SYSTEM_AND_CHARACTER_NUMERICAL_PLAN_v0.3.2_zh-CN.md`](design/systems/ECHO_COMBAT_SYSTEM_AND_CHARACTER_NUMERICAL_PLAN_v0.3.2_zh-CN.md) — 当前完整的战斗与数值主规格。
5. [`engineering/quality/BASELINE.md`](engineering/quality/BASELINE.md) — 逐套件断言与变更记录。
6. [`engineering/decisions/DECISIONS_AND_OPEN_QUESTIONS.md`](engineering/decisions/DECISIONS_AND_OPEN_QUESTIONS.md) — 已确认规则与待决问题。

## 世界观与叙事（`design/world/`）

| 文档 | 核心内容 |
|---|---|
| [`ECHO_WORLD_OVERVIEW_1.0`](design/world/ECHO_WORLD_OVERVIEW_1.0_zh-CN.md) | 世界基调、失落文明与「ECHO」这个名字的多重解释 |
| [`ECHO_OPENING_PROLOGUE_1.0`](design/world/ECHO_OPENING_PROLOGUE_1.0_zh-CN.md) | 开场五幕剧本文本、叙事约束与术语表 |

## 规则与系统（`design/systems/`）

| 文档 | 核心内容 |
|---|---|
| [`ECHO_SYSTEM_LAWS_v1.0`](design/systems/ECHO_SYSTEM_LAWS_v1.0_zh-CN.md) | 四大核心法则：既定回响、让渡律动、回声衰减、局部异象 |
| [`CORE_COMBAT_RULES_v0.1`](design/systems/CORE_COMBAT_RULES_v0.1_zh-CN.md) | 早期战斗规则：网格、AP、伤害、回合流程与不变量 |
| [`BATTLE_EVENT_TIMELINE_v0.1`](design/systems/BATTLE_EVENT_TIMELINE_v0.1_zh-CN.md) | 玩家动作、移动、攻击、敌方预告与阶段边界的事件时序 |
| [`ENEMY_AI_AND_TELEGRAPH_v0.1`](design/systems/ENEMY_AI_AND_TELEGRAPH_v0.1_zh-CN.md) | 敌方决策、意图生成、预告表现与失效规则 |
| [`ECHO_COMBAT_SYSTEM_AND_CHARACTER_NUMERICAL_PLAN_v0.3.2`](design/systems/ECHO_COMBAT_SYSTEM_AND_CHARACTER_NUMERICAL_PLAN_v0.3.2_zh-CN.md) | **当前主规格**：队伍、共享 AP、伤害管线、状态、角色与技能结构 |
| [`battle_status_system`](design/systems/battle_status_system_zh-CN.md) | 状态容器、叠层策略、生命周期与已接入状态清单 |
| [`skill_design_principles`](design/systems/skill_design_principles_zh-CN.md) | 技能与关卡的表达原则、数据要求与验收标准 |
| [`FRAGMENT_SYSTEM_AND_COMMUNICATIONS_TERMINAL_v0.1`](design/systems/FRAGMENT_SYSTEM_AND_COMMUNICATIONS_TERMINAL_v0.1_zh-CN.md) | 残片模块生成、角色构筑、通讯终端与本地奖励邮件规则 |

## 角色与技能（`design/characters/`）

| 文档 | 核心内容 |
|---|---|
| [`OATHKEEPER_V2_DESIGN_SPEC_v1.0`](design/characters/OATHKEEPER_V2_DESIGN_SPEC_v1.0_zh-CN.md) | 瑟弗林 V2：不屈誓约、裁决印记、誓盾庇护、绝对守护与结算原则 |
| [`DEST_LEE_CHARACTER_COMBAT_DESIGN_v1.0`](design/characters/DEST_LEE_CHARACTER_COMBAT_DESIGN_v1.0_zh-CN.md) | 德斯特·李：角色定位、基础面板、技能效果与战斗边界（审阅稿） |

## 赛季内容（`design/content/`）

| 文档 | 核心内容 |
|---|---|
| [`ECHO_SPRING_THAT_NEVER_FINISHED_DESIGN_SUMMARY`](design/content/ECHO_SPRING_THAT_NEVER_FINISHED_DESIGN_SUMMARY_2026-11-26.md) | 「未尽之春」赛季：五区域、双模式、资源经济、藏品与结局留白 |

## 视觉与美术（`design/art/`）

| 文档 | 核心内容 |
|---|---|
| [`ECHO_VISUAL_ART_DIRECTION_1.1`](design/art/ECHO_VISUAL_ART_DIRECTION_1.1_zh-CN.md) | 色彩体系、角色与场景设计语言、UI 与验收标准 |

## 工程架构（`engineering/architecture/`）

| 文档 | 核心内容 |
|---|---|
| [`ARCHITECTURE`](engineering/architecture/ARCHITECTURE.md) | 技术栈、场景与状态循环、逐模块索引、审计发现与优化项 |

## 质量与基线（`engineering/quality/`）

| 文档 | 核心内容 |
|---|---|
| [`BASELINE`](engineering/quality/BASELINE.md) | 逐套件断言数、CI 口径、覆盖下限与历次变更记录 |
| [`SAVE_AUDIT_2026-11-29`](engineering/quality/SAVE_AUDIT_2026-11-29.md) | 暂停保存复现、全持久化边界、邮件事务与重试修复、验证和剩余限制 |
| [`IMPLEMENTATION_DEBT_v1.0`](engineering/quality/IMPLEMENTATION_DEBT_v1.0_zh-CN.md) | 法则落地欠账：D-01 至 D-04 的现状与核对方式 |
| [`BOARD_OVERLAYS_2026-11-28`](engineering/quality/BOARD_OVERLAYS_2026-11-28.md) | 源库接续、生命结算收尾、移动逻辑检查、纯色攻击/技能区域与显隐、真实渲染和已知边界 |
| [`SINGLE_ACTIVE_PARTY_2026-11-28`](engineering/quality/SINGLE_ACTIVE_PARTY_2026-11-28.md) | 单人上场、1 AP 轮换、永久退场、状态/装备继承、真实渲染及已知问题 |
| [`PLAYTEST_FIXES_2026-11-27`](engineering/quality/PLAYTEST_FIXES_2026-11-27.md) | 七项实机问题的定位、修复与回归记录 |

## 决策记录（`engineering/decisions/`）

| 文档 | 核心内容 |
|---|---|
| [`DECISIONS_AND_OPEN_QUESTIONS`](engineering/decisions/DECISIONS_AND_OPEN_QUESTIONS.md) | 已确认基础规则、已移除机制、待决问题与待测试项 |
| [`ECHO_COMBAT_PENDING_DECISIONS_v0.3.2`](engineering/decisions/ECHO_COMBAT_PENDING_DECISIONS_v0.3.2_zh-CN.md) | 0.3.2 战斗裁决单：伤害、多段、资源、状态等逐条裁定 |
| [`CURRENT_SCOPE_AND_DECISIONS`](engineering/decisions/CURRENT_SCOPE_AND_DECISIONS.md) | 当前交付范围、旧规划对账与 ECHO-001/002/003 决策登记 |
| [`ENCOUNTER_LAW_OVERRIDES`](engineering/decisions/ENCOUNTER_LAW_OVERRIDES.md) | 关卡 K/AP 覆写的执行范围、独立样板与尚未支持的预告语义 |

## 计划与状态（`planning/`）

| 文档 | 核心内容 |
|---|---|
| [`PROJECT_STATUS`](planning/PROJECT_STATUS.md) | 当前阶段、目标范围、已完成项、验证记录与协作约定 |
| [`TASK_PLAN`](planning/TASK_PLAN.md) | ECHO-001 起的任务清单、里程碑、依赖与验收条件 |

## 交付与验收（`delivery/`）

| 文档 | 核心内容 |
|---|---|
| [`TESTER_WINDOWS_0.1`](delivery/TESTER_WINDOWS_0.1.md) | Windows 试玩包内容、启动步骤、观察项与安全边界 |
| [`WINDOWS_DELIVERY`](delivery/WINDOWS_DELIVERY.md) | 从指定提交构建 Windows 试玩包、校验值与人工交接流程 |

## 历史归档（`archive/`，只读）

| 文档 | 为什么保留 |
|---|---|
| [`README_LEGACY`](archive/README_LEGACY.md) | 2.5D 重构前的完整 README，供对照 |
| [`GODOT_ENGINE_VALIDATION`](archive/GODOT_ENGINE_VALIDATION_zh-CN.md) | 2026-11-25 首次 Godot 4.7.2 验证与缺陷记录 |
| [`sevrin_skill_kit`](archive/sevrin_skill_kit_zh-CN.md) | 瑟弗林旧版 v1 技能组设计稿 |
| [`FRAMEWORK_PROPOSAL_v1.0`](archive/FRAMEWORK_PROPOSAL_v1.0_zh-CN.md) | 重构前框架提案，已被 `ARCHITECTURE` 取代 |
| [`godot_validation_checklist`](archive/godot_validation_checklist_zh-CN.md) | 早期开发验证清单，测试命令已被 `tests/run_all.*` 取代 |

## 维护约定

合并前跑一次 `tests/run_all.sh`（Windows：`.\tests\run_all.ps1`）。下面五条里有三条
带机器守卫，红了就是真问题——按括注的处置动作修，不要靠"下次更仔细"。

- **可变数字只写一遍。** 套件数与断言数的下限只维护在 [`tests/framework/baseline.json`](../tests/framework/baseline.json)；正文只写指针（`<实际断言数>` / `floor <下限>`），不写具体值。
  - 守卫 `count-copies`：正文里出现活计数就红。处置：跑 `tests/run_all.sh --fix`，它会把 `assertions=N`、`N 条断言`、`N 个套件` 等写法统一归一成同一组占位符。
  - 为什么不能写具体值：两个分支各自把同一行改成自己的数，合并必冲突；后合并的赢，先合并的就变成撒谎。指针在每个分支上都是同一串字，git 能自动合并。
- **移动或改名要跟着改链接。** 跨目录链接的 `../` 层数最容易漏。
  - 守卫 `doc-links`：断链逐条打印「文件 -> 目标」。处置：按提示改路径，改完重跑。
- **新文档先登记再提交。** 放进哪个目录靠判断（回答哪个问题就进哪一类），登记不能靠记性。
  - 守卫 `doc-index`：`docs/` 下任何未出现在本文件目录表的 `.md` 都会红。处置：在本文件对应小节加一行「文档 + 核心内容」。
  - 仓库入口的 [`README.md`](../README.md)「文档导航」表是给人看的索引，新增对外可见的文档时一并补上。
- **归档不删除。** 失效文档移入 `archive/`，开头加一行「历史提示」，保留可追溯性。
- **链接用相对路径。** 同目录直接写文件名，跨目录用 `../`，便于整棵 `docs/` 一起移动。
