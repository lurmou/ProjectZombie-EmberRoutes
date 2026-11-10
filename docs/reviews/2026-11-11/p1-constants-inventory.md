# P1 常量集中：魔法数字与量纲混用清单

基线：main `58b9abf`（2026-11-11）。路径以仓库根为基准；
`L = Contents/mods/EmberRoutesProbe/42/media/lua/`，`J = java/src/main/java/emberroutes/probe/`。
审计方法：先读“Ember Routes 项目整理”旁聊里的魔法常量与量纲审计报告
（基线 5963368），再逐项在 58b9abf 上 grep/读码复核；凡写“已核实”均在
本基线核实过，拿不准的标 UNVERIFIED。

配套实现：`L/shared/EmberRoutesProbe/Kernel/Constants.lua`（中央常量/量纲表，
JobState 注册表同款模式：一个词表、一个读法），
`L/shared/EmberRoutesProbe/Kernel/TickConfig.lua`（节拍表扩充）。
测试：`tests/lua/constants-test.lua`。

## 0. 已核实的前提（复核 58b9abf）

- SupplyEstimate 的 0.6/2.0 已是命名常量（`DAILY_FOOD_PER_PERSON` /
  `DAILY_WATER_PER_PERSON`），P0 报告的 `pop * 2.0` 绕过 bug 已修
  （`foodDailyDemand = dailyFoodDemand`）。**不动。**
- “STRESS /100 量纲不一致”不存在：全库无对 STRESS 的 /100 处理。
  ActivityRelief 守卫、LeisureService 采样、SocialActions 写回三处量程一致。
- 量纲实测（代码自证）：0–1 的是饥饿/口渴/疲劳/耐力/压力/士气，
  0–100 的是无聊/不开心/疼痛/恐慌。证据：
  `Activity/ActivityRelief.lua:48-53` 守卫（BOREDOM/UNHAPPINESS ≤100，
  STRESS ≤1）；`Integration/NpcDebugMenu.lua:115-119,145,151` 滑条步长
  （PAIN/PANIC/BOREDOM/UNHAPPINESS 步长 1，HUNGER/THIRST/FATIGUE/
  ENDURANCE/MORALE/STRESS 默认步长 0.01，上下限取原生 enum 自身
  `getMinimumValue()/getMaximumValue()`）；`Leisure/LeisureService.lua:108-110`
  采样（PAIN/BOREDOM /100，STRESS 不除）。
  MORALE 与 PANIC 在本仓库无任何按量纲使用的读写点（只读原值展示），
  其量纲取自上述滑条步长，**未对 jar 逐项核对，标 UNVERIFIED**。

## 1. 收掉的（调用方改读中央表 / 所属模块表）

### A. 量纲表 → `Constants.Stat`

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| PAIN/BOREDOM `/100`，STRESS 不除，无注释 | `client/.../Leisure/LeisureService.lua:108-110` | `Stat.toUnit('PAIN'/'BOREDOM'/'STRESS', v)` |
| 守卫 `>100` / `>1` 手写 | `client/.../Activity/ActivityRelief.lua:48-53` | `Stat.isNative('BOREDOM'/'UNHAPPINESS'/'STRESS', v)` |
| 写回允差 `0.0001`（0–100 档）/ `0.000001`（0–1 档） | `ActivityRelief.lua:76-79` | `Stat.TOLERANCE_CENT` / `Stat.TOLERANCE_UNIT` |
| `number()` 0–1 校验（桥接与 Lua 两路各一遍） | `client/.../SelfCare/NeedsObserver.lua:5,20-23,37-40` | `Stat.isUnit(v)` |
| 健康 `0–100` 校验 | `client/.../SelfCare/HealthAssessment.lua:11` | `Stat.isNative('HEALTH', v)` |
| `val>1 → /100` 启发式，无共享函数 | `shared/.../Warehouse/SupplyEstimate.lua:77-83` | `Stat.normalizeHungerChange(v)`，行为不变；`getHungerChange()` 返回量纲本身 UNVERIFIED（需原生 API 核对） |
| 人事页同一表达式混用量纲（UNHAPPINESS 0–100 与 STRESS 0–1） | `client/.../UI/PersonnelPresentation.lua:34` | `Constants.Health.MENTAL_UNHAPPINESS_WARN=80` / `MENTAL_STRESS_WARN=0.8`，表达式本身正确，只把隐式知识写进名字 |

