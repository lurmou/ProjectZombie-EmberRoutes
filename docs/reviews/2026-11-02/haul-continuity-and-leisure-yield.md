# 搬运连续动作与闲暇让位修复

日期：2026-11-02。基于 phase-3a-consolidation@eb65db6 加本会话0.29.21未提交修改；修复候选0.29.22。用户授权修复，并允许收益大于代价的适度重构；只运行必要检查，实机由用户验收。

## 问题与取舍

1. HaulAgent 每件结束后回到100ms tick，重新扫描并新建动作，原版内部队列一直只有一件，表现为反复结束动画。
2. Work.busy 包含所有 Runtime 会话；PublicWork.eligible 即使已识别可探测闲暇，仍被该 busy 条件提前排除，因此到不了已有 LeisureService.workReady。

保留逐件外层调度改动最小，却无法解决动作间隙。预先把全批动作加入原版队列会被 checkQueueList 合并/擦除后续动作，破坏逐件回执。另建批次持久格式与整批效果核对会扩大恢复语义，当前不采用。

选择同停靠点单件确认后接续：利用当前安装版 ISInventoryTransferAction.perform 在 transferItem 返回后检查 queueList 的实际顺序。每件物理效果核对且回执成功后，才持久登记下一件意图、把下一条原版队列记录接入同一个动作。没有复制原版 perform/transferItem 实现，没有第二个执行器、批次账本或存档格式。

收益：连续动画、复用当前已完成的有界扫描、消除每件结束后重新扫描/外层等待。代价：WorkTransfer 实例适配需区分本件效果和整段动作结束，并跟踪每件进度超时；对安装原版 perform 顺序产生明确依赖，升级游戏须复核。当前不合并轻物品为一次多原件效果，以维持一个未决意图和现行逐原件清偿语义；不宣称与玩家所有轻物品批量计时完全相同。

## 实施边界与闭环

- 创建认领仍为 HaulJobs.claim → LaborStore/Claims；snapshotStep 在单一现有 Job/Session 内调用 prepareTransfer，登记同一 activeAttempt 格式。
- HaulAgent 从已扫描的 manifest 原件中保存同停靠点候选引用；引用不授权转移。续件前复验原件位置、端点、容量、负重、producer规则和配送玩家停稳/取消状态。换箱/移动/容量不足则结束本段，交回既有 nextStep/DeliveryFlow。
- WorkTransfer 在实例 transferItem 原版效果返回后核对实际原件，再调用现有逐件 transferred/knownTransfer；提交失败不接下一件。每件通知库存变化，不以动画结束冒充整批到账。
- 只拥有本实例内部 queueList，canMergeAction 拒绝吞入外部动作，避免原版 table.wipe 擦除其他任务的回执。native perform 的物品效果、时间重置、循环动画和最终结束仍由安装原版处理。
- 停止/取消/保存继续走现有 TaskBusinessStop 与 knownTransfer；最多只有下一件未决意图，原件不明保留责任。最终 poll 不能将部分停止判为全批成功。
- 超时沿每件实际完成时间更新，单件60秒守卫不累计误杀长批次。
- PublicWork 允许已确认可探测闲暇绕过 Runtime 占用的 busy 提前排除；有实际候选才请求现有 workReady。仍等待身体停止/起身、责任结清和下一次派工，不强行移走正在健身的身体，不放宽吃喝/睡眠门禁。

## 必要检查

- public-work-test：78项通过。适配原闲暇用例，显式提供 busy=true 的真实会话占用，停止释放后才能认领，不是放宽生产守卫的测试。
- haul-routing-test 30项、delivery-service-test 46项通过；原生实体/动作替身不覆盖新增连续分支。
- work-transfer-continuity-test：8项通过，直接加载当前安装 ISInventoryTransferAction.lua 的 perform/checkQueueList，库存/动作底层为替身。验证同一动作续件、逐件到账后回执、最后结束一次、续件前失效保留源原件与部分停止结果。此检查用于新增适配的必要边界，不扩展整套模拟场景。
- 首次误传 delivery-test.lua（不存在）导致命令失败；已改为真实 delivery-service-test.lua并通过，不记首次为通过。
- 构建、347份Lua普通/Debug编译与CN/EN键集通过；0.29.22候选包363文件逐项哈希与工作区一致；3份文档引用零错误，git diff --check无错误。不重跑完整回归、LuaLS或preflight。

## 未验证

真实游戏连续动画、健身起身延迟、配送玩家移动/箱满/取消与保存重进由用户实机确认。未测量帧耗时，不宣称实机性能提升。未提交、未推送、未上传工坊。
