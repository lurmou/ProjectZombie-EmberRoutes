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
| claim | `provider.claim(selected,npcId,jobId,env)`；目录在PublicWork中先claim；env提供actor/entry/now/directory/releaseOffer。返回QUEUED或STARTED表示接手，其他返回由派发方处理拒绝 |
| advance | `provider.advance({actor=actor,now=now,directory=directory})`；适用于有后台推进的领域，不是每个身体Session的帧回调 |
| reconcile | `provider.reconcile()`；领域按真实业务记录核对责任，不是统一的reconcile(jobId,outcome) |
| hasWork | 当前为无参数的领域查询；具体用途以调用方为准，不等于“可给此NPC派工” |

`PublicWorkProviders.register(def)`检查category与defaultPriority，保存定义；没有强制五个回调全部存在。按真实业务实现需要的钩子，其他可选钩子从注册表与调用方读取，不发明通用参数或返回值。

## 3. 身体执行

领域通过 `Runtime/TaskRuntime.current():submit(spec)` 提交候选。先读TaskRuntime中START_SPEC_REQUIRED校验及一个完整生产调用方，如 `Settlement/MembershipReturn.lua`；spec必须提供npcId/jobId/kind/binding/validate/start/tick/finished/stopAdapter/persistFailure等当前必需项。

TaskController由运行时创建。`TaskController.new():request(...)`排队，`attachDriver`经 `Driver.acquireControl(binding,jobId,generation)`获取独占身体；start收到受控body grant，动作只经grant开放的方法提交。不存在TaskController.acquire、session:walkTo、session:queueAction或session:finish这些接口，不为示例新增它们。

## 4. 创建、正常释放与异常留责

- 创建：PublicWork目录claim后，Provider进入领域Job/Session准入；资源权威在LaborStore及领域记录，TaskDirectory只是可重建offer目录。
- 正常释放：以领域证据结清。`HaulingProvider.reconcile`只有确认对应Work记录DONE后才提交目录释放证明；`TaskDirectory.release(key,jobId,proof)`要求effects=KNOWN且obligationsCleared=true。
- 异常：TaskRuntime stopAdapter请求停止、观察身体与效果、持久事实；TaskController.stopOnce确认后释放身体。身体释放和原件结清分开。UNKNOWN、记录缺失、死亡或会话消失不能伪造目录释放证明。

按实际业务核对PREPARE/WORK/COLLECT/DELIVER/SETTLED责任，清洁/浇水不强行运行无意义的产物收集。工具按实际ToolCustody/ToolReturnService契约归还；不凭“任务取消”认定已归还。

## 5. 注册与最少必要验证

领域Provider由PublicWork的组合入口注册；不向PublicWorkProviders这个通用注册表塞具体工种逻辑。CN/EN同步Public_<category>及Personnel_<category>键。

运行 `python tools/check-architecture.py`、`python tools/check-i18n.py`；用 `tests/java/KahluaLaborTest.java` 指定本领域与调度接缝测试。`node tools/audit-npc-control.mjs --changed`只列调用点，需要人工核对控制权，不是自动正确性证明。受影响的原版动作要按pz-modding核对当前安装源码/JAR。构建/实机按变更风险执行，未运行明确登记。