### B. 需求阈值

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| 工作中放宽 DRINK 0.45 / EAT 0.50 / SLEEP 0.85 / REST 0.15 写在 `choose` 函数体，不在 `rules` 表 | `shared/.../SelfCare/NeedsPolicy.lua:23-27` | 折进 `rules` 表每项的 `workEnter`；改基础阈值不再漏改工作阈值 |
| 滞后加成 `+0.15` 无名 | `NeedsPolicy.lua:36` | 本文件顶 `HYSTERESIS=0.15`（单模块所有，不进中央表；见 §3） |
| SLEEP 附加门禁 hunger/thirst `<0.5`，与 EAT/DRINK enter 无显式关系 | `client/.../SelfCare/SelfCare.lua:280` | `Constants.Needs.SLEEP_MAX_HUNGER=0.5` / `SLEEP_MAX_THIRST=0.5` |
| 田间耐力线 `ENDURANCE<0.4` | `client/.../Field/FieldProviders.lua:122` | `Constants.Needs.FIELD_MIN_ENDURANCE=0.4` |
| NeedsPolicy enter/leave 与 LeisureConfig gates 数值巧合相等（0.25/0.20/0.70/0.25） | `NeedsPolicy.lua:3-6`、`LeisureConfig.lua:5,7` | **不合并**：含义不同（自理进入 / 休闲门禁 / 健身退出），今天相等是巧合不是契约；两处各留各的表，只在两文件头注释写明 |

### C. 健康线 → `Constants.Health`

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| 能工作健康线 `>=95` 三处裸字面量 | `Hauling/Haul.lua:361`、`Runtime/Actions.lua:354`、`LeisurePolicy.lua:9`（FITNESS） | `Health.WORK_MIN=95`（三处同一意思：高强度活动健康门） |
| 散步健康线 `>=85` | `LeisurePolicy.lua:14` | `Health.STROLL_MIN=85` |
| 休闲门禁 health `75` | `LeisureConfig.lua:5` | 不动，已在 Config 表里命名，意思不同（休闲准入 ≠ 高强度门） |
| 健康缓存 `1000ms` | `HealthAssessment.lua:39` | `Health.CACHE_MS=1000` |

### D. 威胁规则（Lua/Java 双实现）→ `Constants.Threat` + Java 命名常量

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| 威胁扫描上限 Lua 裸 `64` / Java 已命名 `SPOTTED_LIMIT=64` | `NeedsObserver.lua:47`、`J/ObserverReads.java:13` | Lua 用 `Threat.SPOTTED_LIMIT`；Java 侧不动（已有） |
| 威胁判定半径 `<=100`（即 10 格）双实现 | `NeedsObserver.lua:51`、`ObserverReads.java:47` | 两侧各存 `RADIUS=10`，比较写 `dx*dx+dy*dy <= RADIUS*RADIUS`；不存 `RADIUS_SQ`，避免两份平方值漂移 |
| 威胁 Z 差 `<1` / `>=1` 双实现 | `NeedsObserver.lua:51`、`ObserverReads.java:46` | 两侧各存 `Z_MAX=1` |
| 跨语言说明：Lua/Java 无法读同一张表，双实现保留；两侧命名一致 + 互相注释指向，改一处时另一处可 grep 到 | — | 见 `Constants.lua` 头注释与 `ObserverReads.java` 注释 |

### E. 节拍 → `TickConfig` 扩充

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| PublicWork 多处手写 `now+50`（唤醒轮询/快进重判/待处理预留） | `PublicWork.lua:736,827-828,849,855` | `TickConfig.wakeMs=50` |
| 发现后唤醒底 `now+100` | `PublicWork.lua:798` | `TickConfig.discoveryWakeMs=100` |
| 对账/库存 `now+1000` 各一处 | `PublicWork.lua:806,807` | `TickConfig.reconcileMs=1000` / `stockMs=1000`（两个节拍，数值相等是巧合，分开命名） |
| 退避阶梯 `2000/5000/15000` | `PublicWork.lua:828-830` | `TickConfig.backoffMs={2000,5000,15000}`，`backoffMs[min(backoff,3)]` 与原 `==1/==2/else` 语义相同 |
| 预留过期 `>15000`（与退避上限同值不同义） | `PublicWork.lua:555` | `TickConfig.reservationExpiryMs=15000`，分开命名 |
| `workerRemoteMs or 2000` / `workerRemoteRadius or 48` 回退值与 TickConfig 表重复 | `PublicWork.lua:836,832` | 删回退，直接读表（表里恒有值） |
| 订单重查 `now+2000` 两处、规则轮询 `now+1000` 一处 | `PublicWork.lua:370,373,464` | 不动（见 §2：与 workerRemoteMs 同值不同义，PublicWork 本地节拍） |
| 社交轮 `math.floor(now/1500)` 与休闲停止节流 `now+1500` | `LeisureService.lua:161`、`PublicWork.lua:729` | `TickConfig.socialRoundMs=1500` |
| TaskRuntime 业务节拍 `pace=18`、空闲轮询 `now+50` | `Runtime/TaskRuntime.lua:342,355` | `TickConfig.businessPaceMs=18` / `businessIdleMs=50` |

