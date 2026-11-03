# Health Gate B：新世界仓储与公共搬运验收

基线：`0ed773d`，`phase-3a-consolidation`。仅 Gate B；冻结裁决见本轮用户指定的 health-gateB-design-judgment.md。**当前 Linux 环境不能运行游戏内验收，下述全部实机行为未验证，Gate B 未通过。** 宿主结果另列，不代替本表。

本流程复用 [仓储契约步骤 1–3、6](single-player-warehouse-contracts.md) 与 [过滤/携货保存步骤 6–8](single-player-storage-filters.md)，只使用新存档，不沿用旧脚本中的迁移承诺。只允许既有 Debug 入口生成测试 NPC/物品，不用手改持久表冒充物理搬运。

## 一个存档连续走查

准备一个已驻扎且可搬运的 NPC、同据点内间隔 8–12 格的可达源箱 S 和目标箱 D。记录世界名、模组基线、NPC 稳定 ID、容器登记 ID、订单 ID、每件原件 ItemID/fullType/状态与截图日志。暂停自主分拣直到基线盘点完成。

| 步骤 | 操作与观察 | 验收依据（当前全部未验证） |
|---|---|---|
| 1 | 登记 S/D；S 设 INPUT、D 设 STORAGE；分别配置过滤，D 允许本次五件。应用/取消一次配置，重开确认 | 登记唯一；角色/过滤与实际箱对应；私人、停用拒绝读写；EXCLUDED 是物流角色，不把它误当删除仓储实物。未请求盘点是 NOT_REQUESTED，不能显示为已确认零；请求后等 READY |
| 2 | S 放五件不同 fullType 的已知原件（例如 Pencil、Pen、Eraser、Hammer、Nails；以当前游戏可生成类型为准），D 空。记各 ID；刷新，逐项查看来源 | S=5、D=0、仓储=5；每类型各一，不扫描未登记箱和 NPC 背包；过滤拒绝不等于删除实物。另暂设私人/禁用并恢复，记录可见量与未知/失效计数 |
| 3 | 先记录下方公共订单端点差额；S→D 使用既有普通搬运。用同五件另测购物车纯配送时，把 S 设 STORAGE，收货目标是玩家，收货后手动归入 D；这两段不能冒充一个箱到箱公共订单 | 不使用制作单完成此步骤。监控显示唯一工作、原件及执行者。仓储快捷制作对话框另验证同一意图刷新、双击、关闭重开与重进后再次提交只产生一单；改内容才产生新意图，成功结果留屏 |
| 4 | 放行 NPC，分别在取前、拿取后、交付后暂停记录下表 | NPC 实际走到箱子，原生动作搬原件，不能仅看动画或 QUEUED；每件始终恰好一处 |
| 5 | 至少一件已拿、仍有未拿时正常保存，完整退出到桌面，重新启动载入同一世界 | 登记/角色/过滤/订单/manifest 责任恢复；逐 ID 盘点再放行，已拿原件不再从源领取；恢复或留责暂停须有可见原因；重复原意图不新建单 |
| 6 | 此批完成后手动将同五件放回 S；建立内容有变化的第二个意图，部分拿取后在公共配送单上取消，再完整退出重进 | 已拿留 NPC、manifest 继续负责；未拿留 S；监控显示携货数与归属 NPC。取消持久、不再派发；不新增自动返仓系统 |
| 7 | 对未取消的新一批，分别测试目标移动/拆除、卸载、目标满、NPC 容量不足、过滤改拒绝；每次保留现场，恢复条件后观察 | 记录实际 reason 常量及其可读文案；不向失效位置交付，不重复取货。拆箱时被原版移到地面的货另记录，不能假装仍在 S/D。仓储行标明不可解析端点，监控不静默等待 |
| 8 | 同一产品分别按“人工活需求先建立→补库存”和“补库存活需求先建立→人工”测试；只观察派发抑制，不执行制作 | 第一个建立的活需求获准，后来的重叠需求在监控有现有可读原因；不能仅靠哪个 tick 先执行。共享容器的第二据点不得重复认领同件原件。此项不验收 Gate C 生产 |
| 9 | 执行下方两个命名夹具及定向宿主回归，保留命令与结果 | Public.categories 替身、仓储选择 fullType 夹具仅按真实 harness 修复；宿主结果与以上游戏结果分开 |

### 原件核对表（每阶段重复填写）

