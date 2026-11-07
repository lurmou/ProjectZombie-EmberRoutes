# 能力补全设计（逐项）

> 日期：2026-11-05｜状态：设计，未实施。每条给插入点、数据结构、流程、失败边界、验收与"不做"。
> 上游：[缺口统计与补全计划](../plans/2026-11-05-capability-gap-closure.md)（v2，逐条 grep 核实）。
> 原则：不新建系统，全部挂在既有 `TaskRuntime` / `LaborStore` / `FieldSession` / `FieldSupplies` / `FieldCargo` 上。

## 0. 证据等级

| 标记 | 含义 |
|---|---|
| 已核实 | 有文件:行或 grep 结果 |
| 待核实 | 只读到入口，具体 API 需实施前确认；**不得据此写代码** |

## 1. 田间闭环

### 1.1 现状（v3 修正）

| 能力 | 状态 | 证据 |
|---|---|---|
| 工具补给 | **已有** | `FieldSupplies.lua` 152 行：`PREPARE` 阶段走到仓库 → `ISInventoryTransferAction` → 校验到达 → `phase='WORK'`；`FieldProviders:28-64` 生成 `toolSupply.requirements` 并预占 custody |
| 液体补给 | **缺** | `ToolDiscovery.findSupplies` 只判 `WATER_FLUID` 的"有干净水且 uses>0"，不判够不够本次作业；`FieldSupplies` 无液体分支 |
| 水源往返 | **缺** | Field 内 `waterSource/fillWater` 2 条命中均为觅食 `autoRefillZone` |
| 多目标 | **缺** | `payload.target` 单值（`FieldContext:25/64/71`） |
| 工具归还 | **缺** | `FieldSession.persist:98-102` 只回滚"未取用"的预留，已取用的工具留在背包 |
| 治疗 | **缺**（原版有动作） | `ISCurePlantAction` + `ISFarmingMenu:648/657/700/709/753/762/806/817` |
| 播种 | **缺**（原版有动作） | `ISSeedActionNew:new(player,item,typeOfSeed,plant)`（`CFarming_Interact:122`）；犁地 `ISPlowAction:new(player,square,item)`（`shared/Farming/TimedActions/ISPlowAction.lua:3`） |

### 1.2 液体补给与水源往返（A6 剩余 + A1）

**插入点**：`ToolDiscovery.findSupplies`（角色循环）、`FieldProviders.prepare`（构造 `toolSupply` 处）、`FieldSupplies.step`（`PREPARE` 分支）。

**数据结构**（job payload，随 job 持久，符合"承诺"判据——预占了容器与水量）：

```lua
payload.liquidSupply = {
  role   = 'WATER_FLUID' | 'CLEAN_FLUID',
  itemId = '<containerItemId>',
  needUses   = 12,          -- 本次作业需要几次喷洒
  needAmount = 3000,        -- 毫升，= needUses * getFluidContainerMillilitresPerUse()
  sourceId   = '<waterSourceObjectId>',  -- 找到后写入，避免每拍重搜
  attempts   = 0,
}
```

**needUses 计算**（不猜，沿用已有函数）：`Discovery.waterGoal(plant)` 给出目标水位，`ISFarmingMenu.getWaterUsesInteger(item)` 给出每桶可用次数；`uses = min(10, 可用次数, ceil((goal-level)/10), floor((max-level)/10))`，与 `FieldOperations:276-281` 现有算法一致。

**流程**（`PREPARE` 内，工具补齐之后）：

```
1 背包容器 uses >= needUses        → 清 liquidSupply，进入 WORK
2 否则找水源：CookingWaterSources.search(...)   -- 复用，返回 object/id/amount
   找不到                          → 降级：本次只做不耗水目标（HARVEST/CLEAR），WATER 目标冷却
3 走到水源（WorkTransfer.prepareMove）→ 停身 → CookingFluidTransfer 装填
4 校验 getAmount() 增加            → 重算 uses，回到 1
5 attempts >= 3 或 水源耗尽         → FIELD_WATER_SOURCE_UNAVAILABLE，作业失败但保留已得产出
```

**为什么复用 `CookingWaterSources` 而不是新写**：它已有水源识别（`getFluidAmount/getUsesExternalWaterSource/isTaintedWater`）、ID 持久化与 `release` 语义，且烹饪已在用；新写一套会出现两份水源判定。

**失败边界**：装填后水量没变 = 失败（不重试同一水源 3 次以上）；水源被破坏/搬走 → `revalidate` 失败即换下一个或降级。**不落账本**：水是物理可观测的，重启后重扫即可。

