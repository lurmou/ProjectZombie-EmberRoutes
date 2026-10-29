# A-Life 生态系统与据点架构设计参考（基于 Project A-Life 源码借鉴）

> 日期：2026-10-23｜状态：approved-reference｜适用：EmberRoutes 宏微观模拟、商路交割、敌对/中立实体、据点插槽与无线电传报。  
> 源码指针：`Project A-Life [ALIFE NPCS]` (Steam Workshop ID: `3803984183`，Mod ID: `ProjectALifeNPCs`，作者: Vice)  
> 本地源码绝对路径：`D:\Software\GameApp\steam\steamapps\workshop\content\108600\3803984183\mods\ProjectALifeNPCs\42.20\`

---

## 1. 总体定位与借鉴边界

本文件收录并整理自对 `Project A-Life` 本地源码的深度逆向工程分析。

### 1.1 核心边界约束（遵守 AGENTS.md）
1. **单一权威与单人优先**：宏观数据与本地实体由单机本地世界唯一仲裁，严禁跨端重复结算。
2. **稳定 ID 与状态留存**：NPC、商队、车辆、据点均具备长效 UUID，绝不使用虚假销毁重建代替真实实体转移。
3. **架构互补而非全盘照搬**：
   * `Project A-Life` 的强项是**野外小队战术、隐蔽具象化、视锥计算与轻量化实体**；
   * `EmberRoutes` 的核心是**商路物流、车辆装卸、AE2 仓储网格、工单生产链与社区经营**。
   * 我们将 `Project A-Life` 的底层物理与宏观调度机制融入 EmberRoutes，服务于商队与据点生态。
4. **调度从属声明（2026-10-25）**：本文的插槽竞价、宏观低频推进等调度表述仅为参考素材；正式任务分派一律以[唯一架构](2026-10-22-npc-behavior-architecture-design.md)与[统一任务协议](2026-10-23-unified-task-dispatch-design.md)的事件置脏+逐NPC认领为准，不采用每小时插槽竞价作为实施调度模型。宏观低频结算（tickSeconds/squadSliceMs 一类预算与切片手法）可独立借鉴。

---

## 2. 核心技术构件与源码指针对照表

| 机制类别 | Project A-Life 源码指针 | 核心算法 / 机制 | EmberRoutes 吸收与适配方案 |
| :--- | :--- | :--- | :--- |
| **轻量级物理实体** | `42.20/media/lua/server/ProjectALife/Shells/ALifeShellAdapter.lua`<br>`ALifeAIFence.lua` | `createZombie` + `setUseless(true)` 傀儡化<br>挂载自定义 `AnimSets` 与骨骼动作 | **双轨制实体架构**：<br>• 战术强盗/商队护卫/野外哨兵：采纳 Zombie Shell，极致省性能。<br>• 据点工匠/居民：保留 ZombieBuddy/完整角色体系，满足复杂工单与物品交互。 |
| **视界安全具象化** | `42.20/media/lua/server/ProjectALife/Offline/ALifeRenderProtocol.lua`<br>`ALifeRoadGraph.lua` | 玩家视锥点乘过滤（`coneHalfCos = 0.5`）<br>掩体平移检测（`slideStep`, `hiddenMinimum`） | **商队与野外遭遇安全交割**：<br>进入 80 格视距时，若落在玩家正面 60° 视锥内，平移至树木/建筑后盲区生成，绝不穿帮。 |
| **宏观低频算力熔断** | `42.20/media/lua/server/ProjectALife/Offline/ALifeOfflineDirector.lua`<br>`ALifeSquadLedger.lua` | `tickSeconds = 20`<br>`squadSliceMs = 3`<br>`squadsPerSlice = 2` | **商队宏观推进器**：<br>每 10~20 秒结算一次大地图路网，单次切片算力封顶 3ms，结合原版 `IsoMetaGrid` 算损耗。 |
| **据点与插槽设施** | `42.20/media/lua/server/ProjectALife/Outposts/ALifeOutpostDirector.lua`<br>`ALifeOutpostBuilder.lua` | 动态封板（`IsoThumpable`）<br>营火与战术掩体布局 | **Smart Terrain 岗位插槽**：<br>白天货运车位/工匠/农田，夜晚营火/床铺，通过插槽竞价（Slot Bidding）驱动 NPC 原生 TimedAction。 |
| **动态无线电传报** | `42.20/media/lua/server/ProjectALife/Talk/ALifeKnoxCountyRadio.lua`<br>`Talk/ALifeRumors.lua` | 全图事件广播、传闻派发 | **原版车载/手持电台接驳**：<br>商队抛锚求援、城镇物资暴涨/暴跌行情、路霸路卡预警，生成涌现式任务。 |

---

## 3. 各模块具体落地规范

### 3.1 实体物理层：Zombie Shell 傀儡架构应用

#### 源码参考
* `ShellAdapter.createShell(actor)` [`ALifeShellAdapter.lua`#L120-L160]
* `AIFence.track(shell)` [`ALifeAIFence.lua`]

#### EmberRoutes 落地规范
1. **友方据点 NPC**：
   * 需执行精细的烹饪、缝纫、农田灌溉、AE2 仓储分拣，沿用 `IsoGameCharacter` + ZombieBuddy / 原版 TimedAction 驱动。
2. **敌对强盗（Bandits）、路卡哨兵与商队随从（Guards）**：
   * 采纳 Project A-Life 的 `Zombie Shell` 模式：
     ```lua
     local shell = createZombie(x, y, z, nil, 0, IsoDirections.S)
     shell:setUseless(true) -- 扼杀原版丧尸扑咬 AI
     shell:setCanWalk(true)
     shell:setCrawler(false)
     shell:setFakeDead(false)
     shell:setTarget(nil)
     -- 注入 EmberRoutes 统一 actor 识别字段
     local data = shell:getModData()
     data.EmberRoutesActorUID = actor.uid
     data.EmberRoutesRole = "guard"
     ```
   * 收益：同屏出现 10~20 名强盗或护卫时，物理碰撞和布偶倒地完全由 C++ 原生承载，无 `IsoPlayer` 联机与背包同步开销，彻底杜绝掉帧。

---

### 3.2 具象化与出入场：视锥避让与开阔车位

#### 源码参考
* `RenderProtocol.settings` 与视锥计算 [`ALifeRenderProtocol.lua`#L15-L80]
  * `coneHalfCos = 0.5`（即 $\cos(60^\circ) = 0.5$）
  * `player:getForwardDirection()`

#### EmberRoutes 落地规范
1. **荒野截击商队（Wilderness Intercept）**：
   * 当商队在宏观公路网上行进，玩家驾车追上其坐标时（进入 80 格）：
   * 取玩家朝向向量 $\vec{F} = (fx, fy)$，计算商队相对于玩家的归一化方向向量 $\vec{D} = (dx, dy)$；
   * 若 $\vec{F} \cdot \vec{D} > 0.5$（即处于玩家正面视野夹角内）：
     * 触发平移避让（`slideStep`）：向路肩外侧或密林掩体后平移，或寻找转角遮挡处生成；
     * 生成后处于“情境化驻车”状态（车辆停靠路肩打双闪，NPC 靠车戒备或检修），绝不高空掉车或当面凭空刷新。
2. **据点专属车位交割（Cargo Bay Docking）**：
   * 当商队到达城镇据点：
   * 若玩家在据点内，商队从据点入口盲区驶入，对齐停入【专属货运装卸车位（Cargo Bay）】；
   * 若玩家不在场，走宏观算账直接在仓储账本交付物资，无需实例化实体。

---

### 3.3 宏观路网与算力熔断：时间切片推演

#### 源码参考
* `OfflineDirector` 调度器与时间预算 [`ALifeOfflineDirector.lua`#L20-L75]
  * `squadSliceMs = 3`（3 毫秒硬预算）
  * `tickSeconds = 20`（20 秒更新周期）

#### EmberRoutes 落地规范
1. **大地图离线推演（Macro Highway Simulation）**：
   * 全肯塔基商队在公路拓扑图（Highway Graph）上以浮点进度推进；
   * 严禁每帧更新，固定为 **每 10~20 秒一次低频轮询（Low-Frequency Tick）**；
   * 单帧切片耗时超过 3ms 时主动 `coroutine.yield()`，将余下商队推迟至下一逻辑刻，主渲染帧率永不下跌。
2. **生态摩擦损耗（Ecology Friction）**：
   * 结合原版 `IsoMetaGrid` 虚拟僵尸密度：
     $$\text{商队单程损耗} = \text{路段基础磨损} + \text{途经格僵尸热度} \times \text{护卫战力修正}$$
   * 自动扣除干粮、弹药与车辆耐久，转化为电台事件或据点整备需求。

---

### 3.4 据点运作：Smart Terrain 岗位插槽与 0~4 优先级融合

#### 源码参考
* `ALifeOutpostDirector.lua` & `ALifeCampfires.lua`

#### EmberRoutes 落地规范
1. **据点插槽池（Settlement Slot Pool）**：
   * 据点不再为 NPC 编写死板的逐人行动轨迹，而是维护插槽清单：
     * **生产/物流槽**：货运装卸车位（Cargo Bay）、工作台（Workbench）、农田（FarmPlot）、储物柜（StorageChest）；
     * **防卫槽**：哨塔（Watchtower）、沙袋掩体（SandbagCover）、路口哨卡（Checkpoint）；
     * **生活槽**：床铺（Bed）、营火（Campfire）、座椅（Chair）、诊所床位（ClinicBed）。
2. **动态竞价分配（Slot Bidding）**：
   * 据点调度器每隔游戏小时（或昼夜转换、空袭警报时）进行一次插槽拍卖；
   * 结合玩家在 UI 中配置的 **RimWorld 式 0~4 优先级矩阵** 与 NPC 的生理需求（疲劳度、饥饿度）分配插槽；
   * NPC 认领后，走向指定坐标触发原生 `TimedAction`。

---

### 3.5 世界传报系统：原版调频无线电接驳

#### 源码参考
* `ALifeKnoxCountyRadio.lua` & `ALifeRumors.lua`

#### EmberRoutes 落地规范
1. **接驳原版无线电波段（Radio Broadcast Integration）**：
   * 设立民用商道广播频道（如 `92.4 MHz - 余烬商路公频`）；
   * 宏观事件触发时，向全图广播原生文字简讯：
     * *求援*：“31W 公路加油站附近，西点商队抛锚求援，车队载有高级工具与罐头，急需机械师与护卫！”
     * *行情*：“马尔德劳木材过剩，急缺抗生素与酒精，据点提供双倍兑换率。”
     * *路况*：“罗斯伍德北侧收费站出现密集尸群与武装路霸，建议商队绕行西侧林道。”
2. **沉浸式涌现任务**：
   * 玩家收听电台后，可选择前去解救、做中间商赚差价或绕开危险，真正实现“活着的世界”。

---

## 4. 落地步骤与门禁

1. **第一阶段（当前 P1/P2）**：保持现有 P1 单人单执行者与 P2 生活自理开发，先在友方 NPC 验证 TimedAction 与工单接单稳定。
2. **第二阶段（商队与宏观路网）**：引入公路节点图与 `RenderProtocol` 视锥检测算法，打通货运车位的出入场。
3. **第三阶段（野外威胁与强盗）**：全面接入 `Zombie Shell` 傀儡架构，制作 2~4 人战术路卡与商队护卫，实现高性能武装交火。
4. **第四阶段（无线电网络）**：挂接原版 `RadioChannel`，完成商路宏观事件的自动传报。
