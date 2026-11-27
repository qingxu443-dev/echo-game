# ECHO

ECHO 是一款使用 **Godot 4.7.2 Standard** 与 **GDScript** 开发的 **2.5D 回合制战术 Roguelite** 游戏。

> **历史文档归档**：早期 Prototype 0.1 / 0.3 阶段的旧版 README 已完整归档于 [`docs/archive/README_LEGACY.md`](docs/archive/README_LEGACY.md)。

---

## 当前可玩内容

### 暂停、继续旅程与场景过渡

- 教学战斗、春之境战斗与地图探索均可按 **Esc** 或点击右上角 **暂停**。暂停期间冻结回合结算、动画与困难路线自动行进。
- 暂停菜单提供 **继续 / 保存并退出 / 退出 / 开关音乐 / 开关音效 / 关于**。这里的 **退出是返回标题界面**，确认后不保存当前暂停位置；已有自动存档保留。关闭程序请使用标题页的「退出游戏」。
- **保存并退出**保存当前部署、玩家/敌方回合、AP、生命、状态、装备、待执行意图与地图进度，然后返回标题，可立即选择 **继续旅程**。保存失败会留在暂停界面。成功恢复后消费该断点，避免重复结算奖励；既有春之境自动存档继续保留。
- 音乐与音效独立开关并持久保存。包含项目原创的循环氛围音乐、界面提示和战斗音效，可用 `python tools/generate_pause_audio.py` 重新生成。
- 游戏启动、进入大厅/地图/战斗及教学切关使用金色回声纹样与暗色淡入淡出。过渡期间拦截操作，避免连点重复进入场景。

使用 Godot 4.7.2 Standard 打开 `project.godot` 按 `F5` 即可直接实机试玩完整闭环：

### 1. 黄昏工坊大厅与「黄昏补给商行」
* **黄昏工坊大厅**：开局进入黄昏工坊场景，支持点击右侧路线图选择模式（**教学遗迹** / **未尽之春**，以及后续章节占位）。
* **黄昏补给商行（局外道具系统）**：战斗胜利与战败保底均会产出**工坊残晶**（持久化于 `user://atelier_stash.json`）。出发前可在补给商行不限量购入 6 种战术补给带入局内，出征前支持随时全额退还：
  * **黄昏疗伤药**（回复 1000 生命）、**回声沙漏**（本回合 +1 AP 且不涨敌方充能）、**誓约护符**（+650 护盾与 +1 能量）；
  * **破甲爆弹**（全敌 -1 层重甲并造成 350 真伤）、**镇定香囊**（清空全场敌方近战容忍度并降低 1 格技能充能）、**瞬影樱符**（+2 剑意或能量并获得 450 护盾）。

### 2. 「未尽之春」赛季模式（春之境完整一局）
* **5×5 地图探索**：3 套固定结构模板，每套 11 个地点（4 场普通战、1 场精英、1 名 Boss、3 个固定事件、1 个随机事件、1 家春日行商）及 0–1 个隐藏地点；探索消耗 **10 点体力**（按曼哈顿距离扣除）。
* **20 个敌方遭遇定义**：包含 12 场普通战、5 场精英战与 3 名 Boss（**凋樱剑主** / **千枝神将** / **春痕回响**）。三套地图的主路线共引用其中 18 个，主控角色为**樱**。
* **事件、行商与本局存档**：10 个可交互事件与隐秘之地、春日行商三页交易与刷新、战败续行机制；本局进度持久化于 `user://spring_run.json`，恢复不重抽。
* **Boss 楼层推进**：Boss 胜利后结束春之境；后续区域必须同时满足持久解锁与场景存在才允许交接。当前夏之境场景尚未交付，即使已解锁也会安全结束，不会跳转到不存在的场景。

### 3. 教学遗迹（3 关快速上手）
* 由主控角色**瑟弗林**引导完成三课教学（`蓄力规避` → `射线走位` → `多敌混编`），用于快速掌握移动、位移击退、视线与敌方充能节奏。

---

## 核心战斗与视觉系统

### 1. 2.5D 等距战场与清晰预告体系
* **四对角旋转视角**：8×8 立体石板棋盘，按 **`Q / E`** 90° 旋转 4 个机位，点击坐标、立绘 4 向朝向与攻击预告同步旋转。
* **高辨识度分色预告**：
  * **翡翠绿**＝己方可移动安全格；**银白虚线箭头**＝敌方移动/冲锋路径；
  * **正红**＝近战/蓄力/突袭区；**宝蓝**＝远程狙击/锁命区；**品紫**＝法术脉冲区。
* **悬停聚焦 & 零遮挡受击明细**：
  * 鼠标悬停任意敌人或危险格时，聚焦目标路线与攻击区；无关危险格仍保留可见填色与独立边线；
  * 棋盘格子仅保留单行极简伤害芯片，**左下角主角血条正上方**自动展开受击汇总与逐条招式明细（含 `[致死!]` 提示）；
  * 敌人头顶标出出手顺序 `①②③`，敌方回合逐怪高亮并飘出招式名。

