# 制作任务负重策略

## 2026-10-24 真实消耗模式及公共领单修正（0.24.1）

用户实机反馈配方公共工单都因负重取消。读取当前console.txt确认两名NPC锯大树枝均被算作weight=0、maximum=6、added=7、consumed=0、output=3、peak=10、limit=8.99，并经REJECTED_UNCOLLECTED结束。原版LargeBranch重量6、SawLargeBranch消耗默认mode而非显式Destroy，锯作为keep工具；正确一批峰值应为max(7,7−6+3)=7。

- ProductionCarry不再把“非Destroy”当作不会整件消耗。当前安装JAR的CraftRecipeData.processUsedItems调用ItemUser.UseItem处理普通输入；已核对的单次使用、非部分用量、无CreateTo/ConsumeFrom及无替代容器输入可以抵扣原件重量。保留工具、多次使用、部分输入与替代物继续保守处理。未放宽前两档超重上限，也没有重复按特质补能力。
- ProductionChain的直接配方只读预检复用同一单批负重规则；整张公共需求预查的后续批次材料不累加为本批负重。真带不动时，公共需求保持WAITING并显示负重原因，在分配Job/认领原件之前拒绝该候选。负重失败冷却仅作用于该NPC，不阻塞其他有能力工人立即领同一单。复杂前置链或实际领取后能力下降仍须在执行阶段重验。
- 已关联公共Order的执行Job遇负重不足保留PAUSED及恢复引用，不再调用旧“未取料就取消”收束。已有原件和不明效果均不释放。旧指定NPC诊断/私有执行的既有释放政策保持原契约。
- 日志中的SawLogs另有真实限制：当前NPC能力6，单批原木和锯的待取重量10，本身就超过8.99，即使正确抵扣消耗也不能搬起它们。该公共单应等待合适工人/负重条件，而非取消；不以修正峰值估算冒充任意NPC均能搬动原木。
- 不复活历史CANCELLED任务：旧取消原因未必能区分自动拒绝与用户取消。受旧缺陷影响的已取消需求需要重新下单，仓库原件不删除、不重造。

基线仍为下文PZ42.21.0 JAR SHA256。当前安装脚本已查SawLogs/SawLargeBranch及LargeBranch重量；新增只读javap证据位于build/research/carry-repair-{manager,inputdata,cache,itemuser}-javap.txt，实机触发日志片段在carry-repair-console.txt。定向回归：production-carry-test 26项、task-production-runtime-test 60项及public-work-test 46项通过，覆盖默认消耗、单批而非全单负重、真实超重预领单拒绝、公共Job暂停及能力恢复后同Job完成、弱工人失败不阻塞强工人；原生效果仍为宿主替身。原始输出为build/logs/carry-repair-regression.txt。0.24.1构建成功，最终归档150文件与源码一致；最终release-check通过（0错误/151提示，含并行UI提示）。完整preflight通过：141个Lua文件，LuaLS 0错误/183信息性警告，保留原版ISFluidEmptyAction.lua的0.0f方言解析缺口；文档链接检查通过。门禁、构建、归档、发布与文档输出分别为build/logs/carry-repair-{preflight,build,package,release,doclink}.txt。实机修复效果尚未复测。

验证范围补充：本次preflight记录141个Lua文件的负重修复基线。扫描期间共享工作区另有仓储/UI并行更新（含LiquidRegistry、PinyinHelper及页面调整），保留这些改动；最终归档重新核对为150文件与当前源码一致。本专题不将负重回归或前述类型扫描扩大为并行修改的完整验收。

### 三批锯原木专项复核（同版本，无生产代码变更）

用户进一步质疑三批总重量会导致无人能接。新增tests/lua/production-three-batch-test.lua，复用当前安装原版Lua动作及现有原版来源配方夹具，直接调用公共领单使用的ProductionChain预检和带orderId/chain的Production执行。NPC能力8，每根原木9、锯1，三根加工具总重28超过11.99，但单批重量10；预检通过且不认领原件，随后三次提交交付9块木板，任一时刻最多携带一根原木，峰值10，原锯最终归还。7项专项断言通过，原始输出build/logs/three-batch-carry-regression.txt；身体/物品与原生制作效果为替身，游戏未运行。本轮未修改产品Lua或重建版本，保留0.24.1已有单批规则；不把此前仅两份材料的辅助函数用例冒充三批完整路径验证。

## 2026-10-23 实机故障修正（0.22.14）

0.22.13日志确认两名不同NPC：adbba889…的新锯原木工单因CAPACITY_UNAVAILABLE暂停，数次归还可完成CANCELLED；00f750b5…的旧工单9611b5f1…则反复ITEM_MISSING。不能把两者当作同一NPC占用，也不能据此推断共享负重。