### F. 供应 → `Constants.Supply`

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| 状态阈值 `minDays<2.0 → CRITICAL` / `<5.0 → WARNING` | `SupplyEstimate.lua:141-144` | `Supply.STATUS_CRITICAL_DAYS=2.0` / `STATUS_WARNING_DAYS=5.0` |
| `resolveHunger` 兜底 `meals 0.35 / stable 0.25 / 默认 0.15` | `SupplyEstimate.lua:84-86` | `Supply.HUNGER_MEALS/HUNGER_STABLE/HUNGER_DEFAULT` |
| 0.6/2.0 需求常量 | `SupplyEstimate.lua:3-6` | **不动**（P0 已统一，见 §0） |

### G. 优先级 → `Constants.Priority`

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| 优先级 0–4 校验三处 | `PublicWork.lua:187,193,210` | `Priority.MIN=0` / `MAX=4` |
| 优先级 0–4 校验（存档格式） | `Work/OrderStore.lua:34`（`integer(v,0,4)`） | `Priority.MIN/MAX` |
| `p>=1 and p<=4`（WorkSelector 选择时排除 0） | `shared/.../Work/WorkSelector.lua:10` | **不动**：不是同一谓词——0 表示禁用档，选择时排除是另一条规则 |
| UI 优先级菜单 `for value=0,4` | `UI/PersonnelPage.lua:662` | 不动：菜单枚举档位，与校验范围同源但由校验兜底；改范围时菜单由 `Priority` 派生是后续事，不在本轮 |

### H. 社交缓解 → 已有命名常量

| 散落点 | 文件:行 | 改法 |
|---|---|---|
| SocialActions 手写 `BOREDOM-6 / UNHAPPINESS-3 / STRESS-0.02`，与 ActivityReliefRecord 的命名常量数值相同但不引用 | `Activity/SocialActions.lua:38-40` vs `ActivityReliefRecord.lua:2` | SocialActions 改读 `Record.BOREDOM/UNHAPPINESS/STRESS` |

## 2. 不动的（清单上标明除外，grep 仍有裸数字是预期的）

- **纯 UI 布局数字**：`Layout.lua`、`WarehouseGrid.lua`、`DefensePage.lua` 等的
  像素/边距/字体/分栏数；`SquadHUD.lua:243` 的 `health/100` 展示换算。
- **测试里的期望值**：`tests/lua/*` 的断言字面量（如 `activity-relief-test`
  的 `40-6*r.hours`）是被测行为的期望，不是生产魔法数。
- **各域私有的重试/退避节拍**：含义不同、只出现一次，改一处不牵另一处——
  SelfCare `retryAt 1000/5000` 与 `discoverAt 1500`（`SelfCare.lua:271,356,364,
  375,414,459,530`）、Field `500/5000`（`FieldDiscovery.lua:270,467`、
  `FieldWork.lua:67,99`）、Cooking 泵 `50ms`（`CookingService.lua:207`）、
  Logistics `500/5000`、Membership `5000`、LeisureConfig 已有命名表内的全部
  数值（`seatRetryMs`、`cooldownHours` 等）。
- **通用 64 观察上限**：同值不同义，各是独立的“列表别太长”截断——
  `HealthAssessment.lua:8`（身体部位）、`CraftStations.lua:67`、
  `LeisureService.lua:275`、`ReposeSites.lua:183`、`SettlementFacilities.lua:178`、
  `DeliveryTarget.lua:60`、名字长度 `>64`（`ActivityService.lua:72`、
  `SettlementLedger.lua:70` 等）、`OrderStore.lua:39` 的 `n>64`、
  `CraftRecord.lua:32` 的链长上限。只收其中威胁扫描那一处（§1.D）。
- **派工切片预算**：`PublicWork.lua:802-819` 的窗口 16 / 决策上限 4 /
  工人上限 256——PublicWork 本地调度预算，不跨域。
- **哈希/随机/浮点容差**：`decidePhaseMs` 的 `31/100003`（`PublicWork.lua:64-66`）、
  `ZombRand(10000)/10000` 随机 roll、各域私有的 `0.000001` 级浮点比较
  （Cooking/Warehouse 等，见 `grep 0.0001` 结果——只有 ActivityRelief
  的两档与量纲有关）。
- **百分比换算**：`CookingMenu.lua:40,227` 的 `use/100` 是菜谱贡献百分比，
  不是 stat 量纲；`RuntimeMetrics.lua` 的 `/1000`、`/1000000` 是时钟单位换算。
- **Provider 注册表**：上一项未合 main（`p1-provider-registry`），本轮不碰。
- **调度逻辑**：只改常量与调用方，不改节拍语义、守卫顺序、失败处理。
  全部改动均为等值替换。