仓储只计登记且当前可读取的容器；NPC 携货不计仓储，但计物理总量。正常 S/D 均可读取时：**S+D=仓储；S+NPC+D=5**。私人/卸载/拆除阶段仓储不是完整物理总量，须额外记未知/不可访问及地面等实际位置，不能用旧缓存填零。逐 ItemID 核对“一件一处”，汇总相等不足以证明不复制。

| 阶段 | S | NPC（ID/责任 Job） | D | 仓储 S+D | 物理总量 | 各原件位置证据 |
|---|---:|---:|---:|---:|---:|---|
| 取前 | 5 | 0 | 0 | 5 | 5 | 待实机 |
| 拿取 k 件 | 5-k | k | 0 | 5-k | 5 | 待实机 |
| 携货保存/重进 | 实测 | 实测 | 实测 | S+D | 5 | 待实机 |
| 已交付 j 件 | 5-k | k-j | j | 5-k+j | 5 | 待实机 |
| 完成 | 0 | 0 | 5 | 5 | 5 | 待实机 |
| 中途取消/重进 | 未拿留源 | 已拿留 NPC | 已交付留目标 | S+D | 5 | 待实机 |

## 当前执行链与范围差额

以下路径统一以 `Contents/mods/EmberRoutesProbe/42/media/lua/` 为根；行号为本轮工作树定位。

- 登记数据为 `ContainerRegistry` 的 format=1 locator `{id,x,y,z,containerIndex,containerType}`，对象自己的 ModData 保存过滤及角色；`client/EmberRoutesProbe/ContainerRegistry.lua:127` 每次 resolve 重验原容器。`shared/EmberRoutesProbe/InventoryPolicy.lua` 基线缺失 `return Policy`，实际 require 得到 boolean，本轮补回模块出口。
- `client/EmberRoutesProbe/WarehouseIndex.lua:85` 的原生快速分支曾把私人/移除等所有无法解析端点传成 UNLOADED，Java `WarehouseFastIndex.java:176` 又统一按 UNLOADED 汇总。本轮仅在有失效端点时重新盘点并复用现有 Lua rollup；`Index.containers()` 保留真实登记坐标和 status，原有容器检查窗显示打开时盘点快照中的真实原因（变更后重开检查窗），不能把不可读箱画成“0/0 kg”。未测量性能，不宣称改进性能。
- 意图是玩家 ModData 内**每据点一个当前 UI 草稿** `{scope,recipe,quantity,surface,preferences,requestId,result,product}`，由 `client/EmberRoutesProbe/PublicOrderDraft.lua:10–36` 管理；不是订单、资产账或新 receipt store。`UI/PublicOrderDialog.lua:419` 在有效内容变化时换 token；纯刷新重用，成功保持可见并禁用提交。关闭/模块重载从草稿恢复；A→B→A 属于新意图，不按产品组合去重。权威请求协议及 receipt 淘汰规则不改；已过期的未提交 token 仍返回现有 REQUEST_EXPIRED，不自行换 token 重试。对话框先挂载共用 Stepper 再读 entry，使用 PageLifecycle activation 拦截晚到回调并在关闭时释放。
- **接口差额未关闭**：`DeliveryService.lua:184` 的纯配送 intent 的 destination 是 `player:<requesterId>`，不是注册目标箱；其源只从 STORAGE 选取。`PublicOrderDialog` 创建的是配方需求，不是搬运单。S(INPUT)→D(STORAGE) 是普通 Haul 路线，监控中的 HAUL Job 不能冒充玩家显式创建的 Delivery Order。未新增订单类型/端点，也未改 DeliveryFlow/DeliveryTarget/HaulAgent 原生执行。故“一个箱到箱公共订单完成全部步骤”目前不能宣称支持，更不能记通过。玩家背包也不能计成注册仓储；玩家配送另记录玩家实收，不能套 S+D=仓储 的箱到箱等式。
- 创建/认领：`HaulAgent.lua:192–215` 建 manifest 并经 Store.claim；`HaulAgent.lua:242–264` 在原生效果前保存 activeAttempt；正常核对：`:46–63` 用逐件交付 receipt 结算，`:403–407` 在已知结清后 finish；异常：`:76–110` 走唯一 body stop/Store.pause，未知效果保留责任。正常恢复 `HaulJobs.lua:149` 重建 PAUSED/LOAD_RECOVERY，不等同磁盘验收。上述仅静态调用链证据。
- **取消是本轮明确契约修复**：基线 `DeliveryTarget.lua:31–32` 将 cancelled 设成 returning，旧 `delivery-service-test.lua:132–141,259–263` 断言实际返仓。本轮 `DeliveryService.lua:106–114` 在订单入口持久标 cancelled/CANCELLED 并调用既有 Work.pause(USER)，不清 Job/manifest、不动货物；advance 不再自动恢复取消单。监控禁用该单恢复，显示责任 NPC、cargoHeld/manifest；未知仍显示 RECONCILE_REQUIRED。无新返还系统；被禁的配送执行器未改。完整原生停稳/读档/其他入口干预下的行为未验证。
- **优先顺序是本轮最小派发修复**：现役 `StockService.tick()` 在 publicDispatch 下直接退出。`PublicWork.stock()` 原先见任意活单就跳过补货且无原因；先有 policy Order、后有 manual 时，原先两单可分别被不同工人领取，sequence 分数不能保证抑制。本轮沿既有 Order.sequence 比较最早的活根需求，在候选选择前抑制后来的异类需求；manual/manual 仍各自独立。只配置阈值但尚未形成补货 Order 不算活需求。DONE/CANCELLED 不参与；PAUSED、携货、未知等未结责任仍参与。理由复用代码已有 MANUAL_ORDER_ACTIVE/CYCLE_ACTIVE，CN/EN 成对翻译；规则被已有人工单抑制时以既有只读行契约显示在现有监控。未建立新优先级模型，也未执行 Gate C 生产验收。

