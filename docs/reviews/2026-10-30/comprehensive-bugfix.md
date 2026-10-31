# 垂直工种与系统断层修复证据

> 日期：2026-10-30｜状态：代码接入，本地验证；实机、真实磁盘恢复与性能未验。
> 对应[实施计划](../../superpowers/plans/2026-10-30-comprehensive-bugfix-plan.md)，版本0.29.19。保留工作区其他未提交改动，未提交Git、未上传工坊。

## 范围与授权

用户在计划审查后要求由本会话开始修复，采用现有控制器的工种适配器＋最小持久业务记录、产出者交付本批原件。随后明确选择：腐食仅公共容器→接受腐食的废品容器；清洁半径以NPC为中心且不越合法据点；关闭批量备餐时每个原生成品后重新仲裁，指定订单数量不变。

在线唯一需求v4.0已在本对话读取，连接器修改时间2026-10-27。新增手动全员卸货按钮未授权，不在本轮实现。

## 基线及原生依据

- 当前安装projectzomboid.jar SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。构建严格核对该基线及ZombieBuddy JAR，不用旧反编译树代替。
- 参考ProjectRemnants根NPCFW.jar SHA256：`5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E`。只读检查NPCFW_FarmingActions完整桥接、SafehouseFarmerJob当前字节码的预约、moveToInteractionPoint、queueFarmerWater、actionStatus及取消调用；不迁入其独立控制器。
- 安装版ISWaterPlantAction在update逐单位耗水，ISChopTreeAction在animEvent逐次WeaponHit；不能只包装perform记成功。原生ISGrabCorpseAction入口先排ISUnequipAction，complete才抓尸，ISDropCorpseAction在start请求放手。
- 当前JAR的IsoDeadBody.reanimateZombieForGrapple使用原生reanimate；后者复制ModData并转移原库存。fieldDraggedIdentity只读核对拖拽中的原生grapple-only对象标记，不重造尸体、不把未知对象重新贴成目标身份。
- 当前JAR SearchMode.getSearchModeForPlayer直接访问玩家数组。采集没有为NPC实例化ISSearchManager或ISPanel，也不调用destroyUI/修改玩家搜索视效。FieldForage只在同步原版动作调用栈借用该NPC的manager查表，异常后恢复，原产物生成/转移与生态仍走安装版方法。

## 实际接线与覆盖

| 计划事项 | 实际变更 |
|---|---|
| F01—F03 | 四工种统一discover/claim/advance，移除不存在的getPolicy、moveTo链路；无兼容别名。 |
| F04、F08、F09、F20、F23、F24 | cloneArea/cloneAreas与CSG保留工作区z；据点仍用areas联合区域，扫描去重且过滤空洞；指定区缺失/禁用不扩大范围。据点外批准工种区通过FIELD_WORK宏观资格，具体目标和仓储仍重新验证。Zones.copy原本已有多矩形，不重复修。 |
| F05—F07、F32 | FieldWork经现有TaskRuntime/TaskController申请身体，动作走body.add。FIELD_WORK Job写入现有JobStore、资源仍由LaborStore/LaborClaims唯一协调；不另建库存或身体控制器。停止、保存、旧回调、未知效果、拒绝和结清分别处理。 |
| F10、F11 | FieldCargo仅收集本批确认的原件ID，沿共享仓储排名/过滤/容量与原生转移交付；地面原木原实例拾取。满仓、缺仓、原件不明留责等待或隔离，不倾倒全部背包、不删后重造。 |
| F12—F15、F30 | 工具/水领取前校验；无悬空CLAIMING_AXE。装备/卸装走受控原版动作。清洁目标与站位分开，农作避开其他作物格；补运尸移动、真实拖拽/落尸核对与停止放手。原生停稳掩码纳入拖拽/抓取动画，未放手不把身体交给第二任务。 |
| F16—F18 | 厨房限制炉具/制作台发现和执行，并约束实际备餐位置；保质期策略进入共享原件匹配和自主菜单。batchMeals=false限制自主成品目标，之后回到公共仲裁；不改指定订单数量。既有设备义务仍保留关炉/归还权限。 |
| F19、F21、F22 | continuousBatch只在安全交付后续接近处林木，单执行段有界；优先级0不续批。清洁半径按用户决定消费。腐食从公共STORAGE容器中筛选无其他声明原件，目的地须明确接受废品/堆肥且最终复验。 |
| F25—F28 | 矩阵表头允许两行并复用同一列矩形绘制/命中；规程枚举与Chips按文字测量换行且父表单共享高度。活动按钮移至底栏，修正区名/单位硬编码及清洁漏译，CN/EN成对。 |
| F31 | 原版计数、生成/模组spawn函数、毒性识别、ISForageAction入包及生态完成各保留唯一原生入口；移除原版动作外再造物/扣生态的旧适配器。 |