### 2. 紧迫 `3 AP` 博弈与战术机制
* **AP 联动敌方技能充能**：每回合 `3 AP`；玩家每消耗 `1 AP`，存活敌人的技能充能条实时 `+1`，满 `3/3` 释放招牌技。
* **高交互敌方 AI 与阵型**：支持远程 8 向风筝与掩体探头、近战协同防卡位与拦路截击，多怪自动组成 **雁行护射阵 / 鹤翼合围阵 / 天罗火网阵**。
* **强敌深度博弈机制**：
  * **近战容忍反击**：精英与 Boss 同一回合连续承受 `2` 次近战攻击会立刻触发反击（远程不累计、回合结束清空），`1/2` 时头顶与瞄准均高亮预警；
  * **Boss 重甲、破甲与二阶段**：Boss 拥有 2 层重甲（重击/大招/拆毁结界/破甲爆弹可碎甲并进入易伤）、50% 血量进入狂暴并召唤护卫、第 2 回合起具备双动连击；击杀敌方单位返还 `+1 AP`（每回合最多 2 次）；
  * **可击破春之结界**：千枝神将两侧的结界节点可直接被攻击技能选中与击破，每拆毁 1 座永久降低 Boss 80 防御并碎 1 层重甲。

### 3. 双角色与遗迹宝箱肉鸽循环
* **樱（未尽之春主控）**：`穿花` / `流风`（直线 2 格突进打断蓄势） / `落英`（3×2 三段扇面） / `无尽芳华`（十字四段斩），通过被动「花信」积攒剑意触发「极意」强化与残香追击。
* **瑟弗林（教学遗迹主控）**：`誓刃`（击退 1 格并平移敌方攻击区、撞墙/撞怪附加真伤） / `裁决印记`（1–4 格直线/斜线易伤） / `誓盾庇护`（护盾 + 守誓层数） / `绝对裁决`（八方向重击击退）。
* **对称遗迹宝箱与装备背包（`[B]`）**：宝箱保护至通关自动收入背包；若被怪拆毁，怪物会直接穿戴或使用其中物品（击败后仅掉落武器/护甲）。宝箱按当前上阵角色自动过滤专属技能铭文，不会开出其他角色的技能，也不会重复掉落同一铭文。

---

## 快速开始与桌面操作

