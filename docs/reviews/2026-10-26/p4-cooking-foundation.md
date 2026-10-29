# P4 厨师基础与原版动作：实施与证据

日期：2026-10-26。用户在详细设计及评审修订后明确“开始吧。基础必须打好”；按[设计0.3](../../superpowers/specs/2026-10-26-p4-cooking-and-supervision-design.md)及[执行计划](../../superpowers/plans/2026-10-26-p4-cooking.md)开工。未发布新版本，工作区仍为0.29.11；保留另一个AI的生活/姿态/保存修复。

## 已落地的基础

| 模块 | 当前能力与限制 |
|---|---|
| CookingPolicy | 按正式归属且未retired的全部NPC计人口；FOLLOW/RETURN不扣，待提交移籍仍算原据点。u=0.15、L=N×u、H=2N×u；低于L可允许经核验的最小批次越H，已有最低储备时不为不足一批的缺口另做大锅。未接入公共供餐策略生命周期 |
| CookingRecord / JobStore | COOKING沿同一共享Job保存标量事实、资产清单、不可变额度及单调attempt。COMMITTING先标UNKNOWN；无匹配回执不可APPLIED，回执不能改写，未知时不能删除原件声明。终态不得遗留原件/炉具责任；拷贝有大小/深度/循环限制。原版动作层现已提供三类回执，固定配方及流体仍待接 |
| CookingBudget | P与未知阻断额度从同一Job派生，无第二份持久额度账。观察版本变化、同帧竞争、重复请求及NPC已有任务均拒绝；成品已交付量从P扣除，避免与S双算。REQUEST占用的专属批次不当公共供餐。原生快照新鲜度及交付资格尚需后续公共服务在认领前重验 |
| LaborStore | COOKING与搬运、制作、自理共用唯一Claims；提交失败回滚逻辑声明；旧revision/token失效。加载先重建已知或未知原件声明，不启动动作。尚未接容量声明、炉具接班或运行时保存收束 |
| CookingFood | 区分getHungChange原始余量与getHungerChange有效饱食度，排除不安全、未熟、冻结、调料和未适配餐具需求。只读，不修改食物；不推断完整食谱产量 |
| CookingFacilities / MealSupplyIndex | 现有据点注册容器与权限、有界批读和PlanningWake失效机制；未加载/无法读取保留未知，不当零库存。S只计有效冷藏中可直接消费、未被声明占用的成品。制冷读取原生isFridge/isFreezer、isPowered与getTemperature；炉具只读普通IsoStove状态。当前仅为扫描原语，尚无每据点共享缓存/服务及设施路径/空间预留 |

这些文件尚未注册新的公共候选或自动开火入口，不代表NPC已经会做饭。

## 后续接入：原版动作与炉具责任

用户继续下一步后，新增CookingActions、CookingContext、CookingInventory、CookingDuty，沿同一Job/Claims使用调用者的body能力；没有第二个执行循环。

- 三类生效点分别为：加料/调料的原版complete、搬运的原版transferItem、炉具的原版complete/Toggle。只对当次实例包装；搬运关闭原版跨动作合并，防止同一回调处理其他任务原件。
- 每一步显式传递单调sequence；同序号只读取相同意图的既有结果，旧序号拒绝，UNKNOWN/COMMITTING不重放。入队前保存dispatched，生效前保存COMMITTING/UNKNOWN；正常停止且原件未变化才记ABORTED。ABORTED不是未观察效果的回滚通道。
- 加料前核对基底/食材身份、原版实际准入与原始余量；返回基底使用action.baseItem的真实引用，主料必须有新增的extra marker及明确耗量，调料须从未添加变为已添加，且不超过2次。原版spice分支会在有效余量接近耗尽时UseAndSync，非调料也有最后使用阈值，因此原件消失时不强求原始饱食值恰好为0；必须同时具备当次正耗量和真实结果/marker，转移到其他库存仍视作未知。
- 同步原版调用即使抛错也观察输出；UNKNOWN期间只能在保留全部旧声明的基础上追加新原件。未知新物品先中性保管，不因出现新Food就获得餐食产量。只有原版实际返回并核对的基底才记为OUTPUT。
- Duty与Session分离：设备由同Job声明，初始已开的炉具不接管；启动后保留开火归属，原版Toggle不会因重复回调再次触发。有外人物品时不擅自关火；身份/责任不明继续保留。熟食按原版有效剩余饱食度更新；断电、熟食或不安全结果要求收尾。已经确认自有炉具被玩家/断电关闭时只观察OFF并取出，不重新点火。
- 关火后仍持有炉内原件声明；确认实际取出后才解除设备责任，成品继续归同Job。交付再验过滤、权限、实际容量、有效冷藏及食品可直接食用，提交时失电则保留厨师手中原件。当前未接持久容量预留，因此只完成提交时物理检查，不能称完整容量协调。

这些是可复用动作叶与责任原语；CookingAgent、定时检查、接班与保存屏障候选尚未接通，不构成已启用的完整自主烹饪/防火系统。

## 当前安装版与参考依据