### FIELD_WORK实现契约

- Job envelope沿用现有格式；payload.format=1，包含category、offerKey、target标量身份/坐标/工具ID、phase、sequence、attempt、assets、claims及必要容量/拖拽事实。闭包、userdata和动作队列只在会话内。
- phases为WORK/COLLECT/DELIVER/SETTLED；尝试PREPARED/APPLIED/ABORTED/UNKNOWN。效果不明不重放，身体安全与资产核对分开。终态必须无声明/拖拽/容量、原件全部已交付。
- 重试计时为可重建内存状态，不为了退避修改Job修订号；避免破坏自理恢复关联。前驱已结清时解除续工引用，保留个人自理自身原件义务。
- 拒绝或无效果失败可按证据取消、释放并冷却；携货、持尸和未知效果不走同一清空出口。目录解绑和持久记录退休在正常tick、身体关闭之后。
- Java继续承担污渍/尸体/树木分块扫描。联合区域有游标、去重和共享扫描预算；有效性热路径按权威修订号失效，避免每次原生isValid都深拷贝区域/规程。性能尚未测量。

## 实际验证

- 首轮完整preflight通过：301份Lua，静态0 Error/11 Warning，结构规则无命中；LuaLS 0 Error/638 Warning；全部10项门禁通过。原版ISFluidEmptyAction的`0.0f`导致知识库1份解析失败，不能算全原版覆盖。
- 第二轮完整preflight通过：304份Lua，静态0 Error/11 Warning，LuaLS 0 Error/894信息性Warning，全部10项门禁通过，见 `build/logs/comprehensive-preflight-final.txt`。之后的少量清理和默认优先级元数据修正另经最终语法、相关定向回归与包核对，不冒称完整门禁覆盖之后的每次编辑。
- 工种生命周期21项、动作边界10项、联合区域/规程15项、安装版采集动作/生成适配9项、区域几何26项通过。后四者的原生世界仍由替身提供。
- 安装版采集回归明确令ISPanel.new/getSearchMode报错，验证适配没有触碰它们；构造不入包、complete用原实例入包、perform扣生态、查表异常恢复均通过。
- 自理恢复29项、既有执行会话48项、烹饪原件匹配17项及公共派发/加热/交付/恢复相关定向回归通过；新增排名用例确认后出现的优先原件能参与选择。
- 工作区保存→查询→再次编辑→多矩形执行往返通过。旧测试中文Lua常量在编译阶段被截断，改为Java注入中文再验证；没有改生产名称校验。未把替身问题定性为游戏Bug。
- 规程UI加载与测量折行通过。完整settlement-tabs-test仍失败在“ready restores page and stable item selection”（仓储选择恢复），未算通过；本轮未修改该断言掩盖失败，也未证明该失败由本轮引起。
- 本地Java严格基线构建及打包通过，release-check 0 Error，另有26条其他界面的硬编码中文提示保留，不能称整个模组无硬编码。最终包320文件与模组工作区逐文件一致，无缺失、多余或内容差异；SHA256为`08e5b2fcc55fac3c5eed759c35553ff75e699edc4f816b9e9eaea815be05942a`，见 `build/logs/comprehensive-package-verify.json`。

原始输出集中于 `build/logs/comprehensive-*.txt`。生成包为 `build/packages/EmberRoutesProbe-0.29.19.zip`，未上传工坊。

## 仍未验收的边界

