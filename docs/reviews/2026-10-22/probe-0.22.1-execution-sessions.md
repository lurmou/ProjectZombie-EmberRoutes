# 0.22.1：NPC 执行会话协议基础

> 日期：2026-10-22｜状态：纯协议内核已实现；既有运行入口尚未接入｜实机与性能：未验证。

## 范围

按[已确认架构设计 v1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)开始 P1 基础切片，见[实施计划](../../superpowers/plans/2026-10-22-execution-session-foundation.md)。新增 shared ExecutionSessions 纯 Lua 模块及定向回归入口，保留现有 Work/Companion/Production 和资产声明实现。

**本轮没有让实际 NPC 切换到新控制器。** 新模块尚无生产消费者，不能把协议测试记为游戏内双重控制已解决，也不能宣称保存、吃喝或行为树已接入。它提供后续统一控制器可直接调用的共同协议。

## 接口与实际行为

| 接口 | 行为 |
|---|---|
| new | 创建世界独立内核，私有闭包状态；票据按对象身份核对，不持久化 |
| acquire/canAct | 每 NPC 独占，多个 NPC 独立；停止中、受保护调用中、停派屏障及退役世界拒绝新授权 |
| dispatch | 同步回调期间拒绝重入派发和交接；抛错转 STOPPING、返回明确错误，不自动释放或重放效果 |
| requestStop | 禁止新指令，不宣称身体已停止；重复请求保留首次原因 |
| complete/confirmStopped | 区分正常完成和停止确认；同步调用仍在栈上时拒绝。调用方必须给出 bodyStopped=true、effects=KNOWN或UNKNOWN，获得含任务身份的回执 |
| inspect | 诊断副本，无原生句柄或授权票据 |
| beginDrain/drainStatus/endDrain | 保存停派、等待所有会话确认结束后重开；旧屏障不能打开新屏障 |
| retire | 永久拒绝新授权，允许旧同步调用退出及最后停止证据；新世界重新 new |

本内核不操作 LaborClaims，不释放/重造物品。UNKNOWN表示业务核对责任仍存在；适配层必须在释放会话前保存义务。身体和效果证据由原版适配核验，不能为通过门禁直接假定true。没有事件注册、每帧循环、原生调用、第二套库存账本或新增UI/翻译。

## 验证证据

- 模块尚不存在时先运行定向回归，确认失败；实现后安装版Kahlua/stdlib运行48项通过，next全局关闭。再次以0.22.1前缀确认通过。
- 覆盖双NPC隔离、冲突派单、诊断副本、伪造/跨内核/过期票据、同步调用重入、部分效果后抛错、未知效果、两次保存屏障、退役时调用退出、资产声明不被隐式释放。
- modscan：整文件冲突0处，不等于运行期兼容验收。
- PowerShell 7构建成功，游戏/ZombieBuddy哈希与[调研基线](npc-behavior-baseline.json)一致。构建内置逻辑、检查点、WorkerRoster、原版基线/覆盖类来源、Kahlua表迁移和配方元数据检查通过；原生角色、世界保存和实际效果没运行。
- 首次误用Windows PowerShell 5.1运行现有构建，因为不支持ConvertFrom-Json的AsHashtable参数中止；改用PowerShell 7完成，没有改写构建工具。
- preflight的Lua lint、结构/候选规则和新鲜度通过；无client/EOL目录，健康检查按规则跳过。首次preflight因类型层共享临时文件写权限失败退出1，原始日志保留；获准后只重跑失败的luals层，退出0、0错误/4条信息性提示。未把首次preflight记成全绿，也未重复无关历史回归。
- 文档链接检查6份：0错误/0提示；相关已有文件git diff --check通过。
- release-check：0错误、11条已有UI硬编码中文提示；本轮没有修改那些并行UI文件。

本地原始日志：build/logs中的execution-sessions-kahlua.txt、execution-sessions-preflight.txt、execution-sessions-luals.txt及execution-sessions-release-check.txt；构建记录为build/probe-build.json。它们不是游戏验收日志。

## 下一步与禁止误用

P1后续先建立运行控制器适配：列全Driver、Java命令、动作队列、旧Actions/Haul诊断、自动续工及Persistence入口，每世界一个内核，每执行任务申请票据。同步调用经dispatch进入，但**dispatch返回不等于其启动的异步TimedAction已结束**，动作运行期间仍保留会话。

先定义并验证原生停稳与效果证据，再连接旧pause/cancel与confirmStopped。旧回调按动作尝试身份归账；本模块不替代后续效果记录。保存必须逐会话停稳核对后采集检查点，不能beginDrain后立即假定可安全保存。

完整入口接入、多任务迁移和资产验收前，不删除retains或原件互斥门禁。P1其余内容、P2生活闭环、P3人员管理、P4烹饪及P5协作尚未完成。

版本0.22.1，包位于build/packages/EmberRoutesProbe-0.22.1.zip，会话模块、Build.lua与mod.info逐项SHA-256匹配本地文件。包包含构建时整个工作区既有配方链/UI内容，不意味着这些并行修改获本轮验收。本轮纯协议基础无需新增游戏操作测试。

本轮只编辑新内核/测试/运行脚本、版本源与构建生成信息、计划及进度文档；没有改写已有运行流程、UI、翻译或测试宿主，没有派子代理或委托评审。
