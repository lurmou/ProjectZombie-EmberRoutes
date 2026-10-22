# 0.6.0 标签与真实库存任务实现记录

日期：2026-10-19。实现和本地检查，游戏实机未验证。依据[v3.1](../../requirements/2026-10-19-v3.1-original.txt)、[设计](../../superpowers/specs/2026-10-19-real-haul-design.md)、[计划](../../superpowers/plans/2026-10-19-real-haul.md)。高性能/扩展/维护的用户要求已加入开发规则，并授权存入EmberRoutes独立Hindsight库；不是性能已验证结论。

## 模块契约

| 模块 | 责任与接口 |
|---|---|
| InventoryPolicy | registerTag(id,{read,write})、access(tag,intent)、planExplicit(container,eligible)：用途注册、读写策略和本轮派单 |
| InventoryView | index(containers)、find(index,id)：短期只读索引，一次扫描三处库存；不持久化对象，不作为资产账本 |
| ContainerRegistry | tag、select、resolve(id,intent,scopeId)、data：稳定容器ID、坐标/标签及加载验证 |
| Work | execute、tick、pause、hasCargo：单NPC单执行者、任务ID、版本/类型/范围、暂停及续工 |
| WorkTransfer | move/context与item/context的start/poll：原版动作适配，在效果边界复核权限/身份/容量 |

未来分类、生产、维生与商队装卸应产出明确源/目标和物品ID，复用执行边界。当前scopeId=local-world只表达单人范围，不冒充阵营权限；多NPC预留仲裁、宏观交接和多任务调度另验。未知标签默认拒绝，标签可注册扩展。

Boot接tick/cancel/reset，保存先暂停工作再保存NPC。其他指令接互斥交接；UI删除前检查任务货物。任务不创建、删除或回滚真实物品；旧探针夹具仍走原诊断清理。持有货物时不可遗忘任务，嵌套包也检查；缺失后续条目时先交付已有货物再暂停，不凭类型造替代品。

显式删除NPC且确认无任务货物时取消其任务元数据，物品留实际容器，避免新NPC被旧任务锁死；无法确认原NPC则保守阻止删除。只覆盖本模组UI入口，不拦截游戏死亡或其他模组删除。

规划最多30件、登记256容器、每库存扫描2000件；无工作时不扫描，调度最多10Hz，效果边界额外核验。InventoryView让每次规划/报告复杂度为源+NPC+目标库存，不逐ID重复扫描。本阶段没有真实帧耗时或NPC规模测量。

## 证据与检查边界

构建复核当前游戏/ZombieBuddy固定哈希与[基线](baseline.json)一致。当前安装media/lua/client/TimedActions/ISInventoryTransferAction.lua的isValid/perform/transferItem为原生转移、容量、队列和动画依据；每实例适配去掉真实玩家loot窗口选择。原版perform内还会调用isValid。ModData.getOrCreate见当前Foraging/forageClient.lua；收藏/装备接口核对当前InventoryItem.java。靠近点契约沿[0.5.3证据](probe-0.5.3-approach-fix.md)。

替身覆盖未标签/私人、原实例及自定义状态、重复开工、拿货后暂停并重建执行上下文、撤权效果边界、途中箱满、缺失/重复ID、原NPC归属、路径拒绝、限额、只读标签及另一世界隔离。它们不证明原生动作/保存兼容，须按[集中测试](../../testing/single-player-real-haul.md)验收。正常世界保存无跨文件原子提交保证，不承诺死亡/强退/拆除零损失。

本地结果：[构建](probe-0.6.0-build.txt)、[Lua回归](probe-0.6.0-lua-tests.txt)、[最终任务/保存边界测试](probe-0.6.0-work-tests.txt)、[preflight](probe-0.6.0-preflight.txt)、[发布检查](probe-0.6.0-release-check.txt)、[文档检查](probe-0.6.0-doclink.txt)、[冲突扫描](probe-0.6.0-modscan.txt)均通过。最终LuaLS零错误/警告，文档9份无断链；知识库原版ISFluidEmptyAction.lua的0.0f语法解析缺口仍有提示，无client/EOL故跳过专用健康检查。任务测试调用真实Persistence处理器验证先暂停再交给替身Java检查点；实际世界序列化仍未运行。见[验证元数据](probe-0.6.0-verification.json)和[构建元数据](probe-0.6.0-build.json)；不累加嵌套调用旧套件的断言数。