游戏真实寻路/动画/拖尸落点、鼠标/中文英文渲染、真实磁盘保存重进和规模性能未运行；宿主通过不替代这些验收。运尸当前只接人类尸体，动物尸体原版入背包分支未接；播种/翻地原先没有完整执行，本轮没有补成新功能。采集首版不计未测量的探索距离经验加成，只调用原版最低经验规则；不可据此宣称与玩家所有搜寻策略完全等价。

旧版纯内存作业没有可验证的恢复记录，本轮不伪造迁移、不删除携带原件。新Job正常恢复协议已有回归，真实磁盘和强退一致性仍未验证。完整UI页签失败另留待定位；在该项和实机验收完成前，不宣称“全面Bug修复验收完成”。

## Bug阶段续修：0.29.20

用户批准解释后的源头修复，并要求减少重复夹具体力工作，优先检查资产、停止、保存与派工正确性。本批沿用现有架构和存档格式。

- 规程服务不再用默认值覆盖未知格式；读取阻止执行，草稿返回明确错误，UI展示CN/EN阻断原因。保存统一经Ledger.view核对操作者和据点，通知改用真实LaborSignals.changed。旧测试伪造notify的错误接缝已移除。
- 工种候选通过派工发现环境的candidateReady先过滤退避，再计入三项候选额度；最终仲裁复验仍保留。前三项退避、第四项有效已定向验证。
- 烹饪扫描与完成快照TTL分开：扫描保留原有每轮预算、库存/Claims修订和端点核对，时钟回退仍失效；完成时登记scanStartedAt/observedAt，完成后的缓存仍按两秒/游戏时间过期。1502件静止库存可以完成。该观察仍是跨时段扫描，不能称作同一瞬间的原子库存快照，也未实测高倍速和规模性能。
- Zones提供整区覆盖和联合容量，活动资格/规则/人数使用所有矩形；同层重叠去重，不同楼层独立计算。没有增加新的区域账本。
- 仓储保存网格自己的滚动位置，未知库存重扫和页签往返后恢复；搜索等显式查询变化重置。旧第2页断言与连续网格不符，现检验完整网格、稳定选择和真实滚动。原选择并未丢失，原先将整条失败简称为“选中态恢复失败”不够精确。
- 追加核对当前安装版ISForageAction的complete（原件入包）与perform（采集点/生态结算）接缝。原适配器在两步之间停止仍报KNOWN/APPLIED；FieldActions现在在停止结算时复验既有afterPerform证明，缺失则记UNKNOWN并保留目标/原件责任，不自动补执行。重复settle不会抹去不确定性；不增加控制器或存档字段。真实引擎回调间可中断时序未实机。
- 归属交接复核发现FIELD_WORK互锁：跨据点改派等待旧责任结清，而普通劳动资格拒绝pendingCommand；RETURN也被普通劳动资格拒绝，返回流程却在等待旧义务。FieldWork现在仅在原归属下存在待跨区改派/解除归属或RETURN且已有确认货物时，转入现有COLLECT/DELIVER阶段，经RECOVERY处理旧原件；不继续劳动或续批。旧据点权限、原件/容量及唯一身体复验仍保留；FOLLOW不走此恢复例外，无新增持久字段。正常改派到新据点仍由MembershipService在旧义务结清后提交。

本地验证：规程31、工种生命周期36、活动上下文40、共享烹饪供给16、动作边界13项通过；采集安装版动作适配9项、规程UI加载/排版及已有归属运行链定向通过。工种交接用真实MembershipPolicy、Runtime、Jobs与Claims，交付效果为替身，验证待改派和RETURN时旧原件交付、不会续批及清除原任务义务。新增复现只为具体故障，没有重跑全历史套件。完整CN页签已通过仓储恢复断言，后续在旧SettlementSelector替身缺derive处失败；当前整个页签套件仍未通过，不更改生产继承结构来迁就替身。