- 当前projectzomboid.jar SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。
- ProjectRemnants根NPCFW.jar SHA256：`5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E`。读其完整求餐/锅内加工/交付机制，关键分支核对当前根JAR；不复制独立控制器、按件估量和腐烂配料放行。
- 安装版`shared/TimedActions/ISAddItemInRecipe.lua`：真实加料在complete，返回值写回self.baseItem，基底可能合法替换；perform主要结束队列。不能只拦perform认定原件安全，停止不提供通用回滚。
- 安装版`shared/TimedActions/ISToggleStoveAction.lua`：complete调用Toggle；重复一次即反向切换。必须先保存意图、重读当前状态，再决定是否执行，恢复时不能重放Toggle。
- 安装版`client/TimedActions/ISInventoryTransferAction.lua`：perform会收集合并队列，再从transferItem调用ISTransferAction实际移动；不能只用perform被调用推定原件已转移。适配器保留原版移动，不自行Remove/AddItem。
- 重新核对当前根NPCFW.jar的NPCEvolvedRecipeExecutor与RecipeExecutor字节码：前者把addItem返回引用作为结果，清理是原动作/声效/移动收束；后者保留stationWasActive/activatedStation并以hasForeignWork限制关火。只借鉴结果引用及设备归属机制，不复制其独立控制器或setActivated路径。字节码输出保存在`build/logs/p4-reference-evolved-javap.txt`、`p4-reference-stove-javap.txt`及`p4-vanilla-evolved-javap.txt`。
- 当前ItemContainer字节码：isPowered依赖有效parent对象和checkObjectPowered；getTemperature在有效供电冷藏分支返回0.2，自定义温度有更早分支。实现同时验类型/供电/温度，不用设备名称猜制冷。
- 当前Food与Eat字节码：实际HUNGER消费用getHungerChange，包含熟食修正；getHungChange仍用于追踪原件消耗，不统一替换现有自理算法。
- MakeBreadDough有学习要求、流体输入和多种工具；BreadDough脚本中未见ReplaceOnCooked变成Base.Bread。固定面包链未适配，不以配方接口存在声称完成。

## 实际检查

- 安装版Kahlua：`cooking-foundation-test.lua` 55条边界断言、`cooking-supply-test.lua` 11条、受影响的`job-store-test.lua` 35条通过。前两份复用既有搬运/多工人夹具，原生物件与动作是替身；没有执行真实烹饪或磁盘保存。
- 继续实施的`cooking-actions-test.lua` 34项通过；直接加载当前安装版ISAddItemInRecipe.lua、ISToggleStoveAction.lua，Java物件/配方效果/队列和搬运端口为替身。覆盖基底替换、部分主料/调料、近耗尽原件移除、抛错后保管新旧原件、同序号重建不重放、过期身体、停止、同炉外人物品、熟食关火、断电/玩家关闭不重开、原件取回、冷藏失电不交付；没有实际引擎动画或温度推进。原始输出`build/logs/p4-cooking-actions-kahlua.txt`包含34项及上述三份受影响检查通过。
- 定向风险覆盖：外出人口/移籍、半锅有效量、小批越量、两厨师额度、交付双算、旧回调/回执、原件争用与回滚、加载声明重建、断电冷藏、私人/未加载仓储。
- 基础阶段完整preflight通过，退出码0；Lua语法0错误/4警告，LuaLS 0错误/26警告，结构规则和索引新鲜度通过。已逐项检查首轮新增的炉具字段警告：当前JAR确有这些方法，instanceof确认后补IsoStove类型缩窄，不再报告这6条警告。原始输出保存在`build/logs/p4-cooking-foundation-preflight.txt`。工具另列安装版原版ISFluidEmptyAction.lua的0.0f解析缺口；没有因此修改原版或宣称该文件已检查。
- 动作接入后的最终完整preflight通过，退出码0：210份Lua，语法0错误/4警告；LuaLS 0错误/27警告；结构规则、候选规则及索引新鲜度通过，原始输出`build/logs/p4-cooking-actions-preflight.txt`。专项LuaLS明细另存`build/logs/p4-cooking-actions-luals.txt`，该次列出的诊断均在既有非Cooking文件；多人工作区后续原位检查总数有变化，不把27/28条诊断差异冒充本轮修复。modscan未发现与已装模组的整文件冲突；当前四份变更文档doclink无断链/错误/提示。
- 5份变更文档doclink通过，断链/错误/提示均为0。
- Java未修改，不重跑无关构建；不打包发布、不改版本、不提交混合工作区。

## 尚需接通

接Profiles/Planner与每据点共享供餐观察服务、有效冷藏路径及持久容量、固定配方/纯水动作、CookingAgent和Duty调度/明确接班；再沿公共派发接厨师矩阵/指定请求/知识研习及锅内食物进食，保持原有唯一Session。

未知效果不会因超时释放；当前动作结束能观察即时效果，尚无加载后完整观察器或人工核销。恢复闭环仍未完成。扫描时间漂移、实际原件重新定位及认领时的冷藏/容量重验仍须接服务层；动作提交时已对所选端点重验。实际寻路、加料/调味、加热、关火、食用、保存重进和性能均未实机验证；整个P4未完成。

## 2026-10-27：共享配方事实与输入/输出绑定底座

用户确认共享配方架构和六步次序后再次要求开工。本轮代码覆盖首层事实读取与精确绑定，不把黄油闭环或自主厨师标为完成。

| 接缝 | 当前实现与限制 |
|---|---|
| CraftRecipeFacts.read(id,native?) | 有界读取当前CraftRecipe事实，保留原版IO、父子流体槽、数量单位对应资源、工位/回调/特殊输出事实和定义签名。含运行时原版对象，只作内部观察，不能整体持久化或当执行许可 |
| ProductionRecipe.fromFacts | 继续原有普通物品输入、整件消耗、普通台面/手持、固定输出等限制；旧生产签名构造保持，未放开流体、特定工位、回调或特殊输出 |
| CraftingCatalog.recipeIndex | 同一次增量目录读取生成完整事实生产者索引；原productionIndex仍只提供现有执行器支持的配方。世界根变化一同清空，不另起全表扫描。单配方事实越界会明确返回限制，不能称兼容任意大小模组配方 |
| CraftRecipeInputs.bind/applied | 按原版父IO索引绑定实际原件，输出manual映射和标量输入描述；首批流体形态只接受单件保留容器及固定流体子槽，实际奶液足量且满足原版过滤。新逐槽核对接入普通ProductionActions，在start、perform及performRecipe生效前检查，防止总集合正确而槽位错配 |
| CookingRecord.bindings | 同Job保存有界、追加式真实产物引用，ADD记录原版实际返回的baseAfterId，CRAFT沿已观察outputIds。序号/attempt/原件绑定不可修改或删除，重复完成不追加；旧格式记录仍可读，但不虚构旧历史。resolveOutput拒绝未知效果、跨attempt引用、已消耗/交付/归还原件 |

