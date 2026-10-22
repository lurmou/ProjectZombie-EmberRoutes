# 0.17.1：分类仓储取还与通用制作表面

> 2026-10-21｜状态：实现及必要门禁完成；实机未验证｜主代理独立实施

用户明确纠正0.17.0：制作不能默认拿玩家物品；木叉只需通用平台，不强制砧板；直接复用已有分类储物箱取料、交付及归还工具。本轮按此修正，不另建一套生产箱设置。唯一在线需求重新读取成功，SHA256仍为`3A179F1907B8971E0DD13F8FC2FFA300F0661E6F68C7AA0E7EC3E37202499834`；用户本轮明确决定覆盖原型选样引入的错误限制。

## 行为修正

- 新单从同据点、已登记、过滤匹配的共享STORAGE箱选取1件SmallHandle和1把配方允许的刀。已有NPC可用工具也可复用；完成后仍按分类规则归还工具箱。玩家背包不作为新单来源、交付目标或缺料回退。
- 产物和工具分别复用现有分类索引找目标箱，遵循精确类型/分类优先级、距离和稳定ID排序。允许材料箱、工具箱和成品箱不同，不要求固定返回原箱。没有匹配目标或容量不足时暂停保留原件，不把产物交给玩家或重新制作。
- 移除Chopping_Block、实体脚本和CraftBench组件硬限制。木叉必须是当前原版的AnySurfaceCraft且不要求专用工作站；普通有效表面可以用。表面存在性及原版isGenericCraftingSurface、NPC的canUseAsGenericCraftingSurface仍须通过；外观平整不代表有效。
- NPC复用原有移动原语到箱子/平台，再用原版TA转移与制作，保持原件实例、ID和磨损。玩家无需一直站在NPC旁，本原型仍要求操作者与NPC处于有权限的该据点。新单只读箱子/NPC主容器，不搜索包中包。

## 复用与权威

`CraftSupply`复用SettlementMembership、ContainerRegistry、StorageFilter、SortPolicy和LaborProducers；不复制分类规则或维护平行箱子标签。登记成员/目标反向索引/找料每次推进最多32个规划步，进入Work既有全局工人预算；单箱最多2000项、全次最多20000项，不每帧全箱扫描。仅在明确启动/恢复时重建这份短生命周期计划，效果前复验位置、权限、过滤、原件和容量余量。

`CraftRecord`提供纯记录校验及资源列表；`LaborStore`将制作记录和普通搬运记录恢复到同一个LaborClaims缓存，在完整核查后发布。跨任务物品、NPC或ID冲突直接阻断；普通搬运的claim/publish入口也不能绕过待处理制作记录，避免依赖模块加载顺序。Native valid检查读取缓存，不在每次动作有效性检查里全文遍历生产记录。

新增原子追加认领：先完整检查所有新资源，成功后一次追加实际产物ID；失败不部分追加、不释放原输入。单件流程持续持有耗材ID、工具ID、表面资源及实际输出ID，直至分类交付/归还闭合后统一释放。这里是单件有界追加，不宣称完整多件BOM集合替换协议已经完成。

新记录format2存稳定据点/来源/目标/NPC/原件ID，不存引擎对象；旧format1仅保留显式归还兼容，避免升级丢掉0.17.0已经借走的原件。新建路径不会使用玩家库存。保存、取消和过期代次门禁继续有效；未知原生提交不自动重放。产物已落地时保留原件ID及认领，只有找到已核对的原件并完成分类交付才可闭合。

## 验证及边界

- 93项定向Kahlua检查通过：当前安装ISHandcraftAction/ActionManager Lua、实际CraftSupply/LaborStore/LaborClaims/SortPolicy业务模块；引擎、权限/分类描述宿主、容器、队列、移动和存档为替身。新单把玩家getInventory设为抛错，覆盖空箱时玩家持有同类物品仍缺料；普通无实体脚本/无CraftBench表面可制作；不同分类箱取还、原有NPC工具归类、取消/保存、隐私/排除/诊断保护、同类替换、权限变化、消耗后异常、落地输出和认领冲突均通过。最终输出见[93项检查记录](crafting/0.17.1-contract-check.txt)；相关回归输出保留在`build/logs/craft-storage-final.txt`。
- 相关multi-worker与logistics-progress回归通过；夹具内部复用旧搬运断言，没有运行全历史测试。原子追加失败无部分提交、普通物流抢工具、同NPC直接发布绕过及加载冲突有定向检查。
- 当前JAR静态核查：HandcraftLogic.findCraftSurface调用角色canUseAsGenericCraftingSurface；AnySurfaceCraft只需有效表面/距离，专用工作站另判。原版OnNewCraft以HandcraftLogic.new(player,nil,nil)配合findCraftSurface，证明无需把通用配方绑定CraftBench。固定JAR基线沿用[制作基线](crafting/baseline.json)。
- 0.17.1版本构建、固定JAR及现有Java检查通过，没有修改Java业务源码。原始输出`build/logs/build-0.17.1.txt`；最终源码门禁、发布检查和包核对结果在下方收尾记录。

工作区期间新增的NpcDebugMenu保留原有行为，仅将其一处裸print接入统一Log，处理发布门禁命中；没有删除或改写NPC调试菜单功能。

游戏引擎未启动，真实平台/移动/转移/磨损/占用/存档仍未验证。完整BOM、多件订单、正式制作页、未加载区生产及崩溃原子落盘未实现或未证明。按[三组简短实测](../../testing/single-player-native-crafting.md)确认，不把逻辑检查当实机验收。

## 收尾检查

必要preflight通过：79个Lua语法检查无错误/警告，LuaLS零错误、3条信息性提示；release-check零错误/提示。最终Lua重新打包，逐文件字节比对全部86个文件一致，见[包核对记录](crafting/0.17.1-package-check.json)。既有0.17.1 JAR未重新改写，游戏引擎未运行。