- 保持逐NPC读取getInventory/getMaxWeight，未放宽超重策略。失败日志新增NPC/工单ID、当前重量、能力、容器容量、待取重量、明确消耗、产物重量、峰值和限制；真实负重拒绝的数值原因仍待新版实机日志。
- 受控路径在确认身体停止、效果已知、尚无生产/交付且全部声明原件仍位于已核对仓库时，将负重拒绝工单收束为CANCELLED并释放本单认领；已携货或原件不明继续保留恢复记录。未以删除工单跳过资产清理。
- 取消归还跳过已经确认交付的产物，避免产物后续被消费/移走后误报ITEM_MISSING；未交付原件缺失仍阻断，日志补充具体物品ID与来源/目标。此修正不证明上述旧工单一定属于已交付产物问题，也未自动抹除旧记录。
- 修正最低存量界面格式化翻译缺参数导致的MissingFormatArgumentException刷屏，格式化参数直接交给原版getText。

定向Kahlua：负重18项、受控制作44项（包含既有制作652项夹具）通过，覆盖双NPC能力隔离、取料前拒绝后重新下单、携货后能力下降、已交付产物离库后取消、真正缺失原件不得同类替换。原始输出：build/logs/p1-production-repair-tests.txt。0.22.14构建、preflight、release-check（0错误/44提示）、文档链接/空白检查及三个改动Lua文件包内一致性通过，日志同目录p1-production-repair-*。结构扫描仍有原版ISFluidEmptyAction.lua方言解析覆盖缺口；游戏复测尚未运行，P1仍被实机故障阻塞。

日期：2026-10-22。用户批准允许原版前两档超重，并考虑特质兼容。仅调整格式3正式制作执行；普通物流和历史制作探针策略不变。

## 原版依据

42.21.0 projectzomboid.jar SHA256：E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。

- Moodle.update 使用主库存 getCapacityWeight / getMaxWeight；MoodleStat 默认阈值为1、1.25、1.5、1.75。BodyDamage 的超重扣血分支从档位大于2开始，另有生命值、坐姿、代谢等条件。
- ItemContainer.getEffectiveCapacity 保留原版容器容量与整理特质计算；不能以放宽劳动策略代替 hasRoomFor。
- HandcraftLogic.performCurrentRecipe 调用 CraftRecipeData.perform；createOutputsInternal 成功后先 destroyAllSurvivingDestroyInputs，再返回原生Lua动作交付产物。因此仅 isDestroy 的整件输入可预先抵扣重量，保留或其他用量输入仍保守计算。
- ProbeNpc.update 调用 super.update，并未设置上帝模式或自行固化负重能力。不重复按特质名叠加力量/容量加成。

原始字节码输出在 build/logs：moodle-weight-javap.txt、moodlestat-weight-javap.txt、bodydamage-weight-javap.txt、itemcontainer-carry-javap.txt、handcraft-carry-javap.txt、recipedata-carry-javap.txt、inputscript-carry-javap.txt。

## 实现

ProductionCarry 统一计算：当前有效重量W、待拿取重量A、明确销毁重量D、单批产物O，要求 max(W+A, W+A-D+O) 不超过 min(原版有效容器容量, 当前负重能力×1.5−0.01)。逐件领取不抵扣未来消耗；动作开始和提交前重验，调度tick重验当前重量。已有背包减重随原版主库存有效重量计入，新原料/工具进入主包，按未装备重量计算，不扩展到自动装包。

第三档边界、非法数值和单件带不动均拒绝；批量工单仍逐单批取料/制作/交付，不因为总目标大就一次拿齐。容量失败暂停，不加入反复自动重试。能力在持货期间下降会停工并保留原件认领；本轮没有新增自动卸货或生活恢复行为，不能承诺后续一直站立不会产生原版伤害。可使用既有取消归还。

兼容边界：跟随原版实时能力、有效重量和容器容量；不承诺第三方重新定义超重档位/伤害规则自动兼容。不拦截原版健康或移动惩罚。

## 检查

- production-carry-test.lua：16项，覆盖档位边界、浮点余量、当前有效重量、能力变化、容器容量、阶段峰值、工具不得抵扣、非法数值、物流策略不变。
- craft-probe-test.lua：累计652项，新增能力8携带原木9/锯0.7完成制作并归还；第三档取料前拒绝；持货后能力下降暂停且保留认领。原生Lua动作运行，库存、身体、效果和移动为替身。
- 原始宿主结果：build/logs/production-carry-tests.txt；完整静态检查：build/logs/production-carry-preflight.txt。
- 完整 preflight 最终通过（99个Lua文件）；文档链接检查通过。
- 尚未实机验证特质、背包减重、动作效果和实际伤害；不宣称性能或第三方模组验收。仅更新源码，未重建旧发布ZIP。
