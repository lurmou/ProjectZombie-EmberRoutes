# 制作任务负重策略

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
