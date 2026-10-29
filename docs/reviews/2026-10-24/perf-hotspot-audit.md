# 0.26.0 全项目性能热点定位报告

日期：2026-10-24｜状态：静态审计 + 两份实测采样交叉定位；修复与复测未开始。
分支：experiment/modern-ae2-ui｜version.txt=0.26.0（工作区，未提交）。

任务：用户要求全项目性能优化，第一步定位所有需优化点；允许不严重破坏逻辑的大范围改动、可控破坏性检验与激进策略，并评估第三方依赖。本文档只做定位与分级，不改代码。

## 实测基线（两份 20 秒采样对比）

| 指标 (ms/秒) | 0.24.7（[旧采样](live-performance-and-haul-interruption.md)） | 0.26.0（用户 2026-10-24 20:57 实测，console.txt 行 1917-1944） | 变化 |
|---|---:|---:|---|
| Boot 累计 | 37.766 | **95.275** | +152% |
| 最大单 tick | 16.936 | 3.713 | 改善 |
| tick 边界窗口峰值 | 57.662 | **144.819** | +151% |
| Tasks | 5.853 | **40.737** | **约 7×** |
| SelfCare | 3.135 | **30.499** | **约 10×** |
| Persistence | 6.551 | 7.330 | 持平 |
| PublicWork | 7.826 | 1.612 | 改善（本场景派工少） |
| 其余分桶（Actions/Haul/Logistics/Crafting/CraftView/Companion/Work/Retirement/Java） | — | 合计 ≈4.3 | 均低 |
| 未分项（入口调度+采样） | ≈10.2 | ≈10.7 | 持平，仍未测空采样基线 |

结论：0.24.7→0.26.0 的新增回归集中在 **Tasks 与 SelfCare 两个桶**（合计 71.2/95.3 ms/s），对应 P2 生活主循环与 P3/P3.5 人员-研习-消遣-社交代码。max_tick 变小、窗口峰值变大，说明当前是**持续性高负载**而非单点尖峰。旧采样里的 PublicWork 尖峰问题（16.1ms 单次）本场景未复现，但其结构性成本仍在（见 P1-4）。

## P0 —— 实测大头，机制已定位到行

### P0-1 Tasks 桶：执行中任务每帧深拷贝 JobStore + 每帧桥接调用

每条链都已源码确认；频率乘数为"每执行中 NPC × 每游戏 tick（约 149/s）或每渲染帧"。

1. **引擎每帧调 `action.isValid` → `active()` → `c.valid()` → `c.sameAttempt()` → `Jobs.current():get(job.id)` = `JobStore.get` = 全记录递归深拷贝**（`detached()`，含 budget 计数与 seen 环表分配）。
   - [JobStore.lua:68](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/JobStore.lua) `function api:get(key) return data.byId[key] and detached(data.byId[key]) end`
   - 调用链：`LeisureTimed.lua:7-8`（active）、`LeisureSmoke.lua:36-37`（active，SMOKE 每帧 isValid/update/complete/stop 均触发）、`SelfCareExecution.lua:17-21`（sameAttempt）、`StudyActions`/`SelfCareFurniture` 同构。
   - 同一 tick 内被调用 1–3 次（Tree.tick 的 move 叶 `LeisureActions.lua:6` 再来一次），引擎帧再来 1 次。
2. **`c.body.retained()` → `stopEvidence` → `EmberRoutesProbeJava.bodyStopMask` 桥接，每帧每执行中任务**（`TaskController.lua:112`、各 action 包装器）。
3. **`TaskRuntime.advance` 每 tick 每 NPC**：`controller:inspect` 每次分配新表（`TaskRuntime.lua:144`），紧接着 `controller:state` 再查一次（`TaskRuntime.lua:189`）；`observeStop` 路径 `luaStopped` 查 `ISTimedActionQueue.queues`。
4. **SelfCare `safe` 闭包每 tick 调 `getSurroundingAttackingZombies(false)`（僵尸邻近扫描桥接）**：`SelfCare.lua:62-65`，经 `SelfCareExecution.spec.tick → c.valid()`（`SelfCareExecution.lua:32`）每 tick 执行。
5. 修复方向（激进）：JobStore 增加 `peek(key)` 只读 live 引用（写路径保留 detached 验证）；action.isValid 改查本地缓存布尔，由 Job 修订号/停止事件失效；inspect/state 合并；safe 僵尸扫描 100–250ms 节流缓存。

### P0-2 SelfCare 桶：每 tick 64 泵设施扫描 + 200ms 空闲发现循环重跑

