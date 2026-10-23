# 统一任务迁移：入口与数据边界核查

日期：2026-10-23。工作区基线：包含0.22.4未提交实现；仅静态读取，不是运行/原生停止验证。设计入口为[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)，协议见其从属统一任务细化。以下路径相对Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe。

## 控制入口清单

| 已查源码/入口 | 当前事实 | 迁移要求 |
|---|---|---|
| Driver.lua:stop/move | 直接调用Java stopCarrier/commandFor或command | 加会话身份与当前拥有者验证；Driver不能仅验证NPC存在便授权操作 |
| WorkAgent.lua:取消及接单 | 清TimedAction队列、写queues表；接单调用cancelAll | 通过控制器请求停止/授予，不从其他业务直接清队列 |
| WorkTransfer.lua | 直接入队搬运动作 | 经获授Job/Session操作，保留取放与原件核验 |
| Production.lua:execute/pause/tickPending | 创建/恢复有cancelAll路径，暂停清动作；pending与waiting可直接execute | 创建、恢复、库存唤醒都提交同一控制器，不能只保护UI起单 |
| CraftProbe.lua | 旧格式制作及自己的暂停/恢复/入队路径，包装Production | 旧单保留专用适配，禁止从旧入口绕行；不要误认为Production接通等于旧路径已接通 |
| CompanionAgent.lua | 指令调用cancelAll | 跟随/驻守作为个人候选，保存后恢复仍须仲裁 |
| Actions.lua/Haul.lua | 诊断动作直接clear/add或改queues | Debug不是豁免入口；未适配时拒绝与正式工作并发，不隐式夺权 |
| NpcCommands.lua | 指令调用cancelAll | 按命令目标和停止原因归入控制协议 |
| StockService.lua | 仍按规则npcId查生产记录并有后台派发 | 需求端改公共Order，不另选人；旧周期只作兼容恢复 |

源码定位由rg匹配后读取Driver/Persistence/StockService相关片段核对。直接操作队列是当前事实，不代表每处都是缺陷，也不代表改成一个包装函数即可证明原生动作停稳。

## 保存与Java边界

Persistence.lua:captureOnSave先导出随从意图，经cancelEvery或多个取消入口，再逐NPC调用Java保存检查点；之后调用Companion.restoreState及Probe.afterCraftSave。CraftProbe/Production又有tickPending恢复。这些必须改成统一屏障下的恢复候选，不能在保存回调里分别重新取得身体。

StockService.lua定义beforeSave/afterSave，并注册OnSave调用beforeSave。本轮搜索整个Lua树，只发现afterSave定义，未发现调用点；需核实运行绑定/加载顺序并针对正常保存后后台恢复验证，当前不能记为已闭合。

Java入口位于java/src/main/java/emberroutes/probe/ProbeRuntime.java：stopCarrier、commandFor、saveCheckpointFor、clearForSave。ProbePersistence.java包含stopProbe及库存/装备重建操作；须按原持久化协议核查，不能绕过其声明或用其重建逻辑冒充任务交接。此次只做入口定位，未完成CarrierRuntime等下游所有写身体路径审计；P1实施前需沿这些调用继续核对当前JAR及原生停止后置条件，不能宣称Java边界已安全。

## 记录与资产迁移

| 当前数据/校验 | 新模型 | 必须保留 |
|---|---|---|
| Registry根craftProbes.byNpc | 独立jobId记录+byNpc活动/挂起索引+Order关联 | 原taskId、NPC、produced/delivered、材料/工具/产物ID、链恢复点和未知效果 |
| LaborStore/LaborClaims及nativeTokens | 唯一资源权威接新Job索引 | 先全量验证再发布声明；不能删除互斥校验就声称支持多挂起任务 |
| CraftRecord格式与链goal/nodes | 版本化Job适配/迁移，订单目标与执行分段分离 | 已提交不重做；原件与义务不因Job挂起消失 |
| maintainStock规则和周期 | 规则指向公共补货Order，领取后才关联Job | 旧活动周期/原执行者先收束或明确迁移，不重新发一张补货单 |
| 随从意图、Java检查点 | 个人恢复候选，经统一授权执行 | 稳定npcId、世界身份、动作/身体恢复门禁 |

旧单保留原执行者不违反新版“新生产下单禁止指定人”：这是原件托管兼容，不是长期创建模式。现有物流页面移除之前，未完搬运/归还仍须能在相关任务详情查看和处理。

## 实施前必须补齐的证据

后续源码穿透补充：CarrierRuntime.stopCarrier调用ProbeNpc.stopProbe；CarrierRuntime的move命令调用ProbeNpc.moveTo，后者先调用stopProbe。stopProbe调用StopAllActionQueue、取消movement和寻路、清移动变量。因此移动本身也可能清原生动作队列，不能视为无副作用操作。Production.pause先改业务代次/取消规划，在COMMITTING时标uncertain，再清Lua动作、停Driver并保存恢复候选。以上是当前源码事实，不证明当前安装JAR的原生队列停稳或回调效果已经核验。实施按[P1计划](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)推进。

1. 沿Java命令下游列全移动/停止及队列写入路径，逐动作定义已停稳/部分生效/未知的证据。
2. 建立旧单迁移样本：持材料、已制成未交付、链中间产物、未知提交、保存失败、旧随从恢复。
3. 明确共享记录schema及一次性迁移失败保留路径，不提前删除旧存档或声明。
4. 将所有自动恢复与保存事件纳入统一顺序，验证StockService保存后恢复调用是否缺失。
5. 形成P1逐文件计划后再改运行代码；相关最小回归及实机停止/恢复验证分别记录。

完成本清单不等于P1实现完成。本轮没有运行测试、编译或原生探针，因为只修改文档；文档以doclink验证。下一步是按上述风险完成P1实施计划及必要原生证据，不再另选框架、不启动固定NPC自动派工扩展。