Java严格基线构建通过，release-check为0 Error/26条既有界面中文提示。0.29.20包320文件与模组工作区逐文件一致，记录见 `build/logs/bug-stage1-package.json`。整模组preflight通过：304份Lua，静态0 Error/11 Warning，LuaLS 0 Error/767信息性Warning，10项门禁通过。之后FieldActions停止结算和FieldWork交接收口另经逐文件静态0 Error/0 Warning及相关安装版Kahlua回归；完整门禁与最后两份文件的定向检查分开记录，不冒称同一最终快照全量检查。原始日志为 `build/logs/bug-stage1-*.txt`。初次误把仓库根传入preflight而扫描到测试/临时探针的失败输出保留；已改用明确模组根执行正式检查。

后续审查优先：FIELD_WORK未结责任目前没有接入OrderMonitorService的现有CRAFT/HAUL/COOKING投影，需核对异常可见性与既有监控契约；不因此新建第二账本或擅自增加核销玩法。真实动作、磁盘保存重进和性能仍未验收。

## 并行架构优化接缝收口（2026-10-31）

用户确认其他AI正在同一工作区进行架构优化，随后指定本会话收口已定位接缝。当前源码与历史0.29.21包存在差异，不能据旧日志认定当前代码通过；本轮不恢复旧包，不覆盖其他优化，不改当前0.29.16版本/JAR，不构建或发布新包。

- HaulingProvider原先在模块顶层反向require PublicWork，而PublicWork又require HaulingProvider，宿主加载重复进入两模块。修复采用已有env.directory，成功认领回执保存原目录句柄，结清只向该目录释放；释放失败保留回执供后续重试，移除已无调用者的PublicWork.directory。仍由原Work/Job承担原件和身体责任，未增加账本、调度器或存档字段。
- RuntimeGate.canExecute原来把nil当作仅检查环境，SettlementLedger.authorized随后却调用actor:getIndex。隔离宿主复现空操作者崩溃。执行门禁现在要求操作者；纯环境检查保持独立isSinglePlayer。测试同时验证真实Ledger的空操作者拒绝、合法本地玩家与身份不符拒绝。
- cooking-public-test在SAVE后已经确认取消结清；实际失败是夹具直接加入新锅后未发库存通知，随后15秒发现窗口仍处于既有30秒共享退避。旧0.29.21包和当前源码均复现；在隔离副本发同一库存失效通知后均通过原流程。因此仅补夹具通知，没有修改生产保存/退避策略，也不能把该失败归因于另一AI。

- 经用户裁决采纳方案A：解耦SelfCare状态查询与物理执行动作。SelfCare.lua移除顶层对SelfCareExecution的静态加载，改为在实际创建任务时通过use('SelfCareExecution')按需加载；SelfCareActions安全加载并在实例化前守卫原生TimedActions（ISEatFoodAction/ISDrinkFluidAction），彻底根除公共调度因单点缺动作导致的DISPATCH_BLOCKED瘫痪。task-production-runtime-test（66项）、task-companion-runtime-test、task-legacy-craft-runtime-test、cooking-agent-test、self-care-loop-test等通过；全库扫描162套用例中已通过136套。

现有runtime-gate-test、hauling-provider-test、cooking-public-test安装版Kahlua回归通过，日志为`build/logs/architecture-seams-regressions.txt`。搬运覆盖独立加载、认领、未结保留、结清、释放失败重试、原目录绑定、重置及缺目录不启动劳动；烹饪涵盖原有保存停止、自理前驱和指定订单流程，物理世界与动作载体仍为替身。源码指纹见`build/logs/architecture-seams-source.json`。

完整静态preflight通过：307份Lua，静态0 Error/11 Warning，结构与候选不变量检查通过，LuaLS 0 Error/794 Warning，索引新鲜度10项通过；非EOL项目按工具规则跳过check_health。Warning包含动态字段、空值及其他诊断，本轮不宣称全部为噪音或已清零。原始输出为`build/logs/architecture-seams-preflight.txt`。结束后修复文件与回归时指纹一致，检查启动后未发现Lua文件修改；仅本轮三个生产模块的差异见`build/logs/architecture-seams-source.diff`。文档链接检查通过。本批没有完成全项目修复或真实玩法验收；原生寻路/动作、磁盘重进、完整UI与性能不因这些宿主检查视作通过。