1. **`SelfCare.tick` 每 tick 无条件执行 `SettlementFacilities.tick(64)`**（`SelfCare.lua:340`，注释自述在时间门之前）。每泵最多触发 `getCell`/`getChunkForGridSquare`/`getGridSquare`/`getObjects`/`describe`（instanceof + SeatingManager + properties，`SettlementFacilities.lua:96-157`）。玩家移动时 `LoadGridsquares`/`OnObjectAdded` 持续打脏（`:183-211`），使 64 泵长期满载：约 9600 泵/秒 × 每泵多次桥接。空闲（全部扫完且无脏）时退化为 1 次 `getTimestampMs` + 快速返回，成本低——**成本与玩家移动/世界变化正相关**。
2. **空闲发现循环每 200ms 每 NPC 重跑**（`SelfCare.tick` 轮转 4 人 → `advance`，`SelfCare.lua:352-368`）：`Companion.exportState`（每次分配新表）→ `Policy.choose` → `StudyService.candidate`/`LeisureService.candidate`。`LeisureService.candidate`（`LeisureService.lua:72-151`）单次含：`Ledger.view`（拷贝+桥接，见 P1-2）、`Service.sample` 全量桥接（getStats/getBodyDamage/getBodyParts 循环/getFitness stiffness×4 部位，`LeisureService.lua:36-57`）、`standable` → `getGridSquare`+square 属性检查+`getMovingObjects` 扫描、社交 `canReachTo` 寻路桥接最多 ×8（invite choose 4 方向 ×2 点，`LeisureService.lua:92-97`）、`Facilities.advance(8)` 再泵、`Policy.choose` 加权。**发现失败（nil,true）无冷却即整段重跑**；`StudyService.offer` 15 秒、`LeisureService.offer` 3 秒存续期内持续重扫。
3. 活跃 LEISURE/STUDY 任务每 200ms 还会被 `SelfCare.advance` 的 `LeisureService.valid`/`StudyService.valid` 再各做一次 `Ledger.view` + `exportState` + `getX/getY`（`SelfCare.lua:163-175`）。
4. 修复方向：设施扫描改"有 pending/dirty 才泵"+事件驱动唤醒；发现失败加 1–2 秒冷却；`Service.sample` 结果 1 秒缓存；`exportState` 返回共享只读快照。

### P0-3 Persistence 桶 7.3ms/s：机制未细分（待测）

空闲快路径已很薄（`Persistence.lua:43-44`），采样时段含保存回执核对（managed tick + restoreQueue）。平均 0.049ms/tick、最大 0.327ms，无尖峰。定位动作：细分 `managed().pending()` 与回执核对各自占比（见测量计划）。优先级低于 P0-1/2。

## P1 —— 结构性成本，当前场景量级未测（含旧采样已证实的 PublicWork 链）

4. **SettlementLedger 完全无缓存，且是全模组通用依赖**：
   - `Ledger.data()` 每次调用 = `ModData.getOrCreate` 桥接（`SettlementLedger.lua:12-18`）；`Ledger.at()` 内部先 `Ledger.list()`（全据点逐条深拷贝 + 按面积数组拷贝 + 排序），循环内每条再调一次 `Ledger.data()`（`:46-52`）。
   - 调用方：`PublicWork.eligible`（`:349`）——每 200ms 每候选 + 每 tick 每在途 evaluation（`PublicWork.lua:504-507,527`）；`eligible` 还含 `Driver.bindId`/`getCharacterActions`/`getBodyDamage` 桥接与 `blocksWork`→`forNpc` 拷贝。0.24.7 旧采样 PublicWork 16.1ms 单次尖峰即疑似此链（当时在途 evaluation 每_tick_谓词重评）。本场景未复现，但结构未变，集中派工时仍会回潮。
   - 修复方向：根表 world-epoch 缓存；`at()` 按 settlements revision 缓存；内部改 live 迭代不拷贝。
5. **ContainerRegistry.data() 同样无缓存**（`ContainerRegistry.lua:48-49` 每调用 `ModData.getOrCreate`），被所有服务的 `load()`/`Store.data()` 每 tick 多次调用，系统性放大。修复：与 Ledger 一起做根表缓存。
6. **`Service.orders(scope)` 每次全量拷贝 + 排序**（`PublicWork.lua:179-185`）：每次 `decide`（每 200ms 每就绪工人）调用；`OrderMonitorService.status` 每次重建也调用（`OrderMonitorService.lua:97`）。修复：按 (scope, sequence, revision 签名) 缓存或返回 live 只读列表。
7. **JobStore 写路径双深拷贝**（`update`：`detached(old)` + `detached(candidate)`，`JobStore.lua:105-110`）——防篡改/序列化验证边界，项目红线决定不能简单删除；修复方向是验证与拷贝合并为单次遍历，或将"可序列化检查"改为惰性（保存屏障时才做）。
8. **WarehouseIndex.advance 每 tick 每 ctx 两次 `Ledger.data()`**（`WarehouseIndex.lua:119-122`）——属 P1-4 同根问题；该 tick（OnTickEvenPaused）本身不在 RuntimeMetrics 采样内（盲区）。

