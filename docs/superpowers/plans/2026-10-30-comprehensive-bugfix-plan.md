# EmberRoutes 全面 Bug 修复计划（审查修订稿）

> 日期：2026-10-30｜状态：0.29.19代码接入；用户已授权推荐方向及三项玩法规则，本地验证中，实机未验。

目标：修复垂直工种与派工、身体、空间、保存和产物流转之间的断层。按真实效果验收，不用测试数量代替闭环。

依据：[NPC 唯一架构](../specs/2026-10-22-npc-behavior-architecture-design.md)、[统一任务协议](../specs/2026-10-23-unified-task-dispatch-design.md)、[原件与路线设计](../specs/2026-10-26-haul-routing-and-custody-design.md)、[开发规则](../../development-rules.md)。本轮已读取在线唯一需求 v4.0，连接器返回修改时间为2026-10-27；本计划不另立需求。

## 1. 审查结论与证据边界

- 当前工作区版本0.29.18、HEAD `aeed6b8`，大量用户改动未提交；原报告基线0.29.16，执行前必须复核涉及文件，不能按旧行号覆盖现有实现。
- 本轮仅静态核对当前业务Lua、安装版原生动作及ProjectRemnants农作桥接入口，未运行业务测试、未进游戏；参考全链路尚未验证。
- 安装目录：`D:/Software/GameApp/steam/steamapps/common/ProjectZomboid`；当前projectzomboid.jar SHA256为 `E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。本轮未新反编译JAR；原生语义结论限于已读安装版Lua。
- 原报告位置：`C:/Users/MuMu/.gemini/antigravity/brain/380f8ff6-1db6-4960-a2f8-7bb57726c4c3/full-feature-logic-and-ux-audit.md`。原计划相对链接指向不存在的位置，已撤下。
- 撤销“全部24处已覆盖”：原报告正文列9个配置项，汇总称8个，且漏计工具悬空状态和空间问题。以下逐项追踪，不用总数证明完整性。
- 撤销“零开销、微秒级、100%契合、零技术债、消除全部运行时崩溃”等未经测量或验证的承诺。

### 不应实施的原修法

| 原修法 | 风险与正确方向 |
|---|---|
| DTO补`area=areas[1]`，为空则造`(0,0,1,1)` | 丢失其余区域、挖空语义并伪造领地。据点areas保持唯一真相，修消费方；空区域明确拒绝。 |
| `getPolicy = get`防御别名 | 内部误调用应核对参数并统一为get，无明确兼容对象不增加旧接口。 |
| 每步直接`Driver.acquireControl(binding,category)` | 真实签名为(binding,jobId,generation)，代次由TaskController提供；业务不能自行发代次或抢占。 |
| 调`TaskController.moveControlled/queueAction` | 当前不存在这两个接口。现有接口为request/attachDriver/move/body，动作走body.add。 |
| DONE/死亡/异常统一release目录 | release要求effects=KNOWN且obligationsCleared=true。死亡不证明原件与效果已知，未结责任不能删。 |
| 相邻一格统一视为到达 | 可能隔墙、对角不可达或跨层。农作已选walkway，应走到该格再重验与作物可达；清洁必须把污渍目标格传给动作，不能传角色脚下格。 |
| NPC直接调用ContainerMenu.stashRoutine | 当前是玩家入口，经PlayerStashRoutine直接入队移动/转移并Say，不是NPC受控交付接口。须复用NPC身体、原件和交付协议。 |
| 用Geometry.cloneAreas直接拷贝工作区 | 当前只保留x/y/w/h，会丢工作区z；应区分据点二维区域与带楼层工作区。 |

## 2. 覆盖清单

“确认”均指静态链路，实机结果未验证。模块名指模组42/media/lua下EmberRoutesProbe；T编号对应后文任务。

| ID | 当前判断 | 处置 |
|---|---|---|
| F01 | Lumberjack/Forager Provider使用evaluate/startBatch等，PublicWork消费discover/claim/advance，确认断接；伐木Service已有标准方法 | T2，避免重写已有逻辑 |
| F02 | 两服务误用不存在的getPolicy | T2 |
| F03 | ForagerService调用不存在的TaskRuntime.moveTo，原计划实际漏写修复 | T2/T3 |
| F04 | LifeZoneSelector单矩形分支cloneArea不存在，多矩形分支克隆会丢z | T1 |
| F05 | 清洁/农作/伐木裸调walkAdj，动作直接入队；采集同样无统一授权 | T2/T3 |
| F06 | 三服务activeJobs未见保存接线；采集为不同批处理形态，不应统称四者同表 | T3分别建恢复契约 |
| F07 | 三服务终态删内存记录，未见release；Directory纯内存，“重进仍永久锁死”未证实 | T3区分同会话泄漏与重进恢复 |
| F08 | DTO仅areas而扫描方依赖area，确认消费断层；当前DeliveryTarget使用Geometry.inside，原同类指控撤销 | T1 |
| F09 | SettlementZones.copy当前已拷贝areas，原“必丢多矩形”结论过时 | T1只复核往返，有失败再修 |
| F10 | 地面原木未见接入容器搬运交付链 | T4；不称原木必腐烂 |
| F11 | 农作/采集未见受控产物入仓链 | T4；实际超载/腐败取决于物品与时间 |
| F12 | 清洁抓尸未复用原版入口卸装步骤 | T3；原版isValid并未显式检查双手，不能声称已证明必死锁 |
| F13 | CLAIMING_AXE无推进分支；农作缺水后DONE可能反复派工 | T2/T3前置校验与退避 |
| F14 | 清洁精确到格与walkAdj语义冲突 | T3 |
| F15 | 农作walkway再次walkAdj导致二次偏移 | T3 |
| F16 | kitchenZoneId消费缺口 | T5复核发现与执行两端 |
| F17 | spoilageStrategy排序缺口 | T5 |
| F18 | batchMeals消费缺口 | T5；不得覆盖已有自主目标或指定订单数量 |
| F19 | continuousBatch未约束续伐 | T5 |
| F20 | lumberZoneId从错误的entry.publicLifeZones读取 | T1/T5 |
| F21 | cleanRadius未接通范围，中心语义尚需明确 | T5/待决C3 |
| F22 | haulRottenFood未实现消费 | 待决C3，不默认增加腐食运输业务 |
| F23 | forageZoneId未消费 | T1/T5 |
| F24 | searchRange未完整支持 | T5区分作业范围与感知半径 |
| F25 | 人员矩阵列宽风险 | T6；实际裁切/输入待验 |
| F26 | Chips单行溢出风险 | T6；裁切不等于编码乱码 |
| F27 | 中文硬编码、单位与漏译 | T6逐键核查 |
| F28 | 仪表盘标题栏拥挤 | T6先查当前布局和长名 |
| F29 | 全员归仓/清空背包按钮是新交互，不是已证明Bug | 待决C3，不自动实施 |
| F30 | 本轮新增：CleaningService进入HAULING_CORPSE后仅检查到达，未见继续移动分支 | T3 |
| F31 | 本轮新增：ForagerActions自行造物/扣图标后再调用原版perform，原版complete本身addOrDropItems、perform会actionComplete；构造依赖ISSearchManager对应图标 | T2/T3核实唯一结算及NPC manager适配，禁止无动作直接造物降级 |
| F32 | 本轮新增：包装perform回调不能独立证明效果和取消恢复；动作停止可能留下执行phase | T3按尝试与真实效果推进 |

配置项的“消费缺口”是原报告待逐字段复核的结论，不能仅凭本表认定所有业务完全没读取。

## 3. 架构选择与授权

用户要求本会话开始修复，按本轮说明采用以下C1/C2的A′。随后明确选择本轮补齐三项玩法：腐食仅公共容器→接受腐食的废品容器；清洁半径以NPC为中心且限制合法据点；批量备餐关闭时每个原生成品后重新仲裁，指定订单数量不变。以下备选分析保留审查依据，不再重复询问已确认项。手动全员卸货按钮仍不在范围内。

### C1：业务恢复记录与身体会话粒度

| 方案 | 优点 | 成本与风险 |
|---|---|---|
| A′：现有TaskController工种适配器＋最小持久业务记录（建议） | 批内连续动作共用一个受控执行段；稳定jobId/npcId/尝试记录原件、效果和恢复点；不必每块污渍都建全局持久Job | 每工种仍须停止、保存、恢复契约，不能只存内存批次；不是零持久化 |
| B′：逐资源独立公共Job，批次聚合候选 | 每资源恢复和争用明确，适合长期任务或多人争抢 | 索引/清理/版本成本更多；不必全图预建，也不能断言必有严重GC |

A′不是原方案“每动作抢身体、动作完解绑”。两种方案都复用唯一控制器、业务与原件权威，不照搬Craft/Haul形成另一套内核。先调查LaborStore/Runtime扩展形态；新增记录结构/类型先明确版本与恢复边界。

### C2：产物由谁交付

| 方案 | 优点 | 成本与风险 |
|---|---|---|
| A′：产出者受控收集并交付本批已确认产物（建议） | 无需全域扫描，沿用既有交付/过滤/原件规则 | 占劳动时间；需地面原木拾取、负重分批及无仓等待，不能清空NPC全部背包 |
| B′：产出事件登记局部拾取候选，搬运工领取 | 分工清晰，生产者不用往返，不要求每秒全图扫描 | 需地表原件身份、唯一认领及有界失效观察，现有容器搬运尚不能直接承诺适用 |

原方案把事件式地表搬运遗漏了，不能把全域轮询当唯一替代。若首批只处理背包产物，必须明确地面原木仍未闭环。

### C3：未明确语义和新增功能

cleanRadius中心、batchMeals批量语义、searchRange范围优先级先对照在线需求与现有字段。无明确规则时给用户具体选项及利弊后再实现。未消费配置可选：补齐（玩法完整、开发范围更大）；保留数据并明确禁用/说明未支持（更快、功能延期），由用户决定，不能继续假装可用。

全员/个人卸货按钮另议：操作便利，但增加权限、原件筛选、多NPC仲裁及反馈成本。本次自动产物交付不依赖新增按钮。自动取工具/补水也不能在修悬空状态时默认扩项。

## 4. 四阶段执行任务

顺序调整：先建立安全接线，身体与责任协议未就绪前不得先恢复自动派工。空间/权限和工具前置不能推迟到NPC已外出之后。保留整体批量交付，不逐内部切片要求用户反复进游戏。

### 阶段一：空间模型与安全接线

**T1 空间单一数据源**。涉及SettlementGeometry、SettlementZones、UI/LifeZoneSelector及清洁/农作/伐木等SettlementLedger消费者。

- [ ] 核对据点二维areas与工作区带z的areas；修单矩形初始化和楼层克隆，不加假区域、不以兼容字段覆盖联合区域语义。
- [ ] 扫描联合矩形并去重、排除空洞；有界游标和共享预算，领地/区域版本改变后失效。批准的据点外作业区不能被据点第一矩形截掉。
- [ ] 指定区域重验据点归属、启用、楼层及适用用途；区域删除不偷偷扩大范围。若用途只属UI约定、模型未存用途，先评估再确认模型改动。
- [ ] 在现有geometry/selector/work-zone-selector夹具补两块分离区域、挖空、非零楼层、保存→查询→再编辑和空区域；F09已正确则记录而不重修。

**T2 Provider及原生能力核查**。涉及PublicWork/Providers、各Provider/Service/Actions和JobPolicyService；参考已有CookingProvider/HaulAgent及TaskRuntime接线。

- [ ] 从实际调用核对discover(env)、claim(selected,npcId,jobId,env)、advance(env)和候选DTO，区分可选方法；不强迫全部Provider实现空retained/retire。
- [ ] 伐木Provider委托现有服务，采集接标准链路；纠正getPolicy和moveTo职责错误，不靠别名/补假API维持旧路线。
- [ ] 领取前核查工具、水、目标、绑定、上下文及范围；不足明确拒绝并条件唤醒/有界退避，不保留无出口CLAIMING_AXE。
- [ ] 原生参考先追 `D:/Project/ProjectRemnants/42/media/lua/client/NPCFW_FarmingActions.lua` 全桥及当前根NPCFW.jar调用方，再查当前安装Lua/JAR，记录差异；参考只读，不复制独立控制器。采集追manager→发现→动作→物品/生态→退出/保存。
- [ ] 阶段二受控能力完整后才开放工种自动执行；阶段一不能单独交付仍裸写身体的“可派工”路径。

### 阶段二：受控执行、停止保存与死锁

**T3 统一执行与恢复责任**。涉及四工种Service/Actions、TaskController/Runtime、LaborStore/Claims、TaskDirectory、Persistence/ExitSave的现有接缝，公共内核只作必要改动。

- [ ] 按确认后的C1，经controller.request→ACTIVE→attachDriver→body执行；移动body.move、动作body.add，安全段结束重新仲裁，不每tick直接抢Driver。
- [ ] 按现有契约接adapter.requestStop(reason)、observeStop()、persistEffects(fact)；核查start/stop/perform/complete及同步重入。旧代次禁派发/清新队列，旧效果按原尝试幂等归账。
- [ ] 持久记录仅存版本、稳定ID、业务步骤、原件/目标身份、效果和义务，不存闭包/userdata/动作队列。统一保存屏障同步捕获；UNKNOWN不重放，恢复先核对原件后争取身体。死亡、卸载、跨世界分别处理。
- [ ] 关联offerKey/revision、jobId和npcId；效果KNOWN、义务清且身体停稳才release。正常完成、拒绝、暂停、取消、死亡分出口，不统一finally释放。
- [ ] 清洁区分污渍目标与角色站位，补齐运尸目的地移动；农作走既选walkway且重验同层/对作物可达；伐木同样核对同层/目标身份。不可达有界退避，不统一放宽距离。
- [ ] 参考安装版ISGrabCorpseAction.PerformGrabCorpse排入ISUnequipAction的成熟做法，经同body卸装；不以直接置空双手冒充生命周期。抓/落尸验证真实拖拽和堆放结果后推进。
- [ ] 采集只允许一个已核实结算者，manager适配未通过先阻断，不用无动作造物降级。动作完成通知不等于世界效果，失败不能虚报成功。

最低回归：双NPC同资源唯一领取；一人切随从/自理/活动不影响另一人；旧回调无身体权；持尸或部分产物保存恢复一次；缺工具不反复往返；运尸实际到目的地。宿主验证责任，实机验证移动/动画/物理效果/磁盘。

### 阶段三：原件产物交付

**T4 收集、分批和恢复**。涉及Farming/Forager/Lumberjack结果适配与Haul/WorkTransfer/HaulRouting/LaborClaims接缝；ContainerMenu/PlayerStashRoutine仅作玩家逻辑参考。

- [ ] 按确认后的C2登记本批实际原件ID、来源及必要实例状态；不卸其他Job原件、工具或自理物资。
- [ ] 收获成功或继续将超重前进入交付责任，不能先DONE；原木按真实地表原件拾取，处理抢先拾走、叠放和卸载，不按类型删后重造。
- [ ] 复用过滤/隐私/权限/容量声明及提交前物理验证。满仓、无仓、转移失败保留责任并有界等待/改路，不全域丢地或无限重试。
- [ ] 中断及保存保留已交付事实，仅续剩余原件；实际变化后通知仓储失效，显示刷新失败不重做转移。
- [ ] 复用现有搬运回归补部分交付中断、满仓改路、死亡/保存恢复及重复通知；集中实机确认三类产物流转。

### 阶段四：配置消费与UI

**T5 配置行为对应**。涉及CookingSupply/设施选择/自主备餐、各工种Service/PolicyDef及Zones。

- [ ] F16—F24逐项登记持久值、默认值、标签、实际读点与可观察结果；要么接通，要么经C3明确禁用/延期，不遗漏厨房区、批量备餐、腐食处理。
- [ ] 发现与执行双端重验区域和权限；continuousBatch控制续作，searchRange不替代感知半径，cleanRadius不突破全局预算。
- [ ] 保质期按原版物品属性排序并保留安全/品类过滤；batchMeals尊重既有自主目标和订单数量，改值不重写已发生效果。
- [ ] 在已有policy用例核查保存→读取→选择→动作参数，不只测字段存在。

**T6 布局双语**。涉及UI/PersonnelPage、UI/JobPolicyEditors、SettlementDashboard、PolicyDef和CN/EN字典。

- [ ] 优先复用相对布局/文字测量/裁切滚动解决矩阵和Chips，保留完整名称说明及可靠命中区域，不默认新建图标系统。
- [ ] 长据点名、活动与关闭按钮不覆盖；绘制与输入使用同一布局结果。
- [ ] 去中文拼接与硬编码单位，补漏译；窄窗、CN/EN、长名及字体缩放做相关Kahlua预览，真实鼠标和游戏渲染单列未验。

## 5. 精简验证和交付

1. 审查轮仅修改Markdown；实施轮已获用户授权，递增0.29.19，运行必要定向回归、静态门禁与构建，不上传工坊。
2. 实施复用现有tests/lua与KahluaLaborTest.java；仅新接缝无适合夹具时新增测试。原计划unit-provider-contract-test.lua、vertical-body-control-test.lua与tests/run-all.ps1不可当作现有可执行门禁；也不固定旧断言数量。
3. 覆盖认领→执行→效果核对→中断→保存恢复→责任结清，共享协议测一次，各工种只补差异，不每阶段重跑全历史套件。
4. 改Lua按开发规则跑 `node ../.workbuddy/tools/pz.mjs preflight .`；改Java才构建与相关测试。build-probe是构建打包，不是完整静态门禁；luac不能证明API/玩法。检查未结束写未完成。
5. 静态、宿主替身、原生游戏、真实磁盘和性能证据分开，最后集中一轮完整玩法验收；不承诺联机、强退原子性或固定规模。
6. 实施交付按规则递增版本并保留版本日志，发布前release-check；本轮不上传工坊。进度只原位更新BACKLOG，不向HANDOFF/README堆流水。

## 6. 开工与完成条件

- C1/C2及三项C3规则已获本轮授权；实现契约和事实见下方证据。未知原生能力先最小闭环，不把宿主结果当游戏验收。
- 最终逐条回填F01—F32的处置与验证层，过时结论不重复修、新功能延期不冒充Bug已完成。
- 0.29.19实现、原始输出及边界见[实施证据](../../reviews/2026-10-30/comprehensive-bugfix.md)。真实玩法/磁盘恢复/性能仍未验证，完整页签夹具仍有失败，不记全面验收完成。任务复选框保留验收清单含义，不因代码存在全量勾选。

## 7. Bug阶段首批续修（用户解释后批准继续）

不改变唯一身体控制、Job/Claims权威或新增玩法。按原服务契约修复，版本递增0.29.20；保留其他未提交改动，不自动提交或发布。

- [x] JobPolicyService：拒绝未知格式并保留原数据；写入经Ledger.view；通知使用真实LaborSignals.changed。规程UI显示阻断原因，不生成可覆盖未知数据的默认草稿。原服务测试改用真实信号，覆盖授权、格式保留和保存往返。
- [x] 仓储：保存/恢复网格自身滚动，查询变化重置、扫描更新保留；旧分页断言改为连续网格、稳定物品身份和有效滚动范围，保留重新扫描未知库存断言。完整旧页签测试后续卡在Selector替身缺derive，不以改生产代码迁就夹具。
- [x] 活动：范围覆盖、行为覆盖及人数容量使用整个多矩形联合区，同层重叠不重复计数，沿用现有Zones单一空间语义；补多块区域生命周期回归。
- [x] 派工：通过现有发现环境提供退避资格查询，在工种候选限额前过滤，保留最终复验；补前三项冷却、第四项可选用例。
- [x] 烹饪：扫描依赖与已完成快照TTL分开，时钟回退仍失效；完成时间标识观察结果、保留每轮预算和库存/声明栅栏。补大库存完成、后续缓存过期和变化失效回归；不宣称瞬时原子库存快照。
- [x] 采集停止边界：沿安装版ISForageAction核对complete入包与perform生态结算的两步；FieldActions停止结算复验现有afterPerform证明，无法确认记UNKNOWN并保留责任，不自动补执行或重放。动作边界及重复停止定向通过，真实游戏回调间时序未验。
- [x] 归属交接：待跨区改派/解除归属或RETURN时只经既有RECOVERY交付旧货，禁止续批，不放宽FOLLOW或新劳动。真实宏观政策/Runtime/Jobs/Claims交接回归通过，无新增存档字段。
- [x] 运行相关最小Kahlua回归、Lua完整preflight、版本构建/包核对与文档链接检查。分别记录替身、静态与实机边界；本批后继续其他功能链路审查。

## 8. 未结责任监控续修（用户授权由本会话选择可扩展方案）

选择组合适配：现行Job监控按providerType注册投影与可选命令，不建立新业务账本；提取既有Cooking投影作为第一个命令适配器，FIELD_WORK只读适配器补齐可见性。制作/搬运仍读取原BusinessJobs，不为统一外形强迁其权威记录。UI只消费阶段与原件状态DTO，不识别工种业务或清除UNKNOWN。

- [ ] 新增TaskMonitorProviders注册入口、CookingMonitor及FieldWorkMonitor；OrderMonitorService集中授权/版本复验后路由，未知命令与只读任务不能落入搬运命令。
- [ ] 通用卡片使用可选阶段描述，四工种显示劳动/收集/交付而非伪装制作流水线；真实原件状态决定仓内/持有/待收集，不把OUTPUT角色当作入库证明。
- [ ] CookingService命令入口重新检查操作者、据点和任务归属；未知效果拒绝手动resume，不依赖UI按钮保护。
- [ ] 复用监控与烹饪测试验证投影隔离、订阅、命令路由、陈旧版本、跨据点/无授权拒绝及UNKNOWN；只为上述断层增加必要回归，版本0.29.21，最后一次完整门禁、构建与包核对。本批不新增持久暂停协议或人工核销玩法。

## 9. 并行架构优化接缝收口（2026-10-31，用户指定由本会话实施）

保留当前优化，禁止回填旧包覆盖工作区。用户已在根因及方案说明后授权收口：目录由既有调度上下文注入，避免延迟require仍保留反向业务依赖；执行门禁要求操作者，纯环境判断继续使用isSinglePlayer，避免授权调用方逐个增加特例。

- [x] HaulingProvider移除PublicWork依赖；发现使用env.directory，成功认领时保存该目录句柄，结清向原目录释放且仅在释放成功后移除运行记录。删除已无调用者的PublicWork.directory旁路入口；不新增调度器或存档。
- [x] RuntimeGate.canExecute(nil)返回false；保留仅判断环境的独立接口。用现有门禁测试验证空/死亡操作者和客户端/服务端拒绝，并覆盖真实SettlementLedger.authorized(nil)接缝。
- [x] 复用现有搬运工种测试覆盖加载隔离、认领、未结保留、结清释放及释放失败重试。烹饪夹具新增库存后发出已有库存失效通知，验证SAVE之后下一批发现；不缩短生产冷却。
- [x] 定向Kahlua回归及显式模组根preflight通过，记录当前工作区证据（LuaLS 0 Error/794 Warning，未清零）；本轮不覆盖其他AI版本号/JAR，不将旧0.29.21包当成当前源码构建产物，不宣称实机验收完成。
