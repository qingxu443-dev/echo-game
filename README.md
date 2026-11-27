# ECHO

ECHO 是一款使用 **Godot 4.7.2 Standard** 与 **GDScript** 开发的 **2.5D 回合制战术 Roguelite** 游戏。

> **历史文档归档**：早期 Prototype 0.1 / 0.3 阶段的旧版 README 已完整归档于 [`docs/archive/README_LEGACY.md`](docs/archive/README_LEGACY.md)。

---

## 当前可玩内容

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
  * 鼠标悬停任意敌人或危险格时，自动压暗无关预告并聚焦目标路线与攻击区；
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
| **施放技能** | 点击底部技能槽或按数字键 `1–4`，再点击目标敌人或结界节点 |
| **旋转镜头** | `Q`（逆时针） / `E`（顺时针） |
| **装备与背包** | `B` 键开关（随时穿卸装备、激活铭文或使用补给道具） |
| **取消选择** | `Esc` 或鼠标右键 |
| **结束回合** | 点击右下角「结束回合」、`Enter` 或 `Space` |

---

## 打包 Windows 试玩包

仓库已内置 Windows Desktop 导出预设（`export_presets.cfg`：单文件内嵌资源 exe，排除测试脚本及素材源图）。本机装有 4.7.2 导出模板后执行：

```sh
mkdir -p build
godot --headless --path . --export-release "Windows Desktop" build/ECHO_Windows_x64.exe
```

测试交付规范见 [`docs/engineering/TESTER_WINDOWS_0.1.md`](docs/engineering/TESTER_WINDOWS_0.1.md)。`build/` 为本地产物目录，不入库。

---

## 自动化测试与工程守卫

本分支预期基线为 **37 个套件、2659 条断言**；区域推进改动整合后，Ubuntu 与 Windows 双端 CI 待复验（明细见 [`docs/engineering/BASELINE.md`](docs/engineering/BASELINE.md)）。首次克隆需先执行一次 `godot --headless --path . --import` 生成资源缓存，随后一条命令运行全部套件与 7 项守卫：

```bash
# macOS / Linux / Git Bash
tests/run_all.sh

# Windows（cmd 或 PowerShell）
tests\run_all.bat
.\tests\run_all.ps1 -Godot "C:\Godot\Godot_v4.7.2-stable_win64_console.exe"
```

模块行数变动时可用 `--fix` 原地同步 `docs/engineering/ARCHITECTURE.md`：

```bash
tests/run_all.sh --fix      # PowerShell: .\tests\run_all.ps1 -Fix
```

正常通过示例（退出码 `0`）：

```text
suites=37 assertions=2659 failures=0 broken=0
doc-numbers: ok (2659)
doc-suites: ok (37)
module-sizes: ok (76 rows)
module-lines: ok (limit 600)
table-shape: ok
field-readers: ok
contracts: ok
```

---

## 文档导航

`docs/` 分为 `design/`（设计规范）、`engineering/`（工程基准）与 `archive/`（只读历史）三层，阅读顺序见 [`docs/README.md`](docs/README.md)：

| 分组 | 文档 |
| :--- | :--- |
| **世界观与美术** | [`ECHO_WORLD_OVERVIEW_1.0`](docs/design/ECHO_WORLD_OVERVIEW_1.0_zh-CN.md)、[`ECHO_OPENING_PROLOGUE_1.0`](docs/design/ECHO_OPENING_PROLOGUE_1.0_zh-CN.md)、[`ECHO_VISUAL_ART_DIRECTION_1.1`](docs/design/ECHO_VISUAL_ART_DIRECTION_1.1_zh-CN.md) |
| **机制与法则** | [`ECHO_SYSTEM_LAWS_v1.0`](docs/design/ECHO_SYSTEM_LAWS_v1.0_zh-CN.md)、[`CORE_COMBAT_RULES_v0.1`](docs/design/CORE_COMBAT_RULES_v0.1_zh-CN.md)、[`BATTLE_EVENT_TIMELINE_v0.1`](docs/design/BATTLE_EVENT_TIMELINE_v0.1_zh-CN.md)、[`ENEMY_AI_AND_TELEGRAPH_v0.1`](docs/design/ENEMY_AI_AND_TELEGRAPH_v0.1_zh-CN.md) |
| **角色与数值** | [`OATHKEEPER_V2_DESIGN_SPEC_v1.0`](docs/design/OATHKEEPER_V2_DESIGN_SPEC_v1.0_zh-CN.md)、[`skill_design_principles`](docs/design/skill_design_principles_zh-CN.md)、[`combat_stats`](docs/design/combat_stats_zh-CN.md)、[`battle_status_system`](docs/design/battle_status_system_zh-CN.md) |
| **工程与基线** | [`ARCHITECTURE`](docs/engineering/ARCHITECTURE.md)、[`PROJECT_STATUS`](docs/engineering/PROJECT_STATUS.md)、[`BASELINE`](docs/engineering/BASELINE.md)、[`DECISIONS_AND_OPEN_QUESTIONS`](docs/engineering/DECISIONS_AND_OPEN_QUESTIONS.md) |
| **历史归档** | [`README_LEGACY`](docs/archive/README_LEGACY.md)、[`sevrin_skill_kit`](docs/archive/sevrin_skill_kit_zh-CN.md)、[`GODOT_ENGINE_VALIDATION`](docs/archive/GODOT_ENGINE_VALIDATION_zh-CN.md) |

## 仓库结构

```text
├── assets/              # 2.5D 角色与怪物立绘、大头头像、大厅背景与 UI 图标
├── data/
│   ├── characters/      # 可玩角色档案（sevrin / sakura）
│   ├── enemies/         # 敌人与 Boss 档案（.tres）
│   ├── levels/          # 教学关卡配置（.tres）
│   └── loot/            # 武器、护甲、道具与角色铭文配置（.tres）
├── docs/                # design / engineering / archive 文档
├── scenes/              # 主菜单、工坊大厅、春之境地图与战斗场景
├── scripts/
│   ├── actors/          # 战斗单位与状态模型
│   ├── battle/          # 战斗规则、技能、AI 意图、战术博弈与掉落系统
│   ├── meta/            # 黄昏补给商行残晶存档与局外配置
│   ├── spring/          # 未尽之春地图、事件、行商、遭遇与本局存档
│   └── ui/              # 2.5D 棋盘视图、预告层、HUD、商店与大厅界面
└── tests/               # 37 个自动化测试套件与文档/规范守卫
```