## P2 —— 次级结构问题与 UI

9. **OrderMonitor 全量投影重建链**（仅监控页打开时）：`Signals.watch`/容器事件 → `CraftingService.markDirty` → 下一 tick `Service.status` 全量重建 → `OrderMonitorService.status` 再全量投影（每行 `Driver.bindId`×2 桥接 + `exportState` 分配 + HAUL 行 `ItemDisplay.types` + `getItemNameFromFullType` + 字符串拼接 + 排序，`OrderMonitorService.lua:24-109`）。派工活跃时 Signals 变更频繁，UI 打开期间可能每秒多次全量重建。修复：行级修订号差分更新。
10. **PublicWork.stock() 每 200ms 重建**：rules 数组重建 + 排序 + 重叠规则的 `Membership.query` + `Ledger.view` + `Index.candidates`（`PublicWork.lua:220-260`）。修复：rules 按 revision 缓存排序结果。
11. **测量盲区——三个独立 OnTickEvenPaused tick 不在采样内**：`WarehouseIndex.step`（`WarehouseIndex.lua:269`）、`StockService.tick`（`StockService.lua:456`）、`CraftingService.readTick`（`CraftingService.lua:184`）。前两者空闲快路径便宜、dirty 门控存在，但真实成本从未被 RUNTIME_PERF 覆盖。修复：纳入统一采样或各自计时。
12. **reconcile() 每 200ms 全订单扫描**（`PublicWork.lua:261-291`）：有 jobId 订单时 `records('CRAFT')` + `Runtime.current():status` 逐条。修备：按 jobId 索引。
13. **UI 每帧桥接零星点**：`StockRules.prerender` 每帧 `ScriptManager.instance:getItem`（`UI/StockRules.lua:533+`）；`PublicOrderDialog.prerender`/`CraftingBrowser.prerender` 每帧 `MeasureStringX` + 页码字符串拼接（`:828+` / `:213+`）；`UICache.measureText` 的 `tostring(font)` 键本身每帧分配、`measureCache` 无上限增长（语言切换/大量物品名时泄漏型缓存）。UI 整体渲染成本是**采样盲区**（RuntimeMetrics 不覆盖 draw）。
14. **Observer.sample spotted-list instanceof 循环**（`NeedsObserver.lua:23-29`，≤64 次 instanceof/调用，1 次/秒/NPC）——可下沉 Java 一次返回。
15. **Library.revalidate 每候选线性 `getItems():contains`**（`LibraryIndex.lua:50`）；LibraryIndex 主体已有 10 秒缓存与预算切片，尚可。
16. **LeisureTimed OBSERVE 每帧 `getSquare`+`getObjects():contains`**（`LeisureActions.lua:36-41` hooks.update）——可 500ms 节流。

## P3 —— 小额分配/杂项

- `Driver.bindId` 每调用分配 `{handle,id}` 新表（热路径高频）；`Companion.exportState` 每次分配新表且被 eligible/valid/candidate 反复调用。
- `BehaviorTree.tick` 每调用分配 `run` 闭包（`BehaviorTree.lua:28`）；`decide` 内 `Wake.capture` 每扫描订单分配。
- `SelfCare.tick` 有死代码重复 `now<nextTick` 检查（`SelfCare.lua:342,347`）。
- RuntimeMetrics 采样自身 ≈30 次 nanotime/tick（仅采样期）+ `Boot.tick` 采样期 12 次字符串拼接查服务（`Boot.lua:127-131`）；非采样路径干净。
- `Service.priorities` 每调用新表（`PublicWork.lua:113-116`），decide/eligible 高频调用。
- DispatchMetrics 每 tick 2 次 `getTimestampMs`（`PublicWork.lua:537-539`）。

## 测量盲区清单（细分前先补）