**验收**：一次作业中途水用完 → 自己回水源 → 装满 → 回来继续；无水源时只做不耗水的活，不空转。

**不做**：不做多桶并行携带、不做备用水源预选、不做跨据点调水。

### 1.3 多目标：已存在（A2 更正）

**结论：本项不需要补。** 读代码后发现连续作业已在同一 job 内实现：

- `FieldProviders:143-189` 的 `def.continue(c)`：在一个 job 内把 `payload.target` 换成附近目标（`|dx|<=5 且 |dy|<=5`、同层），同步替换 claims、递增 `batchCount`。
- 上限来自策略：`policy.maxContinuousBatch`，缺省 8，伐木 4（`:148-150`）。
- 调用点：`FieldWorkflow:18`（`continueOrFinish`），在每次 WORK 段结束后尝试续作，失败才结束 job。
- 换目标时若新目标不需要额外工具，`payload.toolSupply` 为 nil、`phase='WORK'`（`FieldProviders:176-177`）——**不回仓库、不重新取工具**，这正是"一次出门多个目标"的效果。

跨区域时 `continue` 返回 false，job 结束；下一个 job 因工具仍在背包（`inInventory=true`）同样跳过 PREPARE，只是会走一次路程。

因此 v2 里"单目标、需换 job"的判断是错的：`payload.target` 单值只说明**任一时刻只有一个目标**，不代表一个 job 只做一个。

### 1.4 工具归还（A4）

**插入点**：`FieldSession.persist` 的 `SETTLING` 分支（现有 `toolSupply` 回滚附近，`FieldSession:98-107`）、`FieldSupplies`（新增反向 transfer）。

**数据结构**：

```lua
payload.toolReturn = { containerId='...', itemId='...', custodyId='...' }
payload.phase = 'RETURN'
```

**流程**：链结束（或 job 单独结束）时，对 `custody.state=='HELD'` 且**来自仓库**（`FieldProviders` 记录过 `containerId`）的工具：走到原容器 → `ISInventoryTransferAction` → 校验离开背包 → `Store.releaseCustody`。

**不做**：不归还 `inInventory=true` 的工具（本来就在背包里，还回去等于搬玩家的东西）；不归还玩家手动放进背包的物品。

**失败边界**：容器不存在/满 → 保留 custody，`RECONCILE_REQUIRED` + `FIELD_TOOL_RETURN_UNCONFIRMED`（与现有 stop 证据语义一致，不假装归还）。

**验收**：取用的仓库工具在作业结束后回到原容器；原容器被拆时作业停在 `RECONCILE_REQUIRED` 而非静默丢失。

### 1.5 作物治疗（A7）

**原版能力（已核实）**：

| 病害 | 判定字段 | 药剂 | 动作 |
|---|---|---|---|
| 霉病 Mildew | `plant.mildewLvl > 0`（`ISFarmingMenu:224`） | `GardeningSprayCigarettes`（`:657`） | `ISCurePlantAction` |
| 蝇虫 Flies | `plant.fliesLvl > 0`（`:227`） | `GardeningSprayMilk`（`:648`）/ 香烟（`:709`） | 同上 |
| 蛞蝓 Slugs | `plant.slugsLvl > 0`（`:426` 调试项） | `SlugRepellent`（`:753`） | 同上 |
| 蚜虫 Aphids | **待核实**（`aphidsLvl` 在 Lua 无命中） | `GardeningSprayAphids`（`:806`） | 同上 |

**设计**：

- `ToolRequirements` 新增角色 `CURE_TOOL`，`matchPhysical` 按药剂类型匹配（`GardeningSpray*` / `SlugRepellent`，且 `getCurrentUses()>0`）。
- `FieldDiscovery.scanPlants` 增加分支：`kind='CURE'`，disease 字段 > 0 时产出目标，并记录 `disease` 名。
- `FieldOperations` 增加 `CURE` 分支：走到 → 装备 → `ISCurePlantAction:new(npc, spray, uses, plant, 10*(uses*10), diseaseName)` → 观测对应 `*Lvl` 下降。
- 药剂用完 → 走 1.2 的补给分支（`CURE_TOOL` 与液体共用"去仓库取/装填"通道）。

**不动**：不新增病害模型，直接读原版字段；不做预防性喷药（只在有病害时治）。

**验收**：霉病/蝇虫地块被治疗后对应等级归零，药剂次数相应减少。

### 1.6 播种生产链（A8，需求已确认）