## 格式错误（只记录，不迁移）

| 根/入口 | 代码实际行为 | 可见性、阻断与保留边界 |
|---|---|---|
| ContainerRegistry.data (`:52–75`) | 非空无版本或非 format=1 抛 WORK_FORMAT_UNSUPPORTED；容器/Job 格式另有明确拒绝 | 此门禁在登记根初始化前拒绝。本轮未改此契约；无迁移。tick 在 pcall 外读取 Registry.data 时也会抛错，不能承诺都转成 DISPATCH_BLOCKED |
| PublicWork.load (`:69–131`) | 顶层格式、request、priority、rule、order/progress 各有 PUBLIC_*_INVALID 异常 | 顶层不支持格式时原 publicWork 引用保留，宿主已测。**不能声称所有嵌套错误原数据逐字不变**：load 在后续嵌套检查前会补 rules/requests、清合法规则 nextCheck；正常恢复还可能先修改其他领域记录。本轮按冻结要求不改此行为 |
| DeliveryService.data/validate (`:13–45`) | 已有根格式错误抛 DELIVERY_FORMAT_UNSUPPORTED；订单/行错误抛 DELIVERY_ORDER_INVALID | 已有不支持根未被替换，宿主已测；合法缺省根仍正常初始化。无迁移，不补造货物 |
| Boot 初始化 (`shared/EmberRoutesProbe/Boot.lua:92–107`) | prepareTaskRecovery 的异常被捕获，ready/restorePending/runtimeReady 关闭，failureCode 通常为 RECOVERY_RECORDS_INVALID，并记日志 | OrderMonitorService 可投影该 failureCode。不能推断世界拒绝载入；也未证明游戏中具体错误框/文字如何出现 |
| 运行中公共 tick (`PublicWork.lua:674–699`) | advance 内异常可设置 faultWorld 并记 DISPATCH_BLOCKED；available() 拒绝继续公共提交 | 不保证 Registry.data 自己抛错也进入此捕获。Delivery 首次读取可能在此才校验，并非一概启动时校验 |
| UI 直接创建/订阅 | 对话框 pcall 捕获 create 异常并把 tostring(error) 留为 notice；CraftingService.tick 对订阅回调异常会删除订阅 | 监控读取自身异常不等于友好错误页，可能停止刷新；不宣称优雅降级 |

游戏内格式错误呈现、真实磁盘原数据保留、整个世界是否继续可玩均未验证。以上按代码与有限宿主观察记实，不在正常验收存档注入破坏性格式数据。

## 本轮验证记录

测试入口取自 `tests/java/KahluaLaborTest.java:90–105`、`tools/test-ui-kahlua.ps1` 及 [宿主调用记录](../reviews/2026-11-01/phase3a-format-admission.md)。本轮可运行的是仓库 Lua 5.4 host 模式（逐测试自带替身），不是安装版 Kahlua：

```sh
export LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;;'
lua5.4 -e 'unpack=table.unpack; dofile("tests/lua/<name>-test.lua")'
```

