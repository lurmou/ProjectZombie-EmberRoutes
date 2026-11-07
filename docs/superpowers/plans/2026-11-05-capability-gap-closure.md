# 能力缺口统计与补全计划

> 日期：2026-11-05｜**v2：重做统计**。v1 的若干"缺失"结论来自关键词假设，未逐条核对；本版每条附核查命令与判定。
> 依据：[与 ProjectRemnants 对照统计](../../reviews/2026-11-05/reference-comparison.md)、[小队跟随设计 §12](../specs/2026-11-05-companion-squad-follow-design.md)、[逐项补全设计](../specs/2026-11-05-capability-closure-design.md)。
> 规则：单人；不为旧接口/旧存档写兼容；不新增测试脚本，用真实编译 + 既有定向套件 + 实机验收。
> **范围（2026-11-06 澄清）**：本文只覆盖**据点内部功能**（岗位闭环、生产、仓储、自理、安全中断）。队伍/跟随命令属于跟随线，不在此文，B6/B7 已移出。

## 0. 核查方法与判据

**判定标准**（每条结论必须落在其中一档）：

| 档 | 含义 | 证据要求 |
|---|---|---|
| 缺 | 机制不存在 | 精确 grep 0 命中，或读代码确认无该分支 |
| 部分 | 机制存在但闭环不全 | 给出存在的文件:行 + 缺的那一段 |
| 有 | 机制存在 | 给出文件:行 |
| 未核实 | 只按文件名/模块名推断 | **不得写成结论**，本版已全部剔除或降级 |

**闭环判据**：L1 单动作 → L2 一次出门（取物→作业→归还/入库）→ L3 跨会话系统。

**持久化判据**：操作是否引入"世界上看不见的承诺"？有 → 落账本；无 → 进程内 + 从活动作业重建。

**v1 的方法错误**（记录在案，避免重犯）：用大小写敏感的关键词在单一目录 grep，把"没搜到"当成"没实现"；用文件名推断模块职责。例如 `Endurance`（首字母大写）搜不到 `CharacterStat.ENDURANCE`，导致误判"耐力休息全缺"。

## 1. 缺口统计（v2，逐条可复现）

### A. 闭环缺失

| # | 结论 | 证据（命令 → 结果 / 文件:行） | 档 |
|---|---|---|---|
| A1 | 农务取水往返**缺** | `grep -niE "fillWater\|refill\|waterSource\|fetchWater\|FillCarrier" Field*.lua` → 2 条，均为觅食 `autoRefillZone`（`FieldDiscovery:169`、`FieldOperations:382`），非水源往返。工具匹配只认手上已有满水容器（`ToolRequirements:24`） | 缺 |
| A2 | 多目标作业 | **已存在**：`FieldProviders:143-189` 的 `def.continue(c)` 在同一 job 内换目标（±5 格、上限 `maxContinuousBatch` 默认 8 / 伐木 4、claims 同步替换），由 `FieldWorkflow:18` 调用 | **有（v2 误判为缺）** |
| A3 | 田间产出入库 | **已存在**：`FieldCargo:151-175` `Supply.returnRoute` 找储位 → `Store.reserveField` 容量预留 → transfer；失败码 `FIELD_STORAGE_UNAVAILABLE/FIELD_CAPACITY_UNAVAILABLE` | **有（v1 误判为缺）** |
| A4 | 工具物理归还 | **已存在**：`ToolReturnService.lua` 398 行 + `ToolReturnProvider.lua` 122 行（`ISInventoryTransferAction` 送回 `endpoint.container`、`interrupt/reconcile/recoverFor`），注册于 `PublicWork:491`，命令切换见 `MembershipRuntime:83`，`PENDING_RETURN` 恢复见 `ToolReturnProvider:99` | **有（v2 误判为缺）** |
| A5 | 伐木产出入库 | **已存在**：`FieldOperations:258-262` TREE 分支调 `Cargo.outputs` → 同 A3 的 deposit 路径 | **有（v1 误判为缺）** |
| A6 | 作业前补给 | **部分**：工具取用已有（`FieldSupplies.lua` 152 行，`PREPARE`→`WORK`，`FieldProviders:28-64` 预占 custody）；液体（水/清洁液）无补给分支，只判"有干净水且 uses>0"（`ToolDiscovery`） | **部分（v2 判为全缺，v3 更正）** |
| A7 | 作物治疗 | `grep -niE "cure\|plantDisease\|disease"` 全库 → 1 条无关命中（`SelfCareReconciliation:87` 注释） | 缺 |
| A8 | 播种/犁地 | 精确 `grep -nE "\bsow\b\|ISSeed\|plantSeed\|SeedAction"` → **0 命中**。`CLEAR` 用 `ISShovelAction` 铲枯株，不是犁地播种 | 缺（需求已确认要） |

### B. 感知与调度