**原版能力（已核实）**：
- 犁地：`ISPlowAction:new(player, square, item)`；仅当 `plant.state=='plow'` 才可播种（`ISFarmingMenu:214`）。
- 播种：`ISSeedActionNew:new(player, item, typeOfSeed, plant)`（`CFarming_Interact:122`），需要背包有 `ItemTag.IS_SEED`。

**设计**：拆成两个独立 job，不长期占用身体。

| job | 目标 | 动作 | 前置 |
|---|---|---|---|
| `PLOW` | 空地/枯株格 | `ISPlowAction` | 有 `DIG_PLOW` 工具（可徒手，原版允许 `nil` item） |
| `SOW` | `state=='plow'` 的格 | `ISSeedActionNew` | 背包/仓库有 `IS_SEED` 种子，且 `props.sowMonth` 含当前月 |

- 选种：只按 `farming_vegetableconf.props[typeOfSeed].sowMonth` 过滤当季，**不建作物目录**；同季多种时取库存最多的。
- 播种后释放 Session：后续浇水/收获由 `discover` 在下一轮自然接上（`waterLvl` 与 `canHarvest` 判定已存在）。
- `FieldSession` 增加 `stage` 字段（`null|'PLOW'|'SOW'`），仅用于分派到不同 `FieldOperations` 分支，不引入状态机框架。

**不做**：轮作、施肥、温室、作物优先级策略表。

**验收**：空地被犁→播种→（数日后）自动来浇水→成熟自动收割；全程无身体被长期占用。

## 2. LOD（B1）

**插入点**：`ProbeNpc.getMinimumSimulationLevel()`（当前恒 `FULL`）。

**设计**：

```java
// 分段：只在玩家距离变化超过 2 格时重算，避免每帧开方
FULL  : 死亡/布娃娃/坠落/ClimbOver*/家具占用/正在执行作业/跟随中且队长在 20 格内
NEAR  : 距最近玩家 < 75
FAR   : 距最近玩家 > 90（滞回）
```

- 进入/退出用不同阈值（75/90）避免边界抖动。
- `FAR` 时位置推进改由 meta 目标以固定速度走直线，不提交寻路。
- 距离刷新：每 500ms 或收到 move 命令时；不每帧算。

**不做**：不降级 AI 决策树，只降模拟等级；不做跨层不同规则（先同规则）。

**验收**：8 个同伴在 100 格外，帧耗时不随人数线性上升；靠近后行为立即恢复。

## 3. 安全传播与中断（B2 剩余 + B3）

**事实源不变**：`NeedsObserver.sample()` 的 `SAFE/UNSAFE/UNKNOWN/RECENT_DAMAGE`，不新建判断。

**新增 `ThreatBoard`（shared，进程内，不落盘）**：

```lua
report(x,y,z,level,sourceId)     -- level: 'UNSAFE'
nearest(x,y,z,radius) -> level,dist,at
```

- 写入：`NeedsObserver` 判到 `UNSAFE` 且 `spottedThreat==true` 时上报，TTL 12 秒（跟随参考量级，非照搬）。
- 读取：作业前置检查与 UI 提示。**只作"附近可疑"降级提示，不接管行动**；要不要跑由本 NPC 自己的 sample 决定。
- 中断：`FieldSession.spec.tick` 开头查 sample（缓存 500ms），`UNSAFE` 且 `effects=='KNOWN'` → `TaskBusinessStop`（暂停→停止→证据），不新建通道。

**为什么不做响应者排序**：排序对象是岗位，GUARD 岗位在 C1 之后才有；先补"有人遇袭，同据点知道"这一层。

**验收**：一名成员被咬，12 秒内同据点成员从 UI 可见"附近可疑"，正在做饭/耕地的作业被安全停止且不留半成品。

## 4. 农务目标占用（B5 补齐）

**插入点**：`FieldDiscovery` 产出目标后、`FieldWork.submit` 之前。

**设计**：把 `FieldDemand:114-120` 的 `claimed` 模式抽成 `FieldClaims`（shared，进程内）：

```lua
tryClaim(key, npcId, kind)   -- key = x..':'..y..':'..z..':'..kind，重复返回 false
release(key, npcId)
```

- `key` 含 kind，所以同一格"浇水"和"收割"不互相挡。
- 作业结束/停止/放弃时释放；TTL 60 秒兜底防泄漏。
- **不落盘**：占用可从活动 job 重建（`Store` 已有 job 索引）。

**验收**：两个农夫同时开工，不会走向同一格。

## 5. 结构化事件流（B8）