新增原版API依据：当前安装版`ISHandcraftAction.start`先手工输入再调用canPerformCurrentRecipe填实际缓存；`ISCraftInventoryPanel.populate`和`ISWidgetInput`实际使用getDataForInputScript。当前JAR确认InputScriptData继承CacheData的getAppliedItemsCount/hasAppliedItem，用于逐槽核对真正应用的输入；没有把getManualInputItems的请求缓冲当作实际应用结果。`LuaManager$Exposer`明确注册CraftRecipeData、CacheData、InputScriptData与HandcraftLogic，未假定任意Java内部类自动暴露给Lua。流体父槽规则继续沿同一JAR的InputScript/CraftRecipeData查证。

实际检查：

- `recipe-facts-test.lua`20项通过：父子槽、流体原文及解析量签名变化、单容器、不拼瓶、不用水冒充奶、旧ID/稀疏分配/销毁容器拒绝、逐槽错配、可发现但不可执行、世界切换失效。原生对象为替身。
- `production-three-batch-test.lua`通过，包含既有制作/兼容/依赖/负重夹具及三批单批搬运7项；加载安装版普通制作Lua，配方、身体、库存与效果为替身。说明新接缝未破坏该宿主中的普通制作，不等于实机验收。
- `cooking-actions-test.lua`40项通过，新增替换基底的真实输出引用、保存数据副本、伪造attempt、禁止改写/删除历史与重复回调不追加；另跑55项Cooking基础和35项JobStore受影响检查。沿安装版加料/Toggle Lua，原生效果仍为替身。
- 原始宿主输出：build/logs/p4-recipe-bindings-kahlua.txt、p4-output-bindings-kahlua.txt。完整preflight通过：212份Lua，语法0错误/4警告，LuaLS 0错误/26警告，结构/候选/新鲜度通过；输出build/logs/p4-recipe-bindings-preflight.txt。单列LuaLS诊断输出p4-recipe-bindings-luals.txt中的27条均在既有非本轮文件，不把警告数量变化当作修复成果；逐槽缓存字节码留存p4-recipe-slot-javap.txt。

未接通：流体描述进入BOM模拟分配、组成快照与实际消耗观察、特定工位索引/占用与会话退出、同Job固定配方动作、渐进取水、CookingAgent/派发。新流体绑定器存在不构成执行许可；旧生产仍拒绝黄油。没有启动自主开火、改Java、打包发布或修改版本；未运行游戏，不声明真实动画、保存或性能通过。

## 2026-10-27续接：黄油原生制作、流体观察与工位退出

以下续接覆盖上一节列出的组成/消耗观察、特定工位候选/占用与内部固定制作动作；上一节“未接通”是该次边界，不代表这些接缝仍全部未做。完整自动黄油生产和自主厨师仍未完成。

| 模块 | 本轮接入与保护 |
|---|---|
| CraftFluids | 从真实FluidContainer创建FluidSample，读取原生流体类型、各分量、总量与容量后归还采样池；快照可保存。比较前后体积及比例组成，只有符合原版按比例removeFluid的固定体积消耗才确认，不把等量换液当奶液扣减 |
| SettlementFacilities / CraftStations | 沿同一据点扫描识别CraftBench组件；分预算读取原版getRecipes做能力匹配。候选不写身份；认领时分配/沿用现有BenchId，使用同一craft-surface声明与旧生产互斥。执行前再次查权限、设备原对象、配方与原版距离 |
| CookingActions.craft / CookingCraft | 调用者提供已持有的精确输入和候选设备，沿同一Job/attempt/Session执行ISHandcraftAction。只开放已核验的整件/保留容器固定流体与固定物品输出形态；回调、可变输入、映射结果、机器资源槽等仍拒绝，NPC实际知识/技能与保守动态容量重验 |
| 提交与产物 | 单人包住实际performRecipe，生效前持久化COMMITTING/UNKNOWN并再验身体权威。紧邻原生效果读取背包基线，避免把长动作期间玩家加入的物品认成配方产物；核对原件、逐槽应用缓存、真实液量/组成、保留容器及真实输出。只有原版完整返回且全部核对才确认；异常或落地仍追加观察到的原件，WORLD/UNKNOWN不算成功交付，不重放 |
| 工位义务与停止 | payload.station记录位置、稳定ID、leaseId与取得阶段，物件上的占用标记关联同一Job/NPC/lease。实际设置UsingPlayer前保存意图，入队前取得原生占用。正常动作结束和Context.stopAdapter沿同一release；后者接现有TaskBusinessStop/TaskController停稳证据，补处理原生动作stop未回调的情况，不增加全局循环 |

释放规则：已取得/可能取得原生占用时必须确认身体停止、同一原件/责任与租约标记，不能清除新会话或玩家占用；仅预约、尚未调用原生setter时可以撤销逻辑预约，哪怕家具已搬走或玩家已抢先使用。未知制作效果可以在证明停稳后清除本次原生使用者，但逻辑声明保留到效果核对，不因超时丢弃。重进时保留工位事实与重建声明，未实现自动解锁未知旧占用；调用方须捕获本Session停止适配器，不能裸跑动作后丢掉上下文。