| # | 结论 | 证据 | 档 |
|---|---|---|---|
| B1 | LOD | `ProbeNpc.java:68` `return UpdateSchedulerSimulationLevel.FULL`，无条件 | 缺 |
| B2 | 安全感知 | **比 v1 描述强**：`NeedsObserver:22-53` 有 `SAFE/UNSAFE/UNKNOWN/RECENT_DAMAGE` 三态 + 3 秒伤害窗口 + `spottedThreat`（Java 桥 `observerSample`）；消费者 `CookingService:55`、`SelfCare:94`。**缺的是传播与共享**（无跨角色报案） | **部分（v1 判轻）** |
| B3 | 受威胁中断 | 作业侧无安全门：`FieldProviders:92` 只按耐力拦（`ENDURANCE<0.4`），不按安全 | 缺 |
| B4 | 耐力驱动休息 | **已存在**：`NeedsPolicy:6` `{kind='REST',field='endurance',enter=0.25,leave=0.80,inverse=true}`；消费者 `ActivityParticipant:31`、`SelfCare:12`、`StudyRelief:4`；`FieldProviders:92` 耐力 <0.4 拒接田间活 | **有（v1 误判为缺）** |
| B5 | 跨岗位目标占用 | **已存在**：农务目标以 `field-target:<kind>:<identity>` 为 claim 键，`FieldProviders.claim:129-134` 用 `Store.resourceOwner(key)` 拒绝重复，返回 `FIELD_RESOURCE_RESERVED`；`def.continue` 同步替换键 | **有（v2 判为"部分"仍偏重）** |
| B6 | ~~队伍作用域命令~~ | 已移出范围（属跟随线，非据点功能） | 范围外 |
| B7 | ~~整队搜楼/休息~~ | 已移出范围（属跟随线） | 范围外 |
| B8 | 结构化事件流 | `Log.write(category, message)` 两参纯文本（`shared/.../Log.lua:4`），无字段化事件 | 缺 |

### C. 实体能力

| # | 结论 | 证据 | 档 |
|---|---|---|---|
| C1 | 战斗 | `grep -niE "ISAttack\|combat\|getSurroundingAttacking\|AttackAction"` → 7 条，全部是**防御检查**（`NeedsObserver:43-48`、`SelfCare:94`、`CookingService:55`）与 **UI 技能名映射**（`PersonnelDossierDrawer:172-174`），无攻击动作 | 缺 |
| C2 | 车辆 | → 3 条：`CompanionAgent:4` 的 `FOLLOW_WAIT_VEHICLE` 状态、`LeisureFitness:66` 的 `getVehicle()==nil` 守卫、`StorageFilter:99` 的零件分类。无驾驶/座位/装载 | 缺 |
| C3 | NPC 拿不到 XP | `IsoGameCharacter$XP.AddXP(Perk,float)`（2/3/4 参同构）字节码：`!isLocalPlayer()` 时直接 `return`；5/6 参重载**无此闸门**。参考用 ASM patch 兜，我们直接调 6 参即可 | 缺（一行级） |
| C4 | 对话 | **部分存在**：`ActivityRoleActions:36` `addLineChatElement` 社交台词、`ActivityScripted:52` `playEmote`、`LeisureSit` 会话钩子 | **部分（v1 说 0 不准）** |

### D. 治理

| # | 结论 | 证据 | 档 |
|---|---|---|---|
| D1 | 逐帧执行器 | 只有引擎路径（设计 §12.7） | 缺 |
| D2 | 门纪律 | 引擎自行 toggle，无队伍门状态 | 缺 |
| D3 | 全局搜索预算 | 引擎队列不可控 | 缺 |

## 2. v1 → v2 更正汇总

| 项 | v1 说法 | v2 实测 | 影响 |
|---|---|---|---|
| A3 田间入库 | 缺（产出留背包） | 有完整 deposit + 容量预留 | M1 少一项 |
| A5 伐木入库 | 缺（无堆场） | 走同一 deposit 路径 | M1 少一项 |
| B4 耐力休息 | "全库 Endurance 零命中" | 有 `NeedsPolicy` 0.25/0.80 + 三处消费者 | M3 少最大一项 |
| B2 威胁 | "仅局部僵尸数" | 有三态安全模型，缺的是传播 | M3 缩小为"传播" |
| B5 目标占用 | "仅清洁点" | 10+ 模块都在用 | M2 降级为"补齐农务" |
| C4 对话 | "0" | 有社交台词与 emote | 不再列为缺口 |

**教训**：v1 的 8 项 A 类缺口里 2 项误判、1 项部分；B 类 4 项里 2 项误判/判轻。原因是关键词与目录假设，不是代码难读。

## 3. 依赖与顺序（v2）

```
M0 LOD（B1）─────────────────────────────┐
M1 田间闭环（A1 取水 → A2 多目标 → A6 补给 → A4 归还）
M1b 播种生产链（A8，需求已确认）
M2 安全传播（B2 剩余）+ 中断（B3）+ 农务占用（B5 补齐）
M3 事件流（B8）
M4 队伍命令（B6 → B7）
M5 执行器（D1 → D2）＋ XP 授予（C3）
M6 战斗（C1）/ 车辆（C2）/ 对话（C4 扩展）
```

硬依赖：**M5 必须在 C1/C2 之前**；**M1b 必须在 M1 之后**；**M2 的中断复用 `TaskBusinessStop`**；其余可并行。