原生 UI fixture 保留仓库现有 host；其硬编码的 Windows ISTickBox 路径只在 `/tmp/gate-b-fixture-host` 中通过目录别名指向本机已有游戏 Lua，Contents/tests 软链接回工作树。没有伪造 TickBox、没有给生产代码删守卫；`health-gate-b-dialog-test` 使用旧夹具已有的 ERMonitorPreviewOnly 入口复用同一 host。安装版 `java --class-path '<game>/*' tests/java/KahluaLaborTest.java <tests>` **NOT-RUN**：Java/JDK/安装 stdlib 缺失；尝试仅下载 JDK 到 /tmp 也被网络 sandbox 拒绝，未安装系统包。

| 测试文件（均 tests/lua/） | 最终结果 | 范围/原因 |
|---|---|---|
| storage-filter-test.lua | PASS 32 | 原过滤/editor policy |
| settlement-storage-test.lua | FAIL | :117 `business discovery checks actor location`；隔离 0ed773d 加同一 return Policy 修复后仍同断言失败。未放宽生产守卫或修第三项夹具债 |
| warehouse-query-test.lua | PASS 26 | 查询/排序/缓存 |
| warehouse-locator-test.lua | PASS 13 | 登记/定位；高亮渲染未运行 |
| warehouse-ae2-test.lua | PASS 20 | 网格/滚动数据接缝 |
| public-work-test.lua | PASS 85 | 当前公共派发/资格/claim/recovery；隔离原始 0ed773d 也通过 |
| delivery-service-test.lua | NOT-RUN（依赖阻塞） | multi-worker-test 依赖仓库已缺失的 work-test.lua；没有到配送业务断言；旧取消返仓断言也与冻结新契约不同，未删除这些用例冒充通过 |
| haul-test.lua | PASS 54（依赖 actions 16） | 原有普通 haul host；不证明现役 HaulAgent 原生接缝已运行 |
| haul-routing-test.lua | NOT-RUN（依赖阻塞） | 同缺 work-test.lua；不记业务 FAIL |
| task-save-runtime-test.lua | PASS 71 | 保存/控制器接缝；磁盘模拟 |
| exit-save-test.lua | PASS 12 | 退出/保存边界 |
| persistence-test.lua | NOT-RUN（夹具能力阻塞） | 其 actions/haul 前置通过后 :39 进入 MembershipService 时未提供 ModData；不是实际磁盘失败，不修该额外夹具债 |
| health-gate-b-test.lua | PASS 22（另先复用 public-work 85） | 草稿/module reload、A-B-A、独立人工单、两向活需求抑制、取消/记录重载不恢复、顶层错误引用保留；物理效果替身 |
| health-gate-b-dialog-test.lua | PASS 10 | 真实对话框+共享 Stepper、刷新/重入/双击/重开/module reload、留屏与生命周期；native host mocked |
| health-gate-b-warehouse-test.lua | PASS 65 | 真实 Registry/Ledger/Index；登记/INPUT 角色、五原件的源→模拟 NPC→目标逐阶段核对；快照由 native 分支回退仍保留其他箱库存及 PRIVATE 原因。取放为替身，不是 native transfer |
| order-monitor-service-test.lua | PASS 30 | 取消保留携货数/NPC/无恢复操作，规则抑制理由；新增 API 替身是本轮调用适配，未修其他旧债 |
| order-monitor-view-test.lua | PASS 19 | 展示事实与责任标签 |
| settlement-tabs-test.lua（两个命名债所在） | FAIL（Lua host）；Kahlua NOT-RUN | categories 替身已补；fullType 选择改用实际 itemGrid row，并执行通过该检查。整套随后在 :258 旧 itemList API 处中断；单独激活人员页在 enrichWorkers 替身缺口处中断。**两个命名债不记完整夹具通过**，不扩修旧页签 |

开发中最初把原版游戏目录加入 Lua 搜索路径的探针会错误加载未替身的可选游戏动作，public-work 在研习断言中断；改用项目记录的 repo-only host 路径后 85 项通过。初次 plain-Lua 的 Windows 文件缺失、初次 Policy boolean、以及新定向用例搭建中的不完整替身/参数错误不作为玩法失败；Policy 出口的实际缺陷已单独修复。完整原输出留本会话 `/tmp/gate-b-host-tests.log`、`/tmp/gate-b-main-results.txt`，不能替代长期实机日志。

