# 分布式工作 UI 实施段

日期：2026-11-04。实施基线：`phase-3a-consolidation @ 4eab3a39d3ebe6e79ab31a53d67aa95cde117707`，开始时工作树干净。依据用户指定的 `ui-distributed-work-implementation-brief.md` 和已定七项决定实施；未提交、未推送。没有重新同步在线需求，不把历史草案当本轮批准范围。

## 冻结的数据契约

读取链：`CraftingService.status` 的工人和制作事实 → `PersonnelService.enrichWorkers` 的人员事实；`OrderMonitorService.status` 的独立执行/订单投影；`DemandMonitorService.status` 的问题及清洁处理者。`WorkOverviewService` 只组合这些只读出口，`WorkOverviewPresenter` 是纯函数，输出可丢弃的快照，不调度、不持久化、不解析 activityText、不读写原件。

| 对象 | 身份与来源 | 用途 |
|---|---|---|
| 需求问题 | `DemandMonitorService.rows[].id`，独立 problemId 命名空间 | 按问题 ID 去重，不按 affected 人数计工作 |
| 公共订单 | `ORDER:orderId`，PublicWork 的订单投影 | 已认领与未认领沿同一订单键；后者在制作页独立区域 |
| 普通制作/搬运/配送 | `CRAFT:jobId`、`HAUL:jobId`、`DELIVERY:orderId` | 沿现有业务监视行的稳定域前缀 ID |
| 外勤 | `FIELD_WORK:jobId`，`FieldWorkMonitor.project` | Job 的类别、目标坐标、状态、资产收集/交付事实；不按每棵树展开 |
| 烹饪 | `COOKING:jobId` 或关联公共订单的 `ORDER:orderId` | 保留源头身份，类别来自监视器 providerType |
| 执行者 | `npcId` | 人员定位、命令目标；不代替工作 ID |
| 工具责任汇总 | `TOOL_CUSTODY:npcId` | 这是按人的责任汇总，不是稳定工作 ID。保留人员可读事实，不加入工作队列/计数 |

实现入口：客户端根目录 `EmberRoutesProbe/WorkOverviewPresenter.lua:4` 状态映射、`:13` 聚合、`:58` 可见性；`WorkOverviewService.lua:4` 数据边界。以下源码路径均相对于 `Contents/mods/EmberRoutesProbe/42/media/lua/client/`。

计数口径：按服务已带领域前缀的工作键去重；待分配仅计无执行者的有效等待工作；受阻仅计有执行者且存在真实 attention/unknown/BLOCKED/RECONCILE_REQUIRED 或外勤明确失败原因的工作；暂停依据真实 PAUSED/paused。结束、取消、纯问题、优先级设置、闲暇和工具责任汇总均不计。暂停优先于等待和受阻；没有真实受阻证据的已分配等待仍显示等待，不靠时长推断。未结清的取消责任仍可在人员显示，不重新计为有效工作，也不清责任。

## 实施结果与文件

按冻结契约、删页、上下文制作、人员、命令、提醒、作业方针的顺序接入：

- 删除 `UI/DemandPage.lua`、`UI/OrderMonitorPage.lua` 页面层；所有后端与监视卡片组件保留。`UI/PageRegistry.lua` 不再注册 demands/orders，工作组默认 crafting，首次 Dashboard 默认 warehouse。policies 的父级为 settlement，logistics 为 personnel，crafting 为 work。组父级与叶页面父级在注册器/导航中明确区分，方向键不会尝试打开虚拟组页。
- `SettlementMenu.lua` 的旧 orders 入口转制作。运行源码没有遗留指向 demands/orders 页的 selectTab/open 调用。
- `UI/WarehouseDetails.lua` 增加独立“发起制作”按钮，原公共配方订单入口保留。未选物品禁用。
- `CraftingCatalog.lua`、`CraftingService.lua` 增加精确 productType 目录过滤，检查真实产出集合（含非主产物），保留原有增量目录预算。输出嵌套类型集合也做副本。
- `UI/CraftingPage.lua`、`UI/CraftingBrowser.lua` 在激活前安装过滤上下文，不选择首个配方、不生成草稿；无结果明示。返回只携带 returnTab=warehouse + filterProduct，返回、提交成功、手动离页、关闭时清除。没有历史栈、itemId 或选中原物品保证。分页文本和测量移到脏数据投影。
- `UI/CraftingOrders.lua` 使用实际独立未认领区域，按订单显示；选中后复用原有详情卡，以原监视行 ID/generation 取消。已认领部分仍按工人显示，公共配方发起入口保留。
- `UI/PersonnelPage.lua` 保持 65/35，复用 FilterChips 和 CachedList，矩阵每行增加一行真实工作小字，右侧工作详情在健康/疲劳信息之前。矩阵与详情使用同一工作对象；等待/暂停不归空闲。筛选不改优先级和选中。列表滚动由现有 CachedList 承载，标题一行截断，详情保留完整标题。人物徽标改用 SemanticBadge，度量缓存于投影。
- 新增 `WorkCommandAdapter.lua`；人员命令与类别队列命令均经此适配器。没有第二套业务命令、状态机、调度、身体控制或资产结算。
- `SettlementDashboard.lua` 固定预留提醒一行，复用 FilterChips 展示健康、受阻、待分配；无异常显示平稳，读取不可用时显示数据不可用。预留食物/水顺序但没有伪造其事实。提醒类别各自计数和点击，不相加为一个总数；按既定顺序展示。窗口拥有 PageLifecycle 订阅，关闭注销；真实人员观察仅在打开窗口按五秒节拍刷新，同时消费服务失效通知。面板外提醒未实现。
- `UI/WorkPolicyPage.lua` 上半部复用新增 `UI/WorkQueue.lua`，按现有类别显示真实逻辑目标、执行者、状态、已有命令；下半部保留可滚动方针/划区表单及保存重置。搬运/制作使用对应业务入口，不编造未注册方针；配方订单仍归制作页。`ActivityPage.lua` 完全未改。
- CN/EN `Translate/*/IG_UI.json` 新增 22 对键，作业页标题成对修改。