## 4. 各里程碑最小实现

### M0 LOD（B1）

- `getMinimumSimulationLevel()` 按距离与状态返回 `FULL/NEAR/FAR`，75 格进、90 格出。
- 强制 FULL：死亡/布娃娃/坠落、`ClimbOver*`、家具占用、正在执行的作业、跟随中且队长在视野内。
- 远处用 meta 位置推进，不跑寻路。

### M1 田间闭环（A1、A2、A6、A4）

会话结构从「单目标」改为「补给 → 作业队列 → 归还」：

| 项 | 设计 |
|---|---|
| A6 补给 | 作业前按 `ToolRequirements.requiredRoles` 检查背包；缺工具/缺液体 → 去注册的 `STORAGE` 端点取（复用 `CraftSupply.endpoint`），拿到再开工 |
| A1 取水 | 液体类补给单独一支：找水源（复用 `CookingWaterSources` 的搜索与凭证）→ 装满 → 回目标；按 `waterUses` 判断够不够本次作业 |
| A2 多目标 | `FieldSession` 加 `queue`，段末续下一个；上限按负重与液体余量算，不写死 |
| A4 归还 | 作业结束时把借用工具放回取用时的容器；托管记录仍由 `LaborStore` 持有，物理归还不改变账本 |
| 占用 | 农务点沿用 `FieldDemand.claimed` 模式（进程内，从活动作业重建，不落账本） |

**不做**：地块规划、作物目录、轮作。

### M1b 播种生产链（A8）

```
PLOW（DIG_PLOW） → SOW（读原版 farming_vegetableconf 选种） → WATER（复用 M1） → CARE（可选） → HARVEST → RETURN
```

- `FieldSession` 增加 `stage`，每阶段独立适配器。
- **不长期占用身体**：播种完释放 Session，后续由 `discover` 在下一轮扫出 `WATER/HARVEST` 再接手。
- 不建作物目录表，不写轮作。

### M2 安全传播 + 中断（B2、B3、B5 补齐）

- 已有 `NeedsObserver` 的三态安全作为**唯一事实源**，不做第二套判断。
- 新增共享报案表：某成员 `UNSAFE` 时写入（位置 + 12 秒 TTL），同据点成员读取后只降级为"附近可疑"，不直接接管。
- 作业中断：安全等级足够时走 `TaskBusinessStop`（暂停→停止→证据），不新建通道。
- 不做：响应者优先级、人数上限、3D 听觉加权（依赖战斗岗位，C1 后再补）。

### M3 事件流（B8）

- `Log.event(domain, event, fields)`：`job-submit / job-start / job-terminal / job-skip(reason) / path-submit`。
- 目的：G1–G3 的「寻路提交次数 / 受阻占比 / 队列等待」需要数据源。

### M4 队伍命令（B6、B7）

- 命令带 `party=leaderId` 作用域，受理时逐成员走现有 `OBLIGATION_PENDING`。
- 首批两条：`PARTY_REST`（下游 `SelfCare`/`ReposeSites` 已有）、`PARTY_LOOT`（下游 `Haul` + `ContainerRegistry` 已有）。
- 其余按下游是否存在排队：`PARTY_BREAK/RELOAD` 等 C1；`PARTY_FLEE` 在 M2 后；`PARTY_WORK` 最后。

### M5 执行器 + 门纪律 + XP（D1、D2、C3）

按设计 §12.7；XP 用 6 参 `AddXP` 在作业完成点授予，不 patch 引擎。

### M6 战斗 / 车辆 / 对话（C1、C2、C4）

独立立项。战斗先做"威胁响应 + 近战自保"，不做 CQB 体系；车辆按参考 21,122 行量级单独立项。

## 5. 验收

| 里程碑 | 实机观察点 |
|---|---|
| M0 | 远离同伴时帧耗时不随人数线性增长，靠近后行为正常 |
| M1 | 缺工具会自己去找；水用完回水源；一次出门处理多个目标；工具回到原容器 |
| M1b | 能犁地→播种→（数日后）自动来浇水/收割 |
| M2 | 一名成员遇袭，同据点成员进入警戒；生产作业被中断且不留半成品 |
| M3 | 事件流能看到 submit/skip 与原因 |
| M4 | 一条命令让全队休息/搜楼，结束后回原岗 |
| M5 | 侧移无抖动、不与原生根运动冲突；NPC 技能随作业上涨 |

静态门禁：Java 真实编译、Lua 普通/Debug、i18n 对称、既有定向套件。**不新增测试脚本。**

## 6. 已确认与待定

已确认：
1. A8 播种/犁地在需求内 → M1b；不做轮作。
2. C3 不是"要不要建成长系统"：属性/技能/特质是引擎原生，缺口只是 XP 闸门。
3. A3/A5/B4 已存在，v1 统计有误，已更正。

待定：
1. M6 顺序：战斗（C1）还是车辆（C2）先。
2. 是否需要"原生动作产生的 XP"（需 @Patch 有闸门的重载）；当前只做主动授予。
3. A4 的"物理归还"是否要真的搬回容器，还是只保留托管记录即可（当前代码是后者）。