原版依据仍为当前projectzomboid.jar SHA256 E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。本轮核对安装版ISHandcraftAction完整start/perform/performRecipe/stop链路、CraftBench.getRecipes、HandcraftLogic.isCharacterInRangeOfWorkbench、FluidContainer.createFluidSample/removeFluid及CraftRecipeManager流体消耗；后者保留原过滤与实际扣减，不自行扣液。javap输出留存build/logs/p4-butter-fluidcontainer-javap.txt、p4-butter-manager-javap.txt。参考ProjectRemnants现有RecipePlanner拒绝特定工位，仅作边界参考，不宣称它已解决搅乳桶链。

补核LuaManager.Exposer：Fluid与FluidSample已暴露，FluidInstance未列入当前注册。最终快照仅调用FluidSample.getPercentage与Fluid.getFluidTypeString读取组成，按快照总量计算各分量，不跨入未暴露的FluidInstance.getAmount；采样池在正常读取及显式拒绝分支均归还。原始注册表字节码为p4-butter-exposer-javap.txt，宿主将getFluidInstance设为抛错哨兵，防止替身误放行内部API。

实际检查：

- 安装版Kahlua加载当前ISHandcraftAction：25项工位/复合流体接缝通过，覆盖正常扣5留1、原容器保留、输出引用、重复/改槽重放拒绝、错误液量、混合物变化、原生异常与落地、会话撤销、跳过action.stop、未取得占用时玩家抢先/家具消失、同NPC后继租约及采样池归还。实体、流体与移动仍是替身。
- 共享设施索引3项与既有家具身份/占用26项通过；另跑40项原版加料/Toggle动作、20项配方事实、55项Cooking基础与35项JobStore受影响检查。原始输出build/logs/p4-butter-kahlua.txt和p4-butter-facilities-kahlua.txt。
- 额外settlement-repose-discovery-test未通过：在未修改的ReposeSites床位评分处调用替身Properties.has失败。只在诊断进程内恢复本轮之前的设施分类器后仍在同处失败，确认不是新增CraftBench分类分支引起；未修改床位代码或掩盖该失败。原始失败与隔离对照为p4-butter-repose-fixture-failure.txt、p4-butter-repose-control-failure.txt，控制脚本p4-repose-classifier-control.lua不属于正式模组。
- 最终整仓preflight未通过：并行PublicWork.lua在342/362/364/387/398处引用waiting/retryReady/cool，而相应local function定义位于545/551/559之后，没有前置局部声明，Lua词法作用域不能向后捕获这些局部函数。最终快照217份Lua、5错误/4警告；结构检查、附加规则、候选规则和新鲜度通过，LuaLS 0错误/27警告。未改该文件，不能把整仓检查写成通过；输出p4-butter-preflight.txt。本轮7份模块独立lua-lint为0错误/0警告，输出p4-butter-scoped-lint.txt。
- 首轮LuaLS列出CraftStations.release的4处可空对象警告，已对实际需要已加载原件的分支补显式nil拒绝；最终整仓类型门禁无Error。单列初次诊断p4-butter-luals.txt不代表最终警告总数，包含并行文件及先前快照。过程中另一次整仓快照命中过并行DeliveryCartDrawer的StatMeter:create调用，随后该文件已被并行改为new；本轮未修改其代码，不把别人的修正归为本轮成果。

当前是原生动作接缝，不是已启用的厨师服务：流体BOM库存分配、自动取料搬运、Agent/公共派发、渐进取水/自由汤链、炉具完整恢复仍待续接；原版实际操作距离、动画、正常磁盘保存重进与性能未实机。没有修改Java、发布包或版本，保留并行生活修复。

2026-10-27夹具修复：用户单独要求处理上述床位回归失败。仅补齐settlement-repose-discovery-test中单床替身的属性标记与has(flag)，按标记集合返回布尔值，不把所有属性都当true；未改ReposeSites或PublicWork。安装版Kahlua重跑该入口，既有家具26项及据点/跨层/加载发现15项通过，原始输出p4-repose-fixture-fix-kahlua.txt。上述床位夹具失败已解决，不代表实机睡眠已验收或PublicWork错误同时修复。

## 2026-10-27续接：流体BOM与自动原件选择

用户要求继续下一步。本轮仍沿既有执行计划，未增加新的产品规则。原ProductionChainPlan新增按FLUID_VOLUME分配的父容器输入：每次制作必须由一件原件供足所需液量，多批分别选件或复用有剩余液体的同一原件；已模拟消耗的液量不能重复使用。同次不能把一件载体分给两个父槽，也不能同时当作另一工具或被消耗物；回溯分支复制体积与分配事实，不污染其他候选。节点fluidInputs只记录实际itemId、父slot、批次和用量，不保存原版对象或执行移动/加水/加热。缺液不推导未实现的灌装、拼瓶或产奶；仅有某类容器的物品生产者不代表能生产其中的液体。

CraftRecipeInputs.planning只转换已由CookingCraft.profile核验过的能力形态，保留原版canUseItem/isFluidMatch过滤及通配输入，不用容器类型代替流体条件。CookingSupply复用ProductionSupply原仓储权限、声明过滤、有界扫描和增广路径匹配，单批选择真实原件与来源端点，再喂入同一BOM。扫描后再次核对原件位置、已有声明、资格和液体；未加载源导致不足时报告CHAIN_INVENTORY_UNKNOWN，不把未观察库存当空。世界切换/取消丢弃候选。旧ProductionRecipe执行门槛保持，普通生产不因此开放黄油；此接口不创建Job、不认领/搬运原件、不占用工位，后续由同Job Agent在认领及每步动作前再验。

参考与原版：先查ProjectRemnants当前根NPCFW.jar的RecipePlanner，对照其按物品身份维护fluidAmounts及分支副本的做法；其requiresSpecificWorkstation拒绝分支仍保留，不能宣称参考已有搅乳桶闭环。当前安装版Base.churn_butter仍为item 1 [*]下挂-fluid 5.0，核对InputScript.isAcceptsAnyItem/isFluidMatch及ISHandcraftAction手工父槽输入/实际执行缓存。字节码留存build/logs/p4-fluid-reference-javap.txt与p4-fluid-input-javap.txt；基线沿上节固定JAR，没有新增原生液体写入。