静态检查：全部 14 份修改/新增 Lua 的 `luac -p` PASS；`git diff --check` PASS；CN/EN JSON 可解析且 1801 键集合一致。官方 doclink 工具入口在此环境缺失，NOT-RUN；本轮用本地路径检查验证验收文档 3 个链接全部存在，INDEX/BACKLOG 指向本轮新文档的链接也存在；全文件扫描另发现原有被忽略的 history 快照链接缺失（INDEX 3 处，BACKLOG 2 处），未扩大范围修补。真实鼠标/渲染、中文 Kahlua 排版、原生走路/拿取/交付/停稳、保存屏障与磁盘退出重进、取消持货实际行为、容器移动/拆除/卸载恢复、目标/NPC 满载、共享容器跨据点、补库存实际执行顺序和规模性能均 **未验证**。无联机或 Gate C 验收。未提交、未推送。


## 箱到箱续接记录（当前脏树，2026-11-03）

本节覆盖上文历史宿主结果：本容器缺少 `lua5.4`、`luac` 与 Java/JDK，旧会话的 PASS **不是本次合并脏树的验证结果**。冻结决定来自用户指定的 `health-gateB-boxtobox-design-judgment.md`；没有重新设计需求或声称在线需求已同步。

实现范围：既有 Delivery 可选 `destinationId`，缺省保留玩家分支；显式 INPUT/STORAGE 来源，普通扫描仍 STORAGE-only。提交、batch、执行重验端点/过滤/容量；目标失效、过滤拒绝、满载、不可达均沿现有 owner 暂停，保留原件，不改投或自动返还。连续原生 TAKE 的每件前置也重验目标，防止后续队列项在过滤失效后继续拿货。移动源箱不再被错误当作目标箱变化。取消立即停止既有 owner、订单保持 CANCELLED；恢复与 discovery 不再派发该订单。

收据只通过 `projectDelivery` 投影到对应箱 ID（传统分支仍 `player:<requesterId>`），监控缓存逐行 source/destination/item/requested/delivered/remaining/reason，并保留 cargoHeld 与 carrier。已结算历史分段不重复加进 Order 基线，也不生成重复卡片。

重叠抑制继续放在 PublicWork：Delivery 使用现有 publicWork.sequence 的创建序号；比较 settlement + fullType + 可核验 destination。生产/最低库存需求没有指定箱时不推断目标；只有现有输出资产路由记录能证明目标。Delivery 的 batch/claim/TAKE 与连续 TAKE 都拒绝受抑制需求；反方向在既有 Production 输出转移/完成回调之前调用同一 PublicWork 守卫，防止目标直到执行时才选定而绕过抑制。此处只是既有交付边界守卫，没有新增生产能力、Gate C、订单类型、库存权威或调度器。取消/完成的先建需求不再抑制后建需求。多目标或缺失目标不进行盲合并。

购物车复用 ISComboBox，Service 返回登记端点副本；源选择仅 INPUT/STORAGE，目标选择仅可 put 的登记端点，传统默认值保留。已选端点失效后保留其意图并禁用提交，不静默改为玩家配送。未运行真实鼠标/窗口布局及中文 Kahlua 排版。

本次修改/新增（保留原有脏树）：

| 文件（client/EmberRoutesProbe 下，除非另注） | 用途 |
|---|---|
| DeliveryService.lua | 意图身份、端点提交检查、batch、认领重验、箱收据；保留取消 owner |
| DeliveryFlow.lua | 显式 INPUT TAKE、目标 HOLD、重叠 TAKE 门禁 |
| DeliveryTarget.lua | box endpoint、容量/过滤、命名目标失败、原生交付与 TAKE 守卫 |
| HaulAgent.lua | 共享执行器失败原因保留、连续 TAKE 门禁 |
| PublicWork.lua | 原 sequence 的双向先建抑制、可核验输出目标、Order 原因投影 |
| Production.lua | 仅既有输出取放/完成回调前的重叠守卫 |
| OrderMonitorService.lua | 箱收据端到端投影、逐行端点/数量/剩余、携货/载体、历史分段去重 |
| UI/OrderMonitorCards.lua | 缓存行摘要与原因显示 |
| UI/DeliveryCartDrawer.lua | 复用组合框的登记源/目标选择、失效保留与禁用 |
| UI/WarehousePage.lua | 转交所选源/目标至既有 Delivery 入口 |
| shared/Translate/{CN,EN}/IG_UI.json | 成对端点、需求摘要、HOLD 原因文案 |
| tests/lua/health-gate-b-boxtobox-test.lua（新增） | 定向真实 Service/Flow/Target/PublicWork 接缝；原生取放/移动为替身 |
| tests/lua/order-monitor-service-test.lua | 使用真实收据投影验证箱目标、携货、历史分段与取消 |
| tests/lua/delivery-cart-test.lua | 端点组合框及命令转交；组合框 clear 补齐原版契约 |
| docs/BACKLOG.md、本文件 | 原 Gate B 行更新及本次证据 |