1. UI 渲染/绘制总成本（RuntimeMetrics 完全不覆盖；ZBLuaPerfMon 的入口行亦不含模组 UI 内部拆分）。
2. 三个独立 OnTickEvenPaused tick（P2-11）。
3. Java `EmberRoutesProbeJava.tick()` 内部构成（Java 桶 0.618ms/s，小，但 bodyStopMask/carrierFor 等散布调用不计入此桶）。
4. GC/分配压力：所有深拷贝/闭包/字符串证据均为静态推断，无 GC 关联数据。
5. 空采样基线（未分项 ≈10.7ms/s 的采样自耗部分）。
6. SelfCare 桶内 Facilities/LibraryIndex/LeisureService/StudyService 无独立分项（BACKLOG P1 已知，仍未拆）。

## 建议的修复顺序与激进策略（待用户批准后执行）

第一梯队（预计覆盖 Tasks+SelfCare 大头，改动集中在少数文件）：
1. JobStore `peek()` 只读 live 视图 + isValid 本地缓存布尔（P0-1.1）。
2. 设施扫描改事件驱动泵（P0-2.1）。
3. 发现失败冷却 + sample 缓存（P0-2.2/3）。
4. Ledger/Registry 根表缓存 + `at()` 修订缓存（P1-4/5，一并消除 P1-8）。

第二梯队：Service.orders 缓存、safe 僵尸扫描节流、inspect/state 合并、OrderMonitor 差分、UI 零星每帧桥接、采样分桶改造（Facilities/LibraryIndex/LeisureService 独立计数、纳入三个独立 tick、空采样基线）。

**第三方依赖评估**：PZ 的 Lua 宿主（Kahlua）是沙箱，无法加载原生 Lua C 模块或第三方 Lua 库；唯一现实的高速通道是本项目已有的 Java 侧车 JAR（`EmberRoutesProbe.jar`），且 0.24.5 已验证"Java 只读批量下沉"模式（192 次桥接 → 3 次）。结论：**不引入第三方运行时依赖**；值得下沉到 Java 的候选：bodyStopMask 批量/缓存、僵尸邻近+spotted 合并单次调用、Ledger 根表句柄。测量工具沿用自有 RuntimeMetrics（扩展分桶）+ 用户现有 ZBLuaPerfMon，无需第三方。

## 第一梯队实施记录（2026-10-24 同日）

以下改动已接并全部通过回归与门禁；游戏实测复测未跑，效果比例未验证。

| 修复 | 文件 | 内容 |
|---|---|---|
| P0-1.1 | JobStore.lua | 新增 `api:peek(key)` 只读 live 视图；写路径与对外 `get` 的 detached 边界不变 |
| P0-1.1 | SelfCareExecution.lua | `sameAttempt`/`persist` 改走 peek（对被替换的 TaskJobs 桩回退 get）；`safe` 僵尸扫描加 200ms 记忆（设计本身容忍 1 秒 observe 采样陈旧） |
| P0-1.3 | TaskRuntime.lua | `advance` 热路径改 state-first，仅离开 ACTIVE 才取完整快照，消除每 tick inspect 表分配 |
| P0-2.1 | SettlementFacilities.lua | `tick` 只泵有未完成工作/脏块/unknown/limited/重扫到期的行；15 秒重扫安全网保留 |
| P0-2.2 | SelfCare.lua | 空闲发现循环增加 1.5 秒退避（两个 provider 均"已结算且无结果"才退避，预算未耗尽不退避）；移除 `tick` 内死代码重复时间门；Facilities 调用在采样期单独计入 `Facilities` 分桶 |
| P1-4 | SettlementLedger.lua | 新增 `scopeAt(x,y)` 内部 live 定位（不拷贝/不排序/不做 actor 鉴权）；`at()` 提升循环内重复 `Ledger.data()` |
| P1-4/6 | PublicWork.lua | `eligible` 改用 `scopeAt`（对仅含 view/at 的替换桩回退 `at`）；`decide` 的订单扫描改用 id+sequence 投影缓存（create/retire 失效；世界切换按 data 身份失效）；对外 `Service.orders` 拷贝语义不变 |
| P1-8 | WarehouseIndex.lua | `advance` 循环内两次 `Ledger.data()` 提升为单次 |

明确放弃/延期的项与原因：
- **Ledger/Registry 根表缓存**：`settlement-storage-test` 通过替换 getOrCreate 后备表模拟世界切换且 ModData 函数身份不变，任何进程内缓存都会返回陈旧根、破坏"立即检测世界切换"断言。需要先设计世界纪元令牌协议（Boot 持有、注册表订阅），列入第二梯队前置项。
- **LeisureService.sample 记忆化**：p35-discovery-test 直调 `Service.candidate` 并在调用间修改传入 sample（静态 mock 时钟），记忆化会改变其语义；且该函数每次发现的绝对成本小（约 15 次桥接 × ≤5 次/秒），收益不值得破坏契约。
- **body.retained()/bodyStopMask 帧级缓存**：`perform/stop` 路径用它做原件权威门禁，陈旧值可能在失去身体控制后放行一次原生效果，触碰实现红线；仅减少其邻接成本（深拷贝已由 peek 消除），不做时间缓存。
- 第三方依赖结论不变：不引入。