## 命令与生命周期闭环

`WorkCommandAdapter.lua:8` 的入口只接受已有能力：

1. 制作、公共配方、搬运、配送、烹饪按行实际 `id`、`generation` 调 `OrderMonitorService.command`；保留权限、代次和 readOnly 守卫。按钮只在源行能力存在时显示。“取消并清理”表示现有业务取消/清理语义，不承诺凭空归还物品。
2. 外勤按 jobId 重读 Job，核对 providerType、scopeId、npcId、revision，复核据点访问，再 `TaskRuntime.current():stopJob(npcId,jobId,'USER')`。不走只读工单命令，也不存在 interrupt 调用。
3. 外勤虽有持久 SUSPENDED，但 `FieldWork.advance` 会自动重试，**不是用户暂停**；只显示“停止身体任务”，不提供虚假恢复/归还，不阻断后端安全收尾。

既有业务闭环没有改动：创建/认领见 `EmberRoutesProbe/FieldWork.lua:114`（`:135` Job 模型、`:140` createClaimedJob）；正常效果与收尾见 `FieldSession.lua:17`、`:83` 的持久收尾及 `FieldWork.lua:92` 的 finishField/removeSettled；异常停止见 `FieldSession.lua:52` stopAdapter 和 `:115` persistFailure，读档见 `FieldWork.lua:49`。身体停止仍经 `TaskRuntime.lua:140` → TaskController.requestStop，不清 Job、claims、obligations 或真实随身物品。

UI 创建归属为 Dashboard → Page → CachedList/InfoList/按钮/菜单；Dashboard 和类别队列的 watch 由 PageLifecycle 激活令牌管理，队列菜单由 activationScope 持有并门禁；制作目录/预览沿原有取消句柄和 activation token，离页注销。没有新增隐藏页面扫描或帧内实体读取。

## 根因待办与明确差额

| 项目 | 代码事实/根因 | 本段处理及影响 |
|---|---|---|
| 食物/饮水问题源 | `DemandMonitorService.lua:38` 开始的状态读取目前只有清洁、库存规则、医疗；没有类型化食物/饮水 problemId 事实及问题详情入口 | 不从库存、名称或受影响人数猜测；不显示虚假食物/水数字。需在业务只读出口建立问题类型与稳定 ID，并提供真实问题详情入口，再接提醒。这一提醒验收尚不完整 |
| 工具归还工作身份 | `ToolCustodyMonitor.lua:33` 用 TOOL_CUSTODY:npcId 汇总多份原件责任，无单个工作 ID/generation | 人员继续展示责任；不纳入作业数字、不伪造归还命令。后续需只读投影真实 TOOL_RETURN Job/责任与可执行业务入口 |
| 人员当前身体与多个保留工作 | 现有监视事实可列多个保留 Job；Presenter 优先 working，否则确定性取服务顺序中的首个保留工作 | 不是新调度裁决。工具责任不覆盖实际工作；准确的“当前身体任务与全部保留任务”多项详情仍需独立身体事实出口，不能解析 activityText 补全 |
| generation 的简报描述与实码差异 | 只有未认领公共订单、部分烹饪/配送行是 ORDER:revision；普通制作/搬运保留执行行沿用其实际 generation。原 `order-monitor-service-test.lua:81` 专门阻止旧未认领按钮控制同数值的新执行 | 原样传行值，未强制改成 ORDER:revision；不破坏旧按钮失效边界。统一代次格式须另行审计权威认领/变更与全部命令守卫，不能在 UI 自造 |
| 外勤手动发起 | 外勤来自既有 provider 发现/认领与方针/划区，PublicOrderDialog 只创建带配方公共订单 | 保留真实方针与业务入口，不声称能手动发起任意伐木/搬运目标；若需手动目标，必须先有业务意图接口 |
| 旧页面测试耦合 | settlement-tabs 同时充当 ISUI 替身和旧 orders/demands 集成套件 | 只补新服务替身契约和 productType 查询支持；不删除旧断言来消除失败。旧页面场景需按分布式业务重新拆分，当前整份套件仍失败，见下表 |
| 原方针编辑器生命周期/绘制边界 | `UI/JobPolicyEditors.lua:182` 的区域选择器 onSaved 没有页面激活令牌，`:205` 的 prerender 仍读 Zones.revision 并可能重建下拉 | 本轮新增队列 watch/菜单有令牌，但不能据此声称既有方针编辑器全部满足红线。根因待办：编辑器协议须显式接收页面激活作用域、对称拥有选择器，并把区域变化投影移到服务通知；不靠回调清状态或吞异常掩盖 |
| 延期 | itemId 定位、面板外通知 | 均未实现，未以 productType 冒充 itemId，也未宣传常驻通知 |