### 运行项目（Windows / macOS / Linux）
1. 安装 **Godot 4.7.2 Standard**（无需 `.NET` 版本）。
2. 克隆仓库或[下载 `main` 分支 ZIP](https://github.com/qingxu443-dev/echo-game/archive/refs/heads/main.zip) 并解压。
3. 在 Godot 项目管理器导入 `project.godot`，等待首次资源扫描完成后按 **`F5`** 运行。

### 战斗快捷键
| 操作 | 输入方式 |
| :--- | :--- |
| **移动** | 左键点击高亮绿色格子（单次最多 2 格） |
| **施放技能** | 点击底部技能槽或按数字键 `1–4`，再点击合法目标；樱的落英可点空地 |
| **旋转镜头** | `Q`（逆时针） / `E`（顺时针） |
| **装备与背包** | `B` 键开关（随时穿卸装备、激活铭文或使用补给道具） |
| **取消选择 / 暂停** | 鼠标右键取消选择；`Esc` 打开暂停菜单 |
| **结束回合** | 点击右下角「结束回合」、`Enter` 或 `Space` |

---

## 打包 Windows 试玩包

仓库已内置 Windows Desktop 导出预设（单文件内嵌资源 exe，排除测试、素材源图、工具与文档）。Windows 工程交接使用以下入口，自动导入、全量回归、导出、包体检查与 exe 无界面启动：

```powershell
python tools/fetch_windows_template.py
./tools/build_windows.ps1 -Godot 'C:/Godot/Godot_v4.7.2-stable_win64_console.exe'
```

产物在 `build/windows/`，含 ZIP、exe、来源提交/校验值、资源清单、日志和测试者说明。构建复现与待人工验收表见 [Windows 交接](docs/delivery/WINDOWS_DELIVERY.md)，初次运行见 [测试说明](docs/delivery/TESTER_WINDOWS_0.1.md)。Windows 实机验收交由人工，Android 暂缓。`build/` 为本地产物目录，不入库。

---

## 自动化测试与工程守卫

基线是**覆盖下限**，由 [`tests/framework/baseline.json`](tests/framework/baseline.json) 单独声明；当前套件数与断言数以运行输出为准，逐套件明细见 [`docs/engineering/quality/BASELINE.md`](docs/engineering/quality/BASELINE.md)。新增测试不需要改任何共享文档。

```bash
# macOS / Linux / Git Bash
tests/run_all.sh

# Windows（cmd 或 PowerShell）
tests\run_all.bat
.\tests\run_all.ps1 -Godot "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
```

模块行数变动时可用 `--fix` 原地同步 `docs/engineering/architecture/ARCHITECTURE.md`：

```bash
tests/run_all.sh --fix      # PowerShell: .\tests\run_all.ps1 -Fix
```

正常通过示例（退出码 `0`）：

```text
suites=<实际套件数> assertions=<实际断言数> failures=0 broken=0
doc-numbers: ok (floor <下限>)
doc-suites: ok (floor <下限>)
count-copies: ok (pointers only)
module-sizes: ok (no copied line counts; module-lines enforces the limit)
module-lines: ok (limit 600)
table-shape: ok
field-readers: ok
contracts: ok
doc-links: ok
doc-index: ok
```

---

## 文档导航

实机缺陷定位与回归结果见 [实机修复记录](docs/engineering/quality/PLAYTEST_FIXES_2026-11-27.md)。

`docs/` 按用途分为 `design/`（世界观 / 规则 / 角色 / 内容 / 美术）、`engineering/`（架构 / 质量 / 决策）、`planning/`（状态 / 任务）、`delivery/`（验收）与 `archive/`（只读历史）。完整目录说明与逐篇摘要见 [`docs/README.md`](docs/README.md)。

| 分组 | 文档 |
| :--- | :--- |
| **世界观与美术** | [`ECHO_WORLD_OVERVIEW_1.0`](docs/design/world/ECHO_WORLD_OVERVIEW_1.0_zh-CN.md)、[`ECHO_OPENING_PROLOGUE_1.0`](docs/design/world/ECHO_OPENING_PROLOGUE_1.0_zh-CN.md)、[`ECHO_VISUAL_ART_DIRECTION_1.1`](docs/design/art/ECHO_VISUAL_ART_DIRECTION_1.1_zh-CN.md) |
| **机制与法则** | [`ECHO_SYSTEM_LAWS_v1.0`](docs/design/systems/ECHO_SYSTEM_LAWS_v1.0_zh-CN.md)、[`CORE_COMBAT_RULES_v0.1`](docs/design/systems/CORE_COMBAT_RULES_v0.1_zh-CN.md)、[`BATTLE_EVENT_TIMELINE_v0.1`](docs/design/systems/BATTLE_EVENT_TIMELINE_v0.1_zh-CN.md)、[`ENEMY_AI_AND_TELEGRAPH_v0.1`](docs/design/systems/ENEMY_AI_AND_TELEGRAPH_v0.1_zh-CN.md) |
| **角色与数值** | [`OATHKEEPER_V2_DESIGN_SPEC_v1.0`](docs/design/characters/OATHKEEPER_V2_DESIGN_SPEC_v1.0_zh-CN.md)、[`数值主规格`](docs/design/systems/ECHO_COMBAT_SYSTEM_AND_CHARACTER_NUMERICAL_PLAN_v0.3.2_zh-CN.md)、[`skill_design_principles`](docs/design/systems/skill_design_principles_zh-CN.md)、[`battle_status_system`](docs/design/systems/battle_status_system_zh-CN.md) |
| **赛季内容** | [`未尽之春设计汇总`](docs/design/content/ECHO_SPRING_THAT_NEVER_FINISHED_DESIGN_SUMMARY_2026-11-26.md) |
| **工程与基线** | [`ARCHITECTURE`](docs/engineering/architecture/ARCHITECTURE.md)、[`BASELINE`](docs/engineering/quality/BASELINE.md)、[`DECISIONS_AND_OPEN_QUESTIONS`](docs/engineering/decisions/DECISIONS_AND_OPEN_QUESTIONS.md) |
| **计划与交付** | [`PROJECT_STATUS`](docs/planning/PROJECT_STATUS.md)、[`TASK_PLAN`](docs/planning/TASK_PLAN.md)、[`TESTER_WINDOWS_0.1`](docs/delivery/TESTER_WINDOWS_0.1.md)、[`WINDOWS_DELIVERY`](docs/delivery/WINDOWS_DELIVERY.md) |
| **历史归档** | [`README_LEGACY`](docs/archive/README_LEGACY.md)、[`sevrin_skill_kit`](docs/archive/sevrin_skill_kit_zh-CN.md)、[`GODOT_ENGINE_VALIDATION`](docs/archive/GODOT_ENGINE_VALIDATION_zh-CN.md) |

## 仓库结构

```text
├── assets/              # 2.5D 角色与怪物立绘、大头头像、大厅背景与 UI 图标
├── data/
│   ├── characters/      # 可玩角色档案（sevrin / sakura）
│   ├── enemies/         # 敌人与 Boss 档案（.tres）
│   ├── levels/          # 教学关卡配置（.tres）
│   └── loot/            # 武器、护甲、道具与角色铭文配置（.tres）
├── docs/                # design / engineering / planning / delivery / archive
├── scenes/              # 主菜单、工坊大厅、春之境地图与战斗场景
├── scripts/
│   ├── actors/          # 战斗单位与状态模型
│   ├── battle/          # 战斗规则、技能、AI 意图、战术博弈与掉落系统
│   ├── meta/            # 黄昏补给商行残晶存档与局外配置
│   ├── spring/          # 未尽之春地图、事件、行商、遭遇与本局存档
│   └── ui/              # 2.5D 棋盘视图、预告层、HUD、商店与大厅界面
└── tests/               # 自动化测试套件与文档/规范守卫
```