## 3. 集中位置的取舍（为什么不是全部进中央表）

- **中央表只收跨域共享或量纲假设**（`Constants.lua` + 已有的 `TickConfig.lua`）。
  跨语言（Lua/Java）无法同表，只做到两侧同名 + 互指注释。
- **单模块所有的数留在所属模块表**：NeedsPolicy 的 enter/leave/workEnter/
  滞后量只在 NeedsPolicy 里读，折进 `rules` 表即是集中，不进中央表；
  LeisureConfig 同理（其头注释已写明“协议/预算常量留给调用方”）。
  这样改一个域只翻一处，符合 M2（新人只读所属模块 + 中央表两处）。
- **同值不同义绝不合并**：Leisure gates 与 NeedsPolicy 阈值、退避上限 15000
  与预留过期 15000、对账 1000 与库存 1000、订单重查 2000 与远程工人
  2000，各自命名；合并它们会在将来某次只改一处时静默改错另一处。
- **SupplyEstimate 的 0.6/2.0 不动**（P0 已统一），只收同文件的状态阈值与
  兜底饥饿值——这两个与 0.6/2.0 无关。

## 4. 验收（2026-11-11，基线 58b9abf）

- 新增 `tests/lua/constants-test.lua`：量纲表、归一化、威胁半径平方恒等、
  优先级范围、节拍表字段、退避阶梯语义、NeedsPolicy 工作阈值与
  LeisurePolicy 健康门的行为锚点。35 项通过。
- 相关测试（Lua 5.4.7 本地运行，见 `tests/lua/constants-test.lua` 头注释的
  运行方法）：20 项中通过 9 项（新增 constants-test + 基线通过的 8 项），
  失败 11 项，全部是基线已失败项（见 §5），失败签名与基线一致
  （仅 `leisure-dispatch-transition-test` 的报错行号因 PublicWork 顶部
  多一行 require 而 +1）。
- 全库 Lua 测试对照（`tests/lua/*-test.lua` 共 236 项，同一 runner、
  同一 30s 超时）：58b9abf 基线 112 通过 / 124 失败；本轮 113 通过 /
  124 失败，唯一差值是新增的 constants-test 通过，**零回归**。
- `public-work-kernel-hooks-test` 的 TickConfig stub 随表扩充而更新
  （调用适配）：其中 `reservationExpiryMs` 取生产值 15000 而非 1——
  预留必须活过测试里 100ms 的提升间隔；其余 stub 字段取 1 不变。
- `tools/check-architecture.py` 0 错误；`tools/check-i18n.py` 2211 键对齐。
- `ObserverReads.java` 单文件用 JDK 25（`--release 25`，classpath 为
  `~/workspace/game-root/*`）编译通过；未跑 `build-probe.ps1`
  全量构建。
- 全库 grep：§1 所列裸数字在生产代码中不再出现（§2 除外）；
  剩余的 PublicWork `now+2000`（订单重查）与 `now+1000`（规则轮询）
  是 §2 标明的除外项。
- 实机验证：**UNVERIFIED**（未进游戏；MORALE/PANIC 量纲与
  `getHungerChange()` 返回量纲未对 jar 逐项核对）。

## 5. 基线失败记录（改动前已存在，非本轮引入）

2026-11-11 在 58b9abf 的干净 worktree 上用 `/tmp/lua-5.4.7/src/lua`
直接跑相关测试（与本轮同一 runner、同一 LUA_PATH）：
20 项中通过 8 项（job-state、warehouse-supply-estimate、p35-policy、
self-care-observation、p35-fitness、p35-social、task-runtime、
public-work-kernel-hooks），失败 11 项，失败点均与常量无关：
`activity-relief-test.lua`（经 activity-lifecycle-test.lua:4）、
`self-care-loop-test.lua:103`（JOB_CHANGED）、`public-work-test.lua:106`
（loaded haul 恢复）、`field-work-test.lua:2`、`health-gate-b-test.lua`
（同 public-work 106）、`personnel-enrich-test.lua`
（OrderQuery.priorities nil 索引）、`self-care-service-test.lua:2`、
`haul-test.lua:84`（Lua 5.4 无全局 `unpack`，runner 环境问题）、
`craft-stations-index-test.lua:5`、`leisure-dispatch-transition-test.lua`
（PublicWork 加载时 cooking stub 无 category，注册失败）、
`labor-wiring-order-test.lua:122`（wiring 漂移）。本轮改动后复跑，
11 项失败签名未变。

注意：本轮工作期间 main 已由父代理推进到 `673da20`（合入了
p1-provider-registry）；本分支仍以任务指定的 58b9abf 为基线，未合它。
在新 main 上 `leisure-dispatch-transition-test` 与
`labor-wiring-order-test` 通过（provider-registry 合并带来的变化），
不在本轮基线内比较。