## 检查与基线对照

宿主 Lua 5.4.8，`-e 'unpack=table.unpack'`；LUA_PATH 为仓库 client/shared 路径，ER_PZ_ROOT 为 `/home/hatch/workspace/repos/pzserver/steamapps/downloading/380870`。对照从 `git archive 4eab3a3` 解到 `/tmp/er-ui-baseline`，没有切换或修改工作区基线。

| 检查 | 基线 | 本轮 | 说明 |
|---|---|---|---|
| ui-nav-grouping | 通过 | 112 通过 | 契约更新：删除旧页路由预期，保留单激活、错误跳转、成员定位、组记忆、关闭/重开、默认页与上下文检查；不是放宽业务守卫 |
| ui-distributed-work | 无 | 14 通过 | 真实状态映射、唯一工作计数、三人一个问题、筛选、实际代次及 stopJob 分支 |
| ui-distributed-flow | 无 | 16 通过 | 生产页面；多配方不自动选、无配方说明、提交/取消返回、未认领可见可取消、人员同源与筛选无副作用 |
| ui-product-filter | 无 | 3 通过 | 真实增量 Catalog，非主产物过滤、副本隔离、无相似配方回退 |
| warehouse-query、warehouse-ae2、warehouse-locator、warehouse-metrics | 通过 | 通过 | 仓储读取、定位、指标回归 |
| personnel-enrich、page-lifecycle-integration、lifecycle-scope | 通过 | 通过 | 人员事实、订阅和令牌回归 |
| order-monitor-service、order-monitor-view、demand-monitor | 通过 | 通过 | 后端读取与代次边界保留；不是旧监控页面交互验收 |
| ui-foundation、job-policy-ui-load | 通过 | 通过 | 基础设施、编辑器加载和清理/行高 |
| settlement-tabs | **失败**：295 行 itemList 为 nil | **失败**：232 行仍引用已删除 orders 页 | 已知基线失败未修；本轮更早因批准删除的页面契约而失败，不能把当前失败点冒充同一基线错误，更不能记整套通过 |
| settlement-ui | **失败**：SettlementSelector.lua:90 Events 为 nil | 同样失败 | 相同基线环境替身缺口，未修改该生产路径 |
| crafting-catalog | **失败**：第 27 行首次切片断言 | 同样失败 | 基线旧测试仍替身 ProductionRecipe.read，而当前 Catalog 已读 Facts/fromFacts；本轮未删除或放宽该断言。新增完整接口替身只验证本轮过滤契约 |

静态：全部 20 个改动/新增 Lua 文件 `luac -p` 通过；`git diff --check` 干净；新增翻译 22 对键，两种 JSON 可解析。无新建 OperationsPage；ActivityPage 无差异；demands/orders 不再注册；没有后端删除。

共享文档工具 `../.workbuddy/tools/pz.mjs` 本机不存在，未把官方 doclink 命令记通过；本段相对文档链接另作存在性检查并通过。INDEX/BACKLOG 既有三份 history 快照链接目标缺失（handoff/backlog/readme-before-navigation-cleanup），未把全文件链接检查记通过；本轮新增链接有效。

**未验证**：游戏内页面/字体/长标题与 15 人以上滚动交互、真实桥、Java 编译、游戏动作与原件实际归还、保存重进、性能、面板外提醒。宿主替身通过不能替代这些验收，也不证明零 GC 或性能提升。没有运行完整 preflight 或发布构建。