定向检查：16项纯流体BOM、14项共享仓储原件选择、22项事实/输入绑定通过；18项旧依赖规划、51项预算/匹配及三批普通制作回归通过，既有25项工位/流体和40项动作宿主也通过。使用安装版Kahlua，原件/仓储/原生效果仍是替身，未运行游戏。原始输出p4-fluid-bom-kahlua.txt、p4-fluid-selection-final-kahlua.txt、p4-fluid-materials-kahlua.txt。最终4模块独立语法lint零错误/警告，p4-fluid-materials-scoped-lint.txt。最终整仓preflight退出码0：219份Lua、语法0错误/4警告、LuaLS 0错误/33警告，结构/候选/新鲜度通过；原始输出p4-fluid-materials-final-preflight.txt。本轮未修改PublicWork，其上一轮5处作用域错误已在并行修改后消失，不再作为当前阻塞。

另跑逐条LuaLS诊断，0错误/33警告，均不在本轮CookingSupply、CraftRecipeInputs、ProductionSupply和ProductionChainPlan四模块；明细p4-fluid-materials-luals.txt。不把全仓警告数量变化归为本轮修复。

尚未接通实际取料/归还与CookingAgent、公共供餐、渐进取水/自由料理和炉具完整恢复；自动选料不能算完整自动黄油制作。未修改Java/版本、未打包发布，保留并行修改。

## 2026-10-27续接：固定请求批次的原件搬运与CookingAgent

上一节未接通的实际取料/归还与Agent已在本节限定范围内续接，公共入口仍未启用。CookingBatch.prepare将已选原件转换为同一REQUEST Job的标量父槽/来源清单；固定定义签名、原件和来源不可改写。首批单批最多16输入原件，不把普通Production执行门槛放开，也不额外建立烹饪库存或配方链。

CookingAgent.new(actor,binding,job,object,budgets,safe,options?)返回现有TaskRuntime的spec与执行上下文，调用方先通过TaskJobs保存同一Job再submit。budget及安全观察由调用方提供；Agent无独立tick事件或身体控制器。captureStop使用当前Session的CookingContext.stopAdapter。CookingCargo沿InventoryView分预算查原件，沿WorkTransfer/Driver走实际目标，沿原有CookingActions转移和ISHandcraftAction制作。材料来源、权限、原件位置、负重、知识及冷藏分别重验，来源撤权后停止读取旧私有库存；共享CraftSupply路由只新增可选端点过滤，旧调用默认行为不变。冷藏失效或无法交付时保留真实产物与声明，不远程挪物或结清。

正常路径：先核冷藏/本批负重/知识，预约原工位，逐件取原材料，移动到工位，原版制作并核对，停稳释放原生UsingPlayer，交付实际产物到有效冷藏，归还同一借用容器/器具。原来就在NPC主背包的保留工具确认仍在原背包后结清，不伪造一次搬运。未取的原件可由settleOnly核对仍在授权来源后撤销声明；已经携带的必须实际归还。

黄油是配料而非现有MealSupply口径中的餐食，因此本轮固定批次限定REQUEST：允许经过实际固定配方确认的安全Food配料交付冷藏，AUTO仍要求原有ready餐食判定，未将黄油塞入meal白名单或增加储备贡献。尚未支持需要后续加热的固定产物交付；保持食物安全硬门槛，待炉具完整链续接。

恢复协议：fixed.craftSequence在原生制作前保存；已知制作回执恢复时沿真实outputIds定位，只交付/归还，不重放制作。只有明确ABORTED的未生效CRAFT才能换新序号开工；UNKNOWN拒绝重建Agent。上下文停止补齐RUNNING→STOPPING→SUSPENDED/RECONCILE_REQUIRED状态接缝；完成全部原件收束后先SETTLING，再由TaskRuntime证明Lua/原生身体已停，才写DONE/CANCELLED、SETTLED并结束空声明令牌。旧身体/世界或新租约不能由旧停止回调清理。

参考核查：先读ProjectRemnants RecipeExecutor的FETCH_INPUTS/CRAFT/STORE_OUTPUT阶段及原件转移，核对当前根NPCFW.jar（5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E）字节码，留存build/logs/p4-agent-reference-javap.txt；不复制其独立jobs循环。当前安装版projectzomboid.jar仍为E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。原生动作依据沿前节已核验ISInventoryTransferAction.transferItem、ISHandcraftAction.performRecipe、工位range/UsingPlayer和本项目唯一Driver移动端口；实际引擎寻路仍未验证。

安装版Kahlua定向检查：18项Agent断言通过，加载真实TaskRuntime、TaskController、BT、JobStore/Claims及安装版ISHandcraftAction Lua，覆盖真实序号串联、借用原件归还、冷藏交付、停稳终态、取料前/取料后/制作前撤销、制作后恢复不重做、已知ABORTED新序号、未知原生异常保管、来源不可改写。原件、流体、寻路、搬运和Java控制仍是替身，不能记作游戏验收。另跑既有40项动作、25项工位/流体、55项基础、16项流体BOM、14项选料以及普通制作三批回归。输出build/logs/p4-agent-kahlua.txt、p4-agent-integration-kahlua.txt。