验证记录：
- Kahlua 回归 19 套件通过（job-store 35 项、task-runtime 61 项、self-care-loop 20 项、self-care-service 11 项、p35-execution、p35-discovery、public-work、settled-task-retirement 18 项、runtime-idle 2016 项、settlement-storage 77 项、task-read-performance、dispatch-performance（1/16/32/64 人模拟开工均 125ms 维持）、p3-study 27 项、p3-personnel-relief 12 项、repose-execution、repose-sites、self-care-resume 27 项、self-care-observation 15 项、self-care-repose 10 项）。中途曾出现两处桩兼容问题（ordersIdsCache 声明顺序致 nil 索引；Ledger 桩缺 scopeAt 致派工故障门关闭），分别以声明前置与等价回退修复后全绿。
- preflight（安装版 Kahlua 四层）全部通过；doclink 0 断链。
- **游戏内 20 秒采样复测未运行**：预期 Tasks/SelfCare 两桶显著回落，但比例必须以实测为准，改前不宣称任何倍数。

## 第一梯队复测与第二梯队 a 组（2026-10-24 晚）

复测采样（用户实机，载入后前 20 秒窗口）：Boot 95.275→**52.566**ms/s、窗口峰 144.819→**64.388**、Tasks 40.737→**5.726**（−86%）、SelfCare 30.499→20.143（其中新增 Facilities 分桶 12.608 单列）、Persistence 8.831、PublicWork 3.819、分项合计大于 Boot 的差值为 Facilities 嵌套计数（SelfCare 含 Facilities）。此窗口含载入恢复（恢复队列逐 NPC `restoreCheckpointFor`、设施首次全量扫描、首轮派工对账），Persistence 与部分 Facilities 属一次性成本；稳态数值待站立静置 30 秒后的复测采样。

第二梯队 a 组（已接，12 套件回归 + preflight 通过）：
- Facilities 重扫间隔 15s→60s；tick 门控修正——unknown/limited/apiUnavailable 是"上报状态"而非"待做工作"，不再触发盲泵（区块加载与对象事件本身会推脏块）。
- `LeisureService.valid`/`StudyService.valid` 的 200ms 周期复检改走 Ledger live 成员判定（faction+几何），消除每轮一次的 detached 拷贝与 actor 重鉴权桥接；被替换的 Ledger 模块无 `data()` 时回退旧 `view()`。

Java 三方依赖评估（针对"优化过的 map 等"）：当前 Java 侧成本仅 0.591ms/s，热点数据都在 Kahlua 表里，Java 集合库不是瓶颈；fastutil/Eclipse Collections 可 shade 进 EmberRoutesProbe.jar，但只在把热循环下沉为 Java 自有索引（如原生声明账本、批量僵尸邻近扫描缓存）后才可能产生可测收益，届时再引入，不预支依赖。

距 30ms/s 目标缺口（~23ms/s）的构成与预期：Facilities（60s 重扫+门控修正后应降至 ~3-4）、载入恢复一次性成本（稳态归零）、SelfCare 剩余（valid 复检已省）、未分项 ~9.7（含采样自耗与入口调度，需空采样基线区分）。

## 第二梯队 b 组：Java 下沉（2026-10-24 晚，已接）

复测确认第一梯队+a 组后稳态预估仍在 30-40，不足 30ms 目标；本轮新增两个原生只读接口（沿用 0.24.5 下沉模式，Lua 保留 noop 桥/旧 JAR 回退路径，均不进入 Boot.validateJava 必需清单）：

1. **`observerSample(IsoPlayer)`**（新类 `ObserverReads.java`）：一次调用返回 hunger/thirst/fatigue/endurance/pain/health/onFire/attacking/spottedThreat。替代 NeedsObserver 每次 5 次属性桥接 + spotted 列表逐项 instanceof（≤64 次）+ 火焰/邻近僵尸扫描的 Lua 链；Java 侧 instanceof 为纳秒级。spottedThreat 键缺省=UNKNOWN，与原 Lua 契约一致；健康窗口（RECENT_DAMAGE）状态留在 Lua。
2. **`cachedModData(key)`**（ProbeRuntime）：`GlobalModData.instance.getOrCreate` 根表句柄缓存，`begin()`/`reset()` 清空。Registry.data 与 Ledger.data 优先走它——这解决了此前延期的"根表缓存破坏测试夹具"问题：测试的 noop 桥返回 nil 自动回退 `ModData.getOrCreate`，而生产环境的清空时机由 Java 世界生命周期保证，Lua 侧 `root~=world` 身份比较语义不变。

