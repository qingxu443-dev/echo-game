# ECHO

ECHO 是一款使用 **Godot 4.7.2 Standard** 与 **GDScript** 开发的 2D 回合制战术游戏原型。

> **仓库边界**：本仓库为 ECHO 独立项目，与「拾光」项目严格隔离。请勿将「拾光」的任何代码、配置或数据合入本仓库。

---

## 项目状态

| 项目 | 当前基线 |
| :--- | :--- |
| **里程碑** | Prototype 0.1（可运行战斗切片） |
| **引擎版本** | Godot 4.7.2 Standard（**非 .NET 版本**） |
| **开发与验证平台** | Windows 10/11（64 位），目标分辨率 `1280 × 720`（横屏） |
| **移动端方向** | Android 横屏（本阶段优先完成 Windows 桌面验证，暂未验证 Android 导出） |
| **技能组版本** | **守誓者 V2**（裁决印记 / 誓盾庇护 / 绝对守护 + 被动「不屈誓约」） |
| **自动化验证** | 2026-11-25 完成 Godot 4.7.2 导入与主场景无头运行；18 个测试套件当前 **808 条断言，0 失败**（基线见 `docs/engineering/BASELINE.md`）；每次推送到 main 或开 PR 时由 GitHub Actions 在 Ubuntu 与 Windows 两个 runner 上复跑（`.github/workflows/suites.yml`） |
| **待人工验证** | Windows 桌面交互与画面表现、Android 导出与真机表现 |

---

## 快速开始（Windows）

首次运行只需 **Godot 4.7.2 Standard（Windows x86_64）**，无需 `.NET` 版本，也无需安装 Android 导出模板。

