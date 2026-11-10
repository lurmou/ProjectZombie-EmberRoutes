---
name: add-provider
description: Add or refactor a PublicWork provider using the actual dispatcher, body-session and retained-asset contracts.
---

# 工种接入手册

更新：2026-11-06｜状态：active。遵循[生命周期规则](../../rules/provider-lifecycle.md)和[工作领域](../../../docs/domains/work.md)。本手册描述当前代码，不新增业务契约。

## 1. 先读实际调用方

从 `client/EmberRoutesProbe/Work/PublicWork.lua` 的发现、候选选择和派发分支开始，再读目标领域已有Provider。至少核对 `Field/FarmingProvider.lua` 与 `Hauling/HaulingProvider.lua`：前者延迟加载后委托组合服务，后者直接实现发现/认领/结清，不能机械复制同一种结构。

## 2. 当前回调协议

| 回调 | 当前调用方式与语义 |
|---|---|
| discover | `provider.discover(envDiscover)`；通过env中的candidates/directory等上下文发布候选，不约定返回数组 |
| claim | `provider.claim(selected,npcId,jobId,env)`；目录在PublicWork中先claim；env提供actor/entry/now/directory/releaseOffer。返回QUEUED或STARTED表示接手；拒绝时若本次认领未留下业务效果，返回第二个值'ROLLED_BACK'，派发方才释放offer，否则offer保留分配并记录诊断原因。createClaimedJob失败时用`Store.createEffectsUnknown(code,evidence)`判断：为true（TASK_WRITE_FAILURE但证据不是写入前拒绝码、或ROLLBACK_FAILURE）不得声明；只有证据精确等于JobStore.create写入前拒绝码（如CRAFT_SCOPE_RECONCILE_REQUIRED）才可声明。工种不自行解析证据，无法识别一律保守保留 |
| advance | `provider.advance({actor=actor,now=now,directory=directory})`；适用于有后台推进的领域，不是每个身体Session的帧回调 |
| reconcile | `provider.reconcile()`；领域按真实业务记录核对责任，不是统一的reconcile(jobId,outcome) |
| hasWork | 当前为无参数的领域查询；具体用途以调用方为准，不等于“可给此NPC派工” |
| retained | `provider.retained(npcId)`；本领域有该NPC未结束的Job时返回true，eligible按注册顺序问，第一个true即不派新工。延迟加载的薄壳也要转发，并保留原有门控：Field薄壳直接调FieldWork.retained，不受原生能力门控；cooking仍按原样受carrierActive门控，载体未激活时返回false。新工种不要因原生能力关闭而返回false |
| reset | `provider.reset()`；世界根替换时由`Providers.resetWorld()`按注册顺序调用，只清本模块的每世界缓存 |
| command | `provider.command(o,action)`；订单category等于本工种时，PublicWork.command过完通用守卫（可用、Ledger、revision）后整单交给它，返回值原样返回（现为cooking） |
| orderCommanded / orderRetired | 无category的公共制作订单被玩家命令改变 / 已结清订单被退役时扇出通知，`orderRetired(id,readyWorkers)`（现为crafting清计划代数） |
| retireUnclaimed | `provider.retireUnclaimed(o)`；无Job、无craftProgress的DONE订单只有其category工种返回true才退役（现为cooking） |
| priorityRequired | 布尔声明，不是函数；为true时setPriorities必须带此工种的优先级（现为crafting、hauling） |

`PublicWorkProviders.register(def)`检查category与defaultPriority，要求discover与claim是函数，可选钩子（列表见注册表`optHooks`）若存在也须是函数；不合格返回`false,原因码`，内置工种由PublicWork的assertRegister在加载时报错。按真实业务实现需要的钩子，不发明通用参数或返回值。

## 3. 身体执行

领域通过 `Runtime/TaskRuntime.current():submit(spec)` 提交候选。先读TaskRuntime中START_SPEC_REQUIRED校验及一个完整生产调用方，如 `Settlement/MembershipReturn.lua`；spec必须提供npcId/jobId/kind/binding/validate/start/tick/finished/stopAdapter/persistFailure等当前必需项。

TaskController由运行时创建。`TaskController.new():request(...)`排队，`attachDriver`经 `Driver.acquireControl(binding,jobId,generation)`获取独占身体；start收到受控body grant，动作只经grant开放的方法提交。不存在TaskController.acquire、session:walkTo、session:queueAction或session:finish这些接口，不为示例新增它们。

## 4. 创建、正常释放与异常留责

- 创建：PublicWork目录claim后，Provider进入领域Job/Session准入；资源权威在LaborStore及领域记录，TaskDirectory只是可重建offer目录。
- 正常释放：以领域证据结清。`HaulingProvider.reconcile`只有确认对应Work记录DONE后才提交目录释放证明；`TaskDirectory.release(key,jobId,proof)`要求effects=KNOWN且obligationsCleared=true。
- 异常：TaskRuntime stopAdapter请求停止、观察身体与效果、持久事实；TaskController.stopOnce确认后释放身体。身体释放和原件结清分开。UNKNOWN、记录缺失、死亡或会话消失不能伪造目录释放证明。

按实际业务核对PREPARE/WORK/COLLECT/DELIVER/SETTLED责任，清洁/浇水不强行运行无意义的产物收集。工具按实际ToolCustody/ToolReturnService契约归还；不凭“任务取消”认定已归还。

## 5. 注册与最少必要验证

不向PublicWorkProviders这个通用注册表塞具体工种逻辑。新增工种要改的接线：

| 位置 | 改什么 |
|---|---|
| `client/EmberRoutesProbe/Work/LaborManifest.lua` `categories` | 加一条category/providerType/provider；插入位置决定categories()顺序和pendingScore平局 |
| 同文件 `jobKinds` | 只在新增TaskJobs种类时加：kind、recovery，可选monitor；插入位置决定读档恢复顺序 |
| `shared/EmberRoutesProbe/Kernel/BuiltinJobContracts.lua` | 新种类的JobContracts条目（shared，记录模块须延迟加载） |
| 领域 `*PolicyDef.lua` 与 `client/EmberRoutesProbe.lua` | 有工作策略页时新增定义并在入口require |
| `tests/lua/labor-wiring-order-test.lua` | 更新expected快照；改动已有顺序属于契约变化，须单独说明 |
| 翻译 | CN/EN同步Public_<category>及Personnel_<category>键 |

运行 `python tools/check-architecture.py`、`python tools/check-i18n.py`；用 `tests/java/KahluaLaborTest.java` 指定本领域与调度接缝测试。`node tools/audit-npc-control.mjs --changed`只列调用点，需要人工核对控制权，不是自动正确性证明。受影响的原版动作要按pz-modding核对当前安装源码/JAR。构建/实机按变更风险执行，未运行明确登记。
