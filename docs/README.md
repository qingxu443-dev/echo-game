# 文档目录说明

`docs/` 分三层。判断新文件放哪一层，只看一个问题：**它还会被修改吗？**

| 层 | 放什么 | 内容 |
|---|---|---|
| `design/` | 设计规范与机制定义，**持续演进** | 战斗系统与数值规划（v0.3.2，当前主规格）、系统法则、核心战斗规则、战斗事件时序、敌人 AI 与预告、守誓者 V2 规范、世界观、序章、美术方向、数值与状态系统、技能设计原则 |
| `engineering/` | 工程基准与项目状态，**随代码更新** | 架构、项目状态、决策与待决事项、框架方案、测试基线、人工验证指引与清单 |
| `archive/` | 已失效但需可追溯的历史，**只读** | 旧版 v1 技能组、早期引擎验证记录 |

## 阅读顺序（新人）

| 顺序 | 文档 | 解决什么问题 |
|---|---|---|
| 1 | [`engineering/PROJECT_STATUS.md`](engineering/PROJECT_STATUS.md) | 现在做到哪、下一步做什么 |
| 2 | [`engineering/ARCHITECTURE.md`](engineering/ARCHITECTURE.md) | 代码怎么分层、模块边界在哪 |
| 3 | [`design/ECHO_COMBAT_SYSTEM_AND_CHARACTER_NUMERICAL_PLAN_v0.3.2_zh-CN.md`](design/ECHO_COMBAT_SYSTEM_AND_CHARACTER_NUMERICAL_PLAN_v0.3.2_zh-CN.md) | **当前完整的战斗规格**：队伍、共享 AP、伤害管线、状态、角色与技能结构 |
| 4 | [`design/ECHO_SYSTEM_LAWS_v1.0_zh-CN.md`](design/ECHO_SYSTEM_LAWS_v1.0_zh-CN.md) | 世界法则与机制解释（Draft） |
| 5 | [`design/CORE_COMBAT_RULES_v0.1_zh-CN.md`](design/CORE_COMBAT_RULES_v0.1_zh-CN.md) | 早期战斗规则（0.1），范围与细节已被 v0.3.2 覆盖 |
| 6 | [`engineering/BASELINE.md`](engineering/BASELINE.md) | 改完怎么验证、断言基线是多少 |
| 7 | [`engineering/DECISIONS_AND_OPEN_QUESTIONS.md`](engineering/DECISIONS_AND_OPEN_QUESTIONS.md) | 哪些已定、哪些**不许擅自决定** |

## 维护约定

- **数字只写一遍。** 套件数与断言数只维护在 [`engineering/BASELINE.md`](engineering/BASELINE.md)，其他文档引用它，不复制。
- **归档不删除。** 失效文档移入 `archive/`，开头注明「历史提示」，保留可追溯性。
- **改名要全库搜。** 文件改名或移动后执行 `grep -rn "旧文件名" docs/ README.md`，确认没有断链。
- **链接用相对路径。** 同层直接写文件名，跨层写 `../`，便于整棵 `docs/` 一起移动。

## 分层历史

2026-11-25 之前，`docs/` 下二十余篇文档平铺，设计规范、项目状态与历史记录混在一起，新成员不知道从哪读起。当天做了两件事：把活跃文档归入 `design/` 与 `engineering/`，把失效文档移入 `archive/`；同时建立本文件作为入口。