1. 下载并安装 Godot 4.7.2 Standard（Windows x86_64）。
2. 获取代码：克隆仓库，或直接[下载 `main` 分支 ZIP](https://github.com/qingxu443-dev/echo-game/archive/refs/heads/main.zip) 并完整解压至普通本地目录（[仓库主页](https://github.com/qingxu443-dev/echo-game)）。
3. 启动 Godot，在项目管理器中点击 **导入（Import）**，选择解压目录下的 `project.godot`，点击 **导入并编辑**。
4. 等待首次资源扫描完成后，按 `F5` 运行：先进入主菜单，选「开始游戏」进入第一场遭遇战。

---

## 核心战斗与系统

### 基础规则
* **战场与单位**：`8 × 8` 正交网格战场；己方单位为 **瑟弗林（守誓者）**，敌方包含 **先锋**、**神射手**、**区域术士** 三种原型。
* **行动点（AP）**：每玩家回合全队共享 `5 AP`（0.3 规划 §4）。移动消耗 `1 AP`，单次最多移动 `2` 格。
* **输出方式**：瑟弗林拥有普通攻击「誓刃」（1 AP，相邻 100% ATK），另有三个主动技能；樱拥有「穿花」与三个主动技能。
* **意图预告**：敌方意图在玩家回合开始时公开，并按固定顺序结算。
* **队伍**：瑟弗林与樱同场；`Tab` 切换当前操作角色，行动点全队共享。
* **界面支持**：支持鼠标与键盘快捷键操作，完整显示技能 AP 消耗、终极能量门槛、合法目标范围及状态标识（护盾、绝对守护、裁决印记）。

### 守誓者 V2 技能组

| 技能 | 消耗 / 冷却 | 类型 | 效果说明 |
| :--- | :--- | :--- | :--- |
| **誓刃** | `1 AP` | 相邻敌人（1 格） | 普通攻击，造成 `100% ATK` 物理伤害 |
| **裁决印记** | `1 AP` | 指向敌人（1–4 格） | 造成 `DEF × 0.8` 物理伤害，并施加「裁决印记」 |
| **誓盾庇护** | `1 AP` | 自身或 2 格内友军 | 为施法者及 `2` 格内一名友军施加 DEF 系护盾，消耗全部「守誓」层数 |
| **绝对守护** | `2 AP` + `5` 终极能量 | 自身施放 | 嘲讽敌人并触发反击 |
| **不屈誓约** | 被动 | 自动触发 | 被敌方主动攻击命中时获得 `1` 层「守誓」（上限 `3` 层） |

### 支援系统（不属于瑟弗林技能组）

| 系统 | 消耗 / 冷却 | 效果说明 |
| :--- | :--- | :--- |
| **猎人通灵** | `0 AP` / 冷却 `2` 回合 | 既有支援系统：召唤猎人现身一击 |

### 视线规则（LOS）
瑟弗林的指向技能（如「裁决印记」）要求目标与自身位于**同一行、同一列或对角直线**上，且路径无遮挡：
* 斜角相邻或对角直线方向上的目标可正常命中。
* 路径中存在地形障碍或其他单位阻挡时，判定失败。
* 非对齐偏移（例如横向差 `2`、纵向差 `1`）不存在直线路径，判定失败。

> **敌方不受此对角规则影响**：神射手仅沿正交直线开火，先锋蓄力亦仅沿正交方向——这两类正交线是玩家读懂敌方预告的核心依据。

---

## 关卡与结算

战斗按固定顺序推进，关卡数据外置在 `data/levels/*.tres`，由 `scripts/battle/level_catalog.gd` 统一加载。所有关卡的初始布阵、敌人配置与障碍布局均固定，不使用随机站位。

| 关卡 | 敌方配置 | 战术考点 |
| :--- | :--- | :--- |
| **第一课 · 蓄力** | 先锋 × 1（正前方 2 格） | 先锋锁定脚下格子蓄力，移动 1 格即可规避 |
| **第二课 · 射线** | 神射手 × 1（距离 5 格） | 神射手只在同一直线、距离 3–6 格时开火，贴太近反而打不到 |
| **第三课 · 混编** | 先锋 + 区域术士 + 神射手（带障碍） | 三种威胁叠加，考验走位与目标优先级决策 |

* **结算面板**：战斗结束后显示当前关卡、回合数、造成伤害、承受伤害、击败敌人数与剩余生命。
* **流程操作**：支持「重开本关」；胜利时提供「下一关」，通关最后一关后切换为「从头开始」。

---

## 桌面操作

| 操作 | 输入方式 |
| :--- | :--- |
| **移动** | 鼠标左键点击可到达的格子 |
| **誓刃**（普通攻击） | 点击技能按钮或按 `1`，再点击相邻敌人 |
| **裁决印记** | 点击技能按钮或按 `2`，再点击合法敌人 |
| **誓盾庇护** | 点击技能按钮或按 `3`，再点击自己或 2 格内友军 |
| **绝对守护** | 点击技能按钮，或按 `4`（需 5 点终极能量） |
| **猎人通灵** | 点击技能按钮或按 `5`，再点击合法敌人 |
| **取消目标选择** | `Esc` 或鼠标右键 |
| **结束回合** | 点击「结束回合」、`Enter` 或 `Space` |

> 数字键 `1–5` 对应技能栏顺序。未选中技能时点击敌人只会给出提示；自身技能按下即刻生效，指向技能需二次点击战场上的合法目标确认（敌方技能点敌人，誓盾庇护点自己或友军）。

---

## 自动化测试

在项目根目录的 Godot 4.7.2 Standard 环境中，使用一条命令即可运行全部测试套件并汇总结果：

```bash
# macOS / Linux / Git Bash
tests/run_all.sh

# Windows（cmd 执行或双击）
tests\run_all.bat
```

若 Windows 未将 Godot 加入 `PATH`，可通过 PowerShell 显式指定可执行文件路径：

```powershell
.\tests\run_all.ps1 -Godot "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
```

三个入口都只负责找到引擎：真正的运行与守卫在 `tests/run_suites.gd`，所以 Linux、Windows 与 CI 跑的是同一份判定。此前两个脚本各写一套等价逻辑，PowerShell 那份漏了脚本错误拦截与文档校验，Windows 上的绿灯因此比 Linux 的宽。

文档里的断言总数、以及 `ARCHITECTURE.md` 的模块行数表，由 `tests/framework/doc_checks.gd` 校验。改动导致行数变化时，用下面这条原地改写那几行，再复查：

```bash
tests/run_all.sh --fix      # PowerShell: .\tests\run_all.ps1 -Fix
```

单独运行某个测试套件：

```bash
godot --headless --path . --script res://tests/test_core_rules.gd
```

> **首次克隆提示**：克隆后必须先在 Godot 4.7.2 Standard 中导入项目（GUI 导入，或执行 `godot --headless --path . --import`）生成 `.godot` 导入缓存，再运行测试；否则依赖 `.tres` 资源的套件会因资源未导入而报「crashed or failed to parse」。

正常汇总输出示例（仅当所有套件 `failures=0` 且无崩溃时退出码为 `0`）：

```text
test_battle_controller                 118 ok
...
-----
suites=18 assertions=808 failures=0 broken=0
doc-numbers: ok (808)
module-sizes: ok (31 rows)
```

* 每个套件结束时会输出一行机器可读结果：`RESULT <名称> assertions=<n> failures=<n>`。
* 末尾三行分别是套件汇总、文档数字校验、模块行数校验；任何一项不一致都会让退出码变成 `1`。套件汇总里的断言总数必须与 `BASELINE.md` 相等——多一条也要在同一个改动里把基线抬上去。
* 当前基线为 **18 个套件、808 条断言、0 失败**，逐套件明细与当前基线提交见 `docs/engineering/BASELINE.md`。
* 任何代码改动均应重跑测试并以零失败为合并前提；无头测试不能替代 `F5` 主场景的交互与画面人工检查。

---

## 当前原型边界

以下内容明确不属于 Prototype 0.1 范围：
* **流程与菜单**：启动进入标题菜单（开始 / 退出），暂无选关界面（仅通过结算面板切关）；菜单里的「选择存档」与「设置」只是占位。
* **美术表现**：当前界面为功能原型表现，非最终美术资产。
* **外围系统**：伙伴独立行动、章节流程、局外成长、经济系统与存档机制。
* **数值状态**：所有技能与敌人数值仍为原型基线，待实机对局持续验证。

---

## 文档导航

`docs/` 分 `design/`（设计规范）、`engineering/`（工程基准）、`archive/`（只读历史）三层，判断标准与阅读顺序见 [`docs/README.md`](docs/README.md)。

| 分组 | 文档 | 说明 |
|---|---|---|
| **世界观与美术** | [`ECHO_WORLD_OVERVIEW_1.0`](docs/design/ECHO_WORLD_OVERVIEW_1.0_zh-CN.md)、[`ECHO_OPENING_PROLOGUE_1.0`](docs/design/ECHO_OPENING_PROLOGUE_1.0_zh-CN.md)、[`ECHO_VISUAL_ART_DIRECTION_1.1`](docs/design/ECHO_VISUAL_ART_DIRECTION_1.1_zh-CN.md) | 氛围、叙事与美术参考，**不产出世界规则** |
| **机制与法则** | [`ECHO_SYSTEM_LAWS_v1.0`](docs/design/ECHO_SYSTEM_LAWS_v1.0_zh-CN.md)（Draft）、[`CORE_COMBAT_RULES_v0.1`](docs/design/CORE_COMBAT_RULES_v0.1_zh-CN.md)、[`BATTLE_EVENT_TIMELINE_v0.1`](docs/design/BATTLE_EVENT_TIMELINE_v0.1_zh-CN.md)、[`ENEMY_AI_AND_TELEGRAPH_v0.1`](docs/design/ENEMY_AI_AND_TELEGRAPH_v0.1_zh-CN.md) | 世界法则与机制解释；冲突时以系统法则为准 |
| **角色与技能** | [`OATHKEEPER_V2_DESIGN_SPEC_v1.0`](docs/design/OATHKEEPER_V2_DESIGN_SPEC_v1.0_zh-CN.md)、[`skill_design_principles`](docs/design/skill_design_principles_zh-CN.md)、[`sevrin_skill_kit`](docs/archive/sevrin_skill_kit_zh-CN.md)（历史版本） | 当前技能结构以 V2 规范为准 |
| **数值与状态** | [`combat_stats`](docs/design/combat_stats_zh-CN.md)、[`battle_status_system`](docs/design/battle_status_system_zh-CN.md) | 伤害公式、抗性与状态系统 |
| **工程** | [`ARCHITECTURE`](docs/engineering/ARCHITECTURE.md)、[`PROJECT_STATUS`](docs/engineering/PROJECT_STATUS.md)、[`DECISIONS_AND_OPEN_QUESTIONS`](docs/engineering/DECISIONS_AND_OPEN_QUESTIONS.md)、[`FRAMEWORK_PROPOSAL_v1.0`](docs/engineering/FRAMEWORK_PROPOSAL_v1.0_zh-CN.md)、[`engineering/BASELINE`](docs/engineering/BASELINE.md) | 模块边界、进度、待决事项、重构方案与测试基线 |
| **验证** | [`GODOT_ENGINE_VALIDATION`](docs/archive/GODOT_ENGINE_VALIDATION_zh-CN.md)（历史）、[`TESTER_WINDOWS_0.1`](docs/engineering/TESTER_WINDOWS_0.1.md)、[`godot_validation_checklist`](docs/engineering/godot_validation_checklist_zh-CN.md) | 引擎验证记录与人工验证指引 |

## 仓库结构

```text
├── assets/ui/summons/   # 余泡泡召唤图标
├── data/
│   ├── enemies/         # 三种敌人的属性配置（.tres）
│   └── levels/          # 三关的固定配置（.tres）
├── docs/                # 设计规范、项目状态与验证清单
├── scenes/main/         # 主入口场景
├── scripts/
│   ├── actors/          # 战斗单位数据
│   ├── battle/          # 战斗规则、技能效果、意图与状态系统、关卡加载器
│   └── ui/              # 原型战斗界面
└── tests/               # 规则、控制器、技能效果、关卡数据与 UI 集成测试
```