采样细分：SelfCare 桶内新增 `SCAdvance` 分桶（200ms 发现/复检轮与桶内固定开销分离；Facilities 已独立）。

工程注记：`tools/build-probe.ps1` 必须用 pwsh 7 运行——PowerShell 5.1 会把 JDK 25 的 restricted-method/LWJGL stderr 警告当错误中止（本轮踩过）。构建产物 `EmberRoutesProbe.jar` 已重建并复制到 mod media/java（2026-10-24 21:59），版本仍 0.26.0；**新 JAR 必须完全重启游戏才生效**。

验证：build-probe.ps1 全部 Java 测试通过（65+42+41+authority+baseline+override 类加载+11 迁移+13 回执+回调边界+30 安装版原生读取）；19 个 Lua 套件全绿；preflight 全过。游戏实测未跑。

后续下沉候选（按预期收益排序，未实施）：Facilities 区块扫描下沉（一次 Java 调用替代每泵 getGridSquare/getObjects/classify 桥接簇，Facilities 稳态剩余的主刀）、bodyStopMask 每 tick 批量化、LeisureService.sample 的 fitness/stiffness 批读。fastutil 等 Java 集合库仍判定为不预支：现有 Java 侧数据结构未成为瓶颈（Java 桶 0.591ms/s），待上述下沉落地、Java 自有索引成形后再评估。

## 第二梯队 c 组：测量升级与零星热点清扫（2026-10-24 晚，已接）

1. RuntimeMetrics：每桶调用直方图，END 输出 p95/p99；新增 `measureSpan`（带返回值包装）与 `epoch`（采样会话代号，供调用方按会话缓存）；Boot 采样循环的服务函数表按会话缓存（消除每 tick 12 次字符串拼接）。
2. 三个独立 OnTickEvenPaused tick 纳入采样：`WarehouseIndex`/`Stock`/`CraftRead` 独立分桶，补上盲区。
3. LeisureActions OBSERVE 目标存在性检查节流 500ms（原每帧 getSquare+getObjects:contains）；失败判定最多延迟同窗口，语义包络不变。
4. PublicWork.stock() 启用规则排序缓存（saveRule 递增 revision、世界根身份双重失效）。
5. UI 每帧测量桥接清扫：PublicOrderDialog 换算卡 4 处与页码、CraftingBrowser 页码改按内容键缓存 MeasureStringX；StockRules 详情物品名按 (id,revision) 缓存 ScriptManager.getItem；UICache.measureText 字体键改二级表键（移除每帧 tostring(font)）。

验证：12 个相关套件（runtime-idle/public-work/stock-service/stock-rules/settlement-ui/recipe-chain-ui/p35-execution/p35-discovery/settlement-storage/warehouse-query/self-care-loop/task-runtime）全绿；preflight 全过；游戏复测未跑。

## 第二梯队复测与 safeRecent 回归修复（2026-10-24 深夜）

复测采样（36.88 秒窗口，含 2c 全部改动）：Boot 95.405ms/s——但 **Tasks max_ms=2443**：`PERSONAL_AUTHORITY_LOST` 硬错误触发 2 次，Kahlua 异常堆栈捕获+打印单次吃掉约 2.4 秒，把窗口从 20 秒拖到 36.88 秒并贡献了约 66ms/s 的平均值。**剔除该尖峰后稳态 Boot ≈ 29.4ms/s，30ms 目标在健康路径上已达成**。各桶：Facilities 12.6→5.105（p95=0.090）、SelfCare 8.867（含嵌套 SCAdvance 1.555，93 次）、Persistence 4.200、PublicWork 1.837（p99=0.690）、新增 Stock 0.451 / CraftRead 0.847、其余 <0.6。

回归根因（本报告作者引入）：P0-1 的 200ms 安全记忆会缓存 false——当 `spec.tick` 的新鲜 safe() 前置检查已恢复通过而 `c.valid()` 读到缓存的 false 时，健康执行被误判权威丢失，走进 `error('PERSONAL_AUTHORITY_LOST')` 路径。修复：**只记忆正结果**（false 永不缓存，新鲜检查保持权威）。9 个相关套件 + preflight 通过。教训入档：①否定结果不得进此类快照缓存；②Kahlua 异常堆栈捕获在深 pcall 链下单次数秒级，每 tick 路径上的 error() 应仅留给真正的不可恢复条件。