移动叶在请求停止后还须观察当前身体的nativeStopped，不能因坐标已相邻或stop返回true就排队制作/转移；宿主延迟清停稳掩码验证该边界。完整preflight通过，222份Lua、语法0错误/4警告、LuaLS 0错误/34警告，结构/候选/新鲜度通过，原始输出p4-agent-final-preflight.txt；8模块独立lint零错误/警告，p4-agent-scoped-lint.txt。逐条类型诊断较早快照为0错误/30警告（p4-agent-luals.txt），不把并行工作区的警告数变化当作本轮修复。最后进一步限制Agent只能接受PREPARING/SUSPENDED/SETTLING，拒绝直接重启RUNNING/STOPPING现场；该窄改补Agent独立lint及18项宿主通过，最终宿主输出p4-agent-final-kahlua.txt。四份变更文档doclink无断链/错误。

尚未接通：公共CookingProvider/启动/人员矩阵和请求UI、待授权请求取消后的业务收束、自动恢复候选与完整磁盘重进、渐进取水/自由料理和加热Duty闭环。这里是可被现有Runtime提交的内部固定请求链，不是玩家已可使用的自主厨师；不改Java/版本、不打包发布，保留并行修改。

## 2026-10-27续接：渐进纯水与自由加料内部链

用户继续授权下一步，沿已批准§21.7执行。本轮新增CookingWater、CookingWaterSources和CookingEvolved，继续使用同一CookingRecord/JobStore/Claims/Session，无新生产账本、事件循环或普通Production能力放宽。上节未接的取水/自由加料已在本节范围内续接，完整厨师仍未开放。

原版与参考核查：先对照ProjectRemnants当前RecipeExecutor.tickFillWater的载体余量、重选水源、移动/取水阶段及根NPCFW.jar的NPCWaterFillExecutor（字节码p4-water-reference-javap.txt），不复制其独立任务循环。当前安装版ISTakeWaterAction在update→updateUse→transferFluid逐步写液体，complete再补足，stop不倒回；构造waterUnit按容器余量/水源可用量/角色自由容量取小值，保持原计划，不修改成“精确灌0.9锅”。当前IsoObject.transferFluidTo、getPrimaryFluid及isTaintedWater包含直连流体、虚拟原生供水、外接取样净化等不同分支，不能凭水龙头名称假定纯水或无限量；字节码p4-water-isoobject-javap.txt。EvolvedRecipe.hasMinimumWater实际要求isAllCategory(Water)且getFilledRatio达到minimumWater，项目另加纯净水硬门；p4-water-evolved-javap.txt。

取水协议：CookingWater.take(c,sequence,item,object)只包装本次ISTakeWaterAction实例，写水仍由原版执行。WATER attempt保存原件、源身份、初始纯水事实与原版最大计划量；首个实际transferFluid前持久化COMMITTING/UNKNOWN。运行中同attempt返回Running，每次真实写入前后有界观察两端，累计原版实际增量，不每帧签新序号或完整发布Job。直接有限流体设施核对两端增减；原生无组件供水按已核验分支读取水源与目标实际进度，不强套无限源或等量库存模型。任一异常、组成变化、无法归属的增减或过时代次均保留未知与原件声明，不回填液体。

正常结束或受控停止必须先证明身体/原生队列已停，再读取实际增量确认回执，保留锅内已有水。CookingContext在这一停稳边界把已知部分结果传给TaskController效果证据，避免业务Job已确认却仍把保存事实记录为UNKNOWN。下一次以锅内真实余量重新构造原版动作，旧dispatch/未知attempt禁止恢复执行。源责任在同Claims上使用cooking:water键，已知停稳才释放；未知逻辑责任保留，加载不自动解锁或重放。

发现与换源：共享SettlementFacilities以原生getFluidCapacity记录FLUID_SOURCE特征，仍保留床/座椅/工位等既有事实；不按NPC另扫世界。CookingWaterSources在实际据点权限和原对象位置内读取、候选不写身份；纯水与资源声明重验后认领。ensure(c,recipe,item)按已有Cargo路径与调用方预算移动，当前候选耗尽后保留锅内进度并找下一候选，记录当前观察下不可用项，补水或观察代次变化可重查。无候选明确等待，不在空水槽原地无限重试。首批支持直接纯水流体设施及已确认纯水的原生无组件供水；getUsesExternalWaterSource路径可能取样净化或转发混合物，未取得完整成分证明时返回WATER_SOURCE_UNSUPPORTED，不做额外烧水/净化。

自由加料：CookingEvolved.new(c,recipe,base,ingredients,target)接收已归本Job持有的原件，按当前原版EvolvedRecipe能力签名核验，先过纯水/最低比例门，再通过既有CookingActions.add逐次加主料。主料达到soft target（至少u/2）即可收束，原料列表不足最低量时不冒充合法一餐；调料只处理已有列表中最多2种不同可用项，无料/重复/不适用即跳过，调料不增加主料目标进度。字段payload.evolved保存不可改写的输入/目标、当前游标和ADD实际产物引用；首份料替换原锅后，下份使用真实输出ID。确认回执先保存、游标还没推进时可依据该回执恢复推进，不能重复加同一份；已知ABORTED才重建下一序号。当前只完成备料混合，生汤仍需后续原生加热，原件/供餐责任不提前结清。

检查：安装版Kahlua加载当前ISTakeWaterAction与ISAddItemInRecipe，14项渐进取水和9项自由料理断言通过：同attempt多次实际写水而无逐帧Job发布、部分停止/控制器效果证据、按真实余量重启、两源接力/首个效果前源被抽干仍换源、混合物/未核验外接供水拒绝、原生异常后不重放、真实替换基底、主料目标、调料去重/上限、原始生汤不计熟食、回执先于游标的恢复去重。世界、流体写入及寻路仍是替身，不构成实机。另跑18项固定请求Agent、40项动作、25项工位、55项基础、共享工位索引3项及家具26/据点15项受影响检查。原始输出p4-water-evolved-kahlua.txt、p4-water-evolved-final-kahlua.txt。