续接前已有且继续保留的修改/新增：PublicOrderDraft.lua（玩家草稿）；UI/PublicOrderDialog.lua（草稿与生命周期）；UI/ContainerInspectorDialog.lua（登记角色/策略）；WarehouseIndex.lua（真实端点失败回退）；shared/EmberRoutesProbe/InventoryPolicy.lua（策略出口）；tests/lua/health-gate-b-{test,dialog-test,warehouse-test}.lua（前轮定向用例）；tests/lua/settlement-tabs-test.lua（前轮夹具调用适配）；docs/INDEX.md（文档导航）。本轮没有重新宣称其历史测试通过。

实际检查：

- `git diff --check`：PASS。
- CN/EN JSON 解析、键集合一致：PASS。
- 对全部 22 份修改/新增 Lua 逐份尝试 `luac -p`：全部 NOT-RUN（可执行文件不存在），不是语法 PASS。
- 使用上文 repo-only LUA_PATH 和 `unpack=table.unpack` 逐文件尝试下表命令：全部 NOT-RUN（`lua5.4` 不存在），没有 Lua 测试 PASS/FAIL 业务结果。
- `java --class-path '/home/hatch/workspace/repos/jars/*' tests/java/KahluaLaborTest.java health-gate-b-boxtobox-test.lua`：NOT-RUN（Java/JDK 不存在；既有 harness 另含 Windows stdlib.lua 路径要求）。没有安装系统包；尝试下载 Lua 到 /tmp 被网络代理连接拒绝。
- 官方 doclink 工具不在当前仓库；本节未添加新的 Markdown 链接，现有 Gate B 本地链接另做存在性检查。

| tests/lua/ 文件 | 本次结果 |
|---|---|
| delivery-service-test.lua | NOT-RUN：lua5.4 缺失；另有旧 work-test.lua 依赖缺失，旧取消返仓断言尚不符合冻结取消语义，不能记通过 |
| delivery-cart-test.lua | NOT-RUN：lua5.4 缺失 |
| haul-test.lua | NOT-RUN：lua5.4 缺失 |
| haul-routing-test.lua | NOT-RUN：lua5.4 缺失；另有旧 work-test.lua 依赖缺失 |
| hauling-provider-test.lua | NOT-RUN：lua5.4 缺失 |
| warehouse-query-test.lua | NOT-RUN：lua5.4 缺失 |
| warehouse-locator-test.lua | NOT-RUN：lua5.4 缺失 |
| warehouse-ae2-test.lua | NOT-RUN：lua5.4 缺失 |
| order-monitor-service-test.lua | NOT-RUN：lua5.4 缺失 |
| order-monitor-view-test.lua | NOT-RUN：lua5.4 缺失 |
| health-gate-b-test.lua | NOT-RUN：lua5.4 缺失 |
| health-gate-b-dialog-test.lua | NOT-RUN：lua5.4 缺失；另依赖原版 ISTickBox 的 Windows 路径 |
| health-gate-b-warehouse-test.lua | NOT-RUN：lua5.4 缺失 |
| health-gate-b-boxtobox-test.lua | NOT-RUN：lua5.4 缺失 |
| public-work-test.lua | NOT-RUN：lua5.4 缺失；包含已有双向公共需求抑制用例 |
| task-production-runtime-test.lua | NOT-RUN：lua5.4 缺失；定向覆盖既有输出执行路径，未跑生产全套 |

命令原始记录：本次容器 `/tmp/ember-box-verification.txt`（临时文件，非长期验收证据）。全部新增/修改 Lua 的解析、宿主业务断言仍待有运行时的环境复核。真实逐 ItemID 的 S→NPC→D、箱失效恢复、取消携货与原件责任、保存/重进、原生寻路与停稳、窗口/交互、性能均未验证。没有运行全套、没有实机验收、没有提交或推送。