**插入点**：`shared/EmberRoutesProbe/Log.lua`（现有 `write(category,message)` 两参）。

**设计**：加 `Log.event(domain, event, fields)`，内部渲染成 `domain` + `event k=v ...` 一行；字段排序固定，避免日志 diff 抖动。

首批事件（只加需要的）：

| domain | event | 字段 |
|---|---|---|
| FIELD | job-submit / job-start / job-terminal / job-skip | jobId, kind, reason |
| FIELD | path-submit | jobId, target |
| FOLLOW | path-submit / blocked / yield | npcId, stage |

计数：`RuntimeMetrics` 加计数器（已有模块，不新建），G1–G3 直接读。

**验收**：一次三人跟随能数出寻路提交次数、受阻占比与队列等待时长。

## 6. 队伍命令（B6/B7）

**插入点**：`MembershipService.request`（受理）、`MembershipRuntime`（推进）。

**设计**：不新建事务模型，**一条队伍命令拆成 N 条成员子命令**：

```lua
{ kind='PARTY', party=<leaderId>, action='REST'|'LOOT', members={id,...}, expiresAt=<ms> }
```

- 受理时逐成员跑现有 `validRow` + `OBLIGATION_PENDING` 检查；有成员被拒 → 返回 `PARTIAL` 并带被拒列表，整体不撤销（避免"一人义务未清导致全队不动"）。
- `REST`：落到成员 `WAIT` + `SelfCare` 的 REST 意图（下游已有）。
- `LOOT`：落到成员 `SETTLE` + 一次 `Haul` 批量（下游 `Haul` + `ContainerRegistry` 已有）。
- 结束条件：全部子命令终态，或 `expiresAt` 到；结束后按原岗位恢复，不做"记忆恢复"——岗位本就在成员行里。

**不做**：`PARTY_BREAK/RELOAD`（无战斗下游）、`PARTY_WORK`（需要岗位优先级模型）。

**验收**：一条命令让三人同时去休息/搜同一栋楼，中途有人被义务卡住不影响其余两人。

## 7. XP 授予（C3）

**插入点**：作业 DONE 分支（`FieldSession.persist`）、`FieldWork` 的产量统计处。

**设计**：

```java
// EmberRoutesProbeJava 增加 bridge
char.getXp().AddXP(perk, amount, true, /*useMultiplier*/false, false, false);  // 6 参，无本地玩家闸门
```

- 数值按工时与产量给（如收割 1 株 = 5 XP，砍 1 树 = 10 XP），不做经验曲线。
- **不做**：不 patch 引擎 2/3/4 参重载；引擎自己给的经验拿不到就接受，靠主动授予即可。

**验收**：连续作业后 `getPerkLevel` 上升。

## 8. 执行器 / 门纪律（D1/D2）

按[设计 §12.7](2026-11-05-companion-squad-follow-design.md) 执行，此处只记约束：取消路径后才写控制变量、回收前不再提交路径、单点 `submitSegment` 替换。门纪律必须排在 D1 之后。

## 9. 战斗 / 车辆 / 对话（C1/C2/C4）

**一期只做最小闭环，不做体系**：

| 项 | 一期内容 | 前置 |
|---|---|---|
| C1 战斗 | 威胁响应（自保：后退/呼叫）+ 近战一次攻击；不做阵型、掩护、换弹 | D1 执行器 |
| C2 车辆 | 上下车、座位占用、跟随"队长在车内"的等待（现有 `FOLLOW_WAIT_VEHICLE`）+ 装载/卸货 | 无（可独立） |
| C4 对话 | 保留现有台词与 emote；是否加指令式对话由产品决定 | 无 |

C1/C2 都需要各自的设计文档与实机验收，**不在本文件内承诺规模**。

## 10. 全局约束

1. **不落盘判据**：水、占用、报案、链——都是可观测事实，进程内 + 从活动 job 重建；只有 custody/capacity/obligations 落账本。
2. **失败码**：新增 `FIELD_WATER_SOURCE_UNAVAILABLE`、`FIELD_FLUID_TRANSFER_FAILED`、`FIELD_TOOL_RETURN_UNCONFIRMED`、`FIELD_LIQUID_INSUFFICIENT`，全部进 CN/EN 翻译（`check-i18n.py` 是硬门禁）。
3. **不新增测试脚本**；纯算法边界（needUses 计算、链上限、占用键）靠实机与既有套件覆盖。
4. 每项落地前先确认"插入点仍在"——本文件所有行号基于 0.29.41，改动后须复核。