最终完整preflight通过：225份Lua、语法0错误/4警告、LuaLS 0错误/30警告，结构/候选/新鲜度通过，p4-water-evolved-final-preflight.txt；7模块独立lint零错误/警告，p4-water-evolved-scoped-lint.txt。警告总数随并行快照变化，不算本轮消除其他模块的诊断。

未接通：ISFluidTransferAction的物品倒液体/外接供水完整成分验证、自由料理自动选料/取料及CookingAgent分支、实际炉具加载/等待/取出/条件关火与Duty恢复、公共派发和产品入口、真实磁盘重进/性能/原生寻路与玩法验收。水和料的内部步骤已接，不把它当作完整自动汤或已可用自主厨师；未改Java/版本、未打包发布，保留并行改动。

## 2026-10-27续接：成组接通加热、交付及同NPC恢复

用户要求“多个小功能一起做”。本轮合并为同一内部流程：炉内装载/加热观察、分批取熟后关火、冷藏失效换址、断电或中断收尾、设备身份保护与只读恢复候选。CookingAgent已能接已完成备料的evolved Job，与既有固定请求共用TaskRuntime/BT、Job/Claims、动作与停止协议；不新增独立监督事件循环，也未开放公共厨师。

CookingHeat.new(c,ids,endpoint?,cleanupOnly?)保存同Job不可改写的真实热加工原件ID集合，使用普通通电IsoStove；按调用方预算找设备、实际移动/停稳，开火前检查有效冷藏与食物机制资格。装载/取出沿既有原版transferItem生效点，开关沿ISToggleStoveAction.complete→Toggle，不直接改Activated或食物熟度。正常等待按250ms现实时间或1游戏秒到期复查现有Duty，真实Food的getHeat/getCookingTime/isCooked为观察事实，不按计时赋予成熟。到位后不逐tick重复发Java停止请求。

多原件逐件取熟：一件已熟先取出到主背包，其他原件仍可在炉内原生加热；最后一件取出后才关火，避免关闭后的余温继续烧焦。Duty.expected按整个热加工批次汇总，已取出的熟食也计入，防止部分出炉使P被低估。正常可观察、空炉、OFF、已证明本Job关闭并无炉内原件后才结清设备声明。

承重不足无法取出时允许先关已知自有炉具，保留STATION原件和Duty，之后同Job重取；这是紧急收尾，不把关火当交付。断电、外部OFF或已有Duty的恢复只取出/关闭，不再次点火。安全但未熟的Food实际存回有效冷藏并记RETURNED，整个批次CANCELLED且expected=0，不冒充成品；冷藏也失电则原件继续HELD/被声明，设备已安全关闭后等待收纳。烧焦/不安全食物不自动投入公共食物库存；设备证明空且关闭可结清，但食物仍保留责任。外人物品或未授权ON使Duty进入核对，能合法取出的本批原件先取回，不接管外人物品、不无条件关玩家设备。

设备与恢复：新Duty保存endpointId和原坐标；身份/坐标在同Job不可改写，恢复通过ContainerRegistry解析原设备，未加载不等于OFF/空炉。旧缺身份记录保持可读但拒绝自动恢复，不伪造旧位置。CookingRecovery.new(actor,binding):step(budget)只沿现有JobStore的NPC索引生成标量候选，读设备/原件与成员事实，不认领、不发布Job、不操纵身体；UNKNOWN、未证停稳、原件缺失、身份变化或责任不清给明确阻断。已知ON保留监管责任，已知外部OFF只允许排空；实际恢复仍须通过原Runtime申请唯一身体。

CookingCargo同时修正多原件游标：确认原件已到位后也等待上一个原版动作退出，随后清旧动作树，防止下一原件复用前一转移动作而被跳过。冷藏PUT在提交前失效且能证明未生效时，保留同一原件/Job，沿原仓储排序有界换址（每原件最多8次本轮尝试）；撤权或效果未知不偷读私有容器后重放。自由料理未用完的主料/调料沿授权仓储物理归还，不凭缺少固定配方来源就假装已归还个人背包。

支持边界：首次加热只接受本次已核验、原件不因加热替换且无OnCooked回调的Food；未知加热替换/回调在装载前拒绝，不猜测热加工新ID。原版PotOfSoupRecipe为同原件Cooked标志、ReplaceOnUse返锅而不是ReplaceOnCooked；面团等热加工换物形态仍待原件绑定适配。原版JAR仍为E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33，根NPCFW.jar仍为5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E。先查参考RecipeExecutor的WAIT_STATION/UNLOAD_STATION分批取熟及500ms观察，再对照当前Food烹饪/烧焦和原版Toggle实际入口；未复制其直接setActivated/自动重开路线。字节码p4-heat-food-javap.txt、p4-heat-reference-javap.txt；同原件汤的定义来自当前generated/items/food.txt。

检查：22项新加热/交付/恢复断言通过，使用真实CookingAgent、TaskRuntime/TaskController、BT、JobStore/Claims和安装版动作Lua，覆盖多件分批取熟/取出后关火、真实饱食贡献、冷藏失效换址、保持Duty的中断、同NPC只排空恢复、紧急先OFF后取出、外部OFF不重开、炉具和冷藏同时失电后的原件保管、外人物品核对、候选只读及身份不可改写。原生温度/熟度推进、Java控制、寻路及搬运效果是替身，不能作为实机或性能结论。另跑18项黄油Agent、40项动作、25项工位、14项取水、9项自由加料及55项基础受影响检查。原始输出p4-heat-kahlua.txt、p4-heat-final-kahlua.txt；7模块独立lint零错误/警告，p4-heat-scoped-lint.txt。最终完整preflight退出码0：227份Lua、语法0错误/4警告、LuaLS 0错误/30警告，结构/候选/新鲜度通过，p4-heat-final-preflight.txt。首次逐条类型诊断命中本轮Cargo可空目标与Recovery可空设备，已补明确目标契约/空值拒绝；复跑逐条类型检查0错误/33警告，本轮7模块无诊断（p4-heat-final-luals.txt）。警告数量因并行快照变化不一致，不把其他模块诊断归为本轮修复；四份变更文档doclink无断链/错误。