## 修复后干净采样与最后一轮插桩（2026-10-24 深夜）

safeRecent 修复后的干净 20 秒采样：**Boot 28.866ms/s（30ms 目标达成）**、窗口整 20.00 秒、max_tick 3.726ms、PERSONAL_AUTHORITY_LOST 0 次。分桶：SelfCare 10.132（含 SCAdvance 1.823）、Facilities 5.561、Persistence 5.057、PublicWork 2.405、Tasks 3.507、其余 <0.8。**用户体感的 80ms 对应 peak_tick_window_ms=75.172**——无单点尖峰，是某一秒内多个小突发（发现轮 p99 2.6ms、PublicWork p99 0.85）的叠加；Persistence 稳态 5ms/s 与"空闲应≈0"的预期不符，静态读码无法定位卡住的门条件。

为此加的最后两项插桩（8 套件+preflight 通过）：
1. RuntimeMetrics 每桶 `peak_win_ms`：复用全局 1 秒窗口翻转给各桶累计，零额外时钟调用——下一份日志直接回答"最差的那一秒是谁"。
2. Persistence 慢路径拆为 `PersistWork` 独立分桶 + 每 ~300 次入口记一条 `SLOW_PATH gate=RESTORE_PENDING/RESTORE_QUEUE/LEGACY_STOCK/MANAGED_PENDING` 诊断（计数器节流，不引入时钟全局——首个版本用 getTimestampMs 被 runtime-idle-test 击落，测试环境未定义该全局）。

## 00:05 采样判读与 ModEvents 插桩（2026-10-25 凌晨）

用户报告单倍速仍约 100ms 并提供新采样：**模组 Lua 合计仅 5.966ms/s（每帧约 0.28ms）**，但窗口被拖至 48.94 秒、仅 1045 tick（约 21 FPS），且采样发生在世界载入后早期（START f:827，恢复日志在 f:1-3）；同一会话菜单阶段为 109.8 FPS——**拖帧在模组 Boot 之外**（pzopt 烘焙/流式预热或模组外入口）。Persistence 悬案同帧解开：`SLOW_PATH gate=RESTORE_PENDING entries=1`——载入后仅一次慢路径，稳态 1.26ms/s。模组内剩余可见项：一个突发秒 CraftRead 31.8ms + Stock 16.6ms（合成目录/仓储churn 同秒，待确认是否 UI 开启）。补上最后盲区：模组事件处理器（LoadGridsquares/OnObjectAdded/Removed/OnContainerUpdate → 设施与仓储失效）以 `ModEvents` 分桶计量（仅采样期计费）。7 套件+preflight 通过。待用户：载入后静置 2-3 分钟再采样；提供 pzopt 叠加层/ZBLuaPerfMon 当时 top 条目名称与数值。

## 监视器归因与 EvenPaused 合并（2026-10-25 凌晨）

用户提供 ZBLuaPerfMon 截图：模组名下约 79ms/s——而模组内部采样同场景仅约 6ms/s。主假设为**观察者效应**：pzopt/LuaEventProfile 对每次事件调用做包装记账，开销记在被包装入口名下；本模组当时有 1 个 OnTick + 4 个 OnTickEvenPaused（161 次/秒×3 个读服务 + retirement）+ 事件风暴期的设施/仓储处理器，约 500+ 次/秒被剖析调用 × 每次零点几毫秒 ≈ 79ms/s。

对策（已接，15 套件+preflight 通过）：
1. 新增 `shared/EmberRoutesProbe/EvenPaused`：全模组唯一的 OnTickEvenPaused 分发器；retirement、WarehouseIndex.step、StockService.tick、CraftingService.readTick 全部并入——被剖析高频入口 4→1。（第一版把分发器放 Boot 里，被 WarehouseIndex 的 require 连带拉起 Boot 尾部事件注册、在不完整 Events 测试桩下崩溃；独立无副作用小模块解决。）
2. 修正上一轮自身回归：ModEvents 插桩的 per-event `require` 提升为模块级缓存（事件风暴期 require 本身会成为热路径）。

待用户验证观察者效应：同一场景监视器叠加层开/关各测一次（FPS + 体感 + 我们自己的 20 秒采样）。若关闭后帧率显著回升而模组采样数字不变，则 79ms 为剖析开销归因，模组侧可收口。

## 决定性采样与 require 热路径修复（2026-10-25 00:28）