仍未接公共CookingProvider/厨师入口、共享选菜/供餐观察与自由料理自动取料、自动消费恢复候选、TaskPersistence开机唤醒、跨厨师责任接班及成品进食适配。即时危险停止仍优先撤离，炉具Duty会保留；当前内部候选没有后台自动接班者，不能据此启用无人监管自主开火或承诺无烧焦/无火灾。真实正常磁盘保存重进、原生热加工/寻路和规模性能均未实机；不改Java/版本、不打包发布，保留并行修改。

## 2026-10-27续接：共享观察、原版事实选料和自由料理取料/续做

用户继续授权成组开发。新增CookingSupplyService与CookingMenu；扩展既有CookingEvolved/Cargo/Agent/Heat/Recovery与同一CookingRecord。没有修改PublicWork/Boot或启用自主开火，公共派发与炉具恢复消费者仍未完成。

共享观察：每个据点只持有一个MealSupplyIndex增量游标；同50ms切片不被多厨师重复推进，实际读取扣调用方共享预算。库存/权限变化、既有CookingBudget的Job版本、现有Claims的占有集合版本均为失效条件；缓存最长2秒或1游戏分钟，快进同样过期。人口从正式成员事实即时重算，全员持续计入，已退役剔除。未完成或不明读数无ready字段，不能当零库存；入场重新核对快照与额度，不信任调用方改写的人口/储备字段。额度仍来自Job，Claims版本仅是可丢弃的观察提示，容量变化不冒充物品占有变化。

选料：先查ProjectRemnants RecipePlanner.allocateEvolvedStage/evolvedIngredientUsable的ItemRecipe.use与needToBeCooked，再核对安装版ISInventoryPaneContextMenu.getRealEvolvedItemUse和当前EvolvedRecipe字节码（p4-selection-evolved-javap.txt）。原版getItemsCanBeUse受MinimumWater门槛限制，空锅规划不能假装已经灌水，也不为选料试调用addItem。CookingMenu按原生ItemRecipe与Food安全事实给只读候选；按getOffAge-getAge排序安全生鲜，保留原件ID/容器，实际执行仍经原版过滤。调料仅从所选锅/主料已需停靠的容器中取，最多两种。估量不写成已确认expected，准备阶段不搬运/认领/消费；实际加料仍按真实产物与饱食度收束。原版getEvolvedRecipes最终委托ScriptManager.getAllEvolvedRecipes，直接通过已核验的manager接口读同一目录（p4-collection-registry-javap.txt）；生鲜读取签名p4-menu-freshness-javap.txt。未适配的热替换/回调、额外器具/冷餐类型仍不因能选中而获得执行承诺。

原件来源与执行：prepare将锅和每件主料/调料写入同Job，来源信息不可改写；Cargo定位包含原锅，取料、实际ADD替换、加热、冷藏交付和余料原仓归还沿同一Runtime规格。已有个人原件只在明确provenance的新计划中归还个人背包；旧缺来源记录不据此推断为个人财产。中途停止后继续实际新基底，不重拿已消费的原锅，不重加已有回执的食材。取消会识别回执先于游标的实际半成品，将安全未熟原件RETURNED到有效冷藏且expected=0；未使用过灶台时直接收尾，不借取消重新占用/开火。恢复候选增加未完成自由料理，但准备恢复仍需当前WORK资格，不能以RECOVERY资格偷开工。

实际检查：cooking-menu-test覆盖原版事实选料、临界生鲜、同停靠点调料、只读/声明变化失效和缺指定配方不替代；cooking-collection-test覆盖自动取锅/原料、基底替换、中途停稳后同Job续做、余料原仓归还，以及取消回执已保存/游标未推进的半成品且无可用灶台；cooking-supply-service-test覆盖共享游标、全员人口、调用方副本隔离、多人额度竞争、无库存通知的原件声明变化和双时钟过期。固定黄油Agent、既有动作/取水/加料/炉具和基础回归通过。原始输出build/logs/p4-menu-final-kahlua.txt、p4-collection-final-kahlua.txt、p4-supply-service-kahlua.txt。这些运行了安装版Kahlua与原版动作Lua，世界/配方实际效果仍为替身，未实机。

完整preflight通过：229份Lua、语法0错误/4警告，LuaLS 0错误/31警告，结构/候选/新鲜度通过，build/logs/p4-collection-final-preflight.txt。首次lint未识别原版getEvolvedRecipes全局，已改为经字节码确认的同一manager接口，未改工具白名单或隐藏诊断；首次调料夹具改到了路由缓存过滤副本，已修成实际容器过滤，未放宽产品权限。

逐条LuaLS输出build/logs/p4-collection-final-luals.txt确认本轮Agent有一处单值赋给两个局部的提示（第二值有意为nil）；末轮已拆为独立声明，Agent/Menu/SupplyService定向lint零错误/警告，build/logs/p4-collection-final-scoped-lint.txt。该纯声明整理后未再重复完整preflight/LuaLS，其他模块的既有诊断未修改。getAge/getOffAge定义在Food的InventoryItem基类，证据文件已按实际继承位置保留。

仍缺公共CookingProvider/Boot与优先级产品入口、恢复候选自动消费/明确跨厨师接班、持久交付容量、指定请求/研习/进食闭环、物品倒液体及完整外接供水适配。本组提供内部可组合规格，不宣称自主厨师已开放。未改Java、版本或发布包；真实原生玩法、磁盘重进、规模性能仍未验证。