稳定会话（00:19 载入、单倍速 81.7tps、整 20.00s 窗口）最终分解：**模组合计 32.96ms/s（基线 95.3），最差秒 70.1**。Facilities 0.219（自 12.6 起已治愈）、事件处理器 ≈0（无 ModEvents 行）、even-paused 合并后 163 次/秒单入口（Stock/CraftRead 合计 1.16）。真实热点：**Tasks 15.20**（每 tick 约 0.19ms 的执行推进常价，p95=0.233，最差秒 32.2——现为最大真实桶，候选对策为消遣推进隔 tick 节流，属玩法权衡）、SelfCare 3.88+SCAdvance 1.21、PublicWork 2.14、**Persistence 4.32——根因找到：快路径门内 `managed()` 每 tick 走 Kahlua require 机制（字符串拼接+装载器查找）约 0.05ms/tick；慢路径根本没跑（无 PersistWork 行）**。修复：Persistence `managed()` 改预建键直查 package.loaded（`_G.package` 守卫过 lint，require 兜底）；三个 tick 包装器与 WarehouseIndex 的每调用 require 一并提升为模块级。预期合计再降 5-6ms/s 至约 27。4 套件+preflight 通过。监控器 ~100 与实测 33 的剩余差额 = 面板绘制（待用户确认开/关）+ 每入口派发/剖析开销 + 监视器读数偏峰值秒（我们最差秒 70+开销≈100 量级吻合）。

## 监视器归因定案与分发器降频（2026-10-25 01:00 后）

用户关键事实：监视器在 1× 与 2× 倍速下均显示模组 ~100ms——而模组实测工作量两倍速下翻倍（33→63.5ms/s，2× 采样 ticks=165/s 证实）。**监视器数字不随实际工作量变 ⇒ 其计费主体是入口调用本身**：even-paused 按帧派发（三次采样恒 163 次/秒、与倍速无关——正解释两倍速同读数），本模组因"暂停可读"特性入口调用率 ~245-330 次/秒（典型 mod ~80），按每调用 ~0.3-0.4ms 包装记账得 ~80-100 vs 别模 ~20-30，与用户观察一致。Persistence 修复经 2× 采样确认生效（4.0→0.658）；EngineActions 行在 NPC 非动作期 ≈0，账本自此无盲区。

对策：EvenPaused 分发器每 3 次派发执行 1 次（~54Hz，读取服务预算切片型无感知）——入口调用面再降约 40%，监视器口径下预期 ~100→~70；7 套件+preflight 通过。最终用户自验（无需回报数据）：关闭监视器叠加层同场景对比体感——若无明显变化，~100 为监视器记账而非玩家体感延迟。模组真实成本现状：1× ≈ 32ms/s（2× ≈ 63），其中 Tasks（0.18ms/tick 推进常价）为最大真实桶，隔 tick 节流方案待用户批准。

## 收口三刀：Tasks 墙钟步调 / 倍速封顶 / SelfCare 固定段（2026-10-25 凌晨，用户批准"全部试试"）

1. **TaskRuntime 业务推进墙钟步调（pace=18ms，仅游戏路径）**：状态迁移/停止清理/准入保持每 tick；仅 spec.tick+finished 对按墙钟限频。1×（12ms/tick）≈隔 tick；2×（6ms/tick）≈每 3 tick 一次——同一机制同时实现隔 tick 化与倍速封顶。直构 Runtime（测试）默认 pace=0 保持旧行为；宿主无 getTimestampMs 全局时退化为合成步进时钟（不门控），task-save-runtime 因此无需改夹具。
2. **SelfCare 固定段瘦身**：单次取钟传给 Facilities.tick(64,now)（可选参数，缺省内部取钟，直调测试兼容），消除每 tick 重复桥接。
3. 预期：1× ~32→~20-22ms/s（Tasks 15→~7.5）；2× ~63→~35-38。NPC 动作推进粒度变为 18ms 墙钟，肉眼不可辨。23 套件+preflight 全绿；游戏复测未跑。
4. NPC 本体引擎模拟成本不在 Lua 口径内：用 pzopt game-thread profile（叠加层开着时 25Hz 采样）读 IsoPlayer/ProbeNpc 帧的占比，属引擎侧观察项。

## 验证方式（对应 BACKLOG P1 验收要求）

每梯队改完跑：固定场景（同一存档、同 NPC 数、同箱子规模、UI 开/关两态）× 20 秒采样，记录每桶 ms/s、P95/P99/最大值（需先给 RuntimeMetrics 加分位统计），1/5/10/20 NPC 分档；目标 Boot <50ms/s 且窗口峰值显著回落。所有本报告静态结论在复测前均标注"未测量证实比例"。
