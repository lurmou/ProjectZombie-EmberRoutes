# P1任务3：运行服务与随从接线（0.22.8）

状态：运行服务、获授身体接口及随从命令/推进/恢复调用链已实现并通过定向宿主检查；**迁移总开关关闭，游戏仍走原路径，P1任务3未完成**。不把接线存在当作运行迁移已启用。

依据：[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)、[P1计划](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)、[现有停止适配](p1-business-stop-adapters.md)。本轮没有改变架构或增加公共任务选择器。

在线需求本轮无法重新读取：网页工具拒绝导出URL，本地HTTPS请求也发生SSL连接失败。沿已批准架构及实施范围续做，不宣称同步了新的在线改动。

## 已实现

- `TaskRuntime.new()`复用一个TaskController和集中LaborSchedule：每NPC至多一个当前执行及一个后继申请，全世界最多256个NPC槽位；控制器与运行服务每tick分别最多推进4项。无逐NPC线程/定时器。
- `submit(spec)`只记录申请；候选在提交、排队处理及获授前复验。无效或非抢占候选不打断当前任务；有效切换先禁止旧派发，等待联合停止及效果记录，关闭后在后续推进轮次申请新授权。
- `spec`提供稳定npcId/jobId/kind/binding和validate/start/tick/finished/stopAdapter/persistFailure。身体控制、业务资产、候选选择仍分别负责；不是一个全局FIFO公共工单池。
- 控制器提供绑定**确切ticket**的body接口：`current/move/stop/add/clear/snapshot`。业务不取得Java许可密钥；动作入队/清理检查目标角色及原生许可，STOPPING清理仍防同步重入，旧闭包不能借用继任者权限。
- 启动调用异常可能已有物理效果，禁止自动重放；联合Lua队列和原生停止观测后，必须由业务记录UNKNOWN才能释放。没有取得身体许可、没有启动业务的拒绝不冒充未知物品效果。
- Companion命令、逐tick策略、停止和restoreState已接同一运行服务；恢复输入复制标量，固定NPC身份，保留已有Job ID，切换选中角色不改变排队目标。受控worker不再被旧随从schedule重复推进。
- 随从停止意图写入原有世界ModData根下的`companionIntents`（format=1、byNpc），只含jobId/模式/驻点/效果标记/错误，不保存userdata/闭包/许可，也不建立第二份资产账本。写入此表不表示磁盘已成功保存；任务4尚须将它接入真实读档和保存编排。
- Boot增加统一tick及begin/reset接点。reset禁止清理期间重建服务；重复begin不重置当前代次源；ModData世界替换只退役旧Lua控制器，不调用可能已属于新世界的Java全局退役入口。

## 启用边界与准确下一步

`Boot.controlledExecution=false`是内部迁移门闩，没有新增玩家开关。只启用随从后，同一NPC会进入Java managed状态，现有制作/搬运/诊断和保存的旧命令将被拒绝，因此本轮不启用。

1. 下一轮继续任务3：Production/Work及旧CraftProbe的启动申请、上下文body、动作入队/清队列和业务完成/暂停收口。复用TaskRuntime，不能另建一套执行调度；普通完成须正确记录效果并关闭身体会话。
2. 将Production.tickPending/CraftProbe.tickPending、Actions/Haul/NpcCommands及Persistence样本写入口纳入申请或显式拒绝旁路；保留旧原件认领和持货门禁。本轮未转换这些入口。
3. 任务4统一OnSave停派与恢复：本轮运行服务提供beginSave/finishSave，但Persistence/StockService尚未调用它。不能在OnSave等待未来tick，也不能把OnPostSave或检查点内存写入单独当磁盘成功。
4. 世界退役当前保证禁止旧派发，不能据此宣称未完成业务已持久化；保存/退出时的同步事实捕获仍在任务4。完成这些迁移后再开启总门闩并集中实机验收。

## 实际检查与限制

- 安装Kahlua：运行/队列35项、受控随从调用链20项通过；覆盖同步清理重入、未知效果未记录不交接、两NPC隔离、迟到清理、候选提交/获授复验、失败启动不重放、唯一恢复身份、同世界重复begin及跨世界Java退役隔离。
- 原控制器28项、Driver桥接、随从36项、多NPC48项及其相关动作/搬运依赖通过；原始输出：`build/logs/p1-task-runtime-tests.txt`。这些是引擎替身，不是实机证据。
- 最终preflight通过：Lua静态与结构检查0错误，LuaLS为0错误/72条信息提示（与前一轮数量及类别一致）。0.22.8构建及其Java/检查点/载体/边界检查通过；release-check为0错误/54条既有提示；zip内8个相关Lua模块与最终工作区逐字节一致，Build.lua/mod.info版本均为0.22.8；6个相关Markdown链接检查0错误。原始输出见`build/logs/p1-task-runtime-*`与现有构建日志。当前安装基线和限制沿用[Java授权证据](p1-body-authority.md)。
- 新运行路径的原生动作、正常保存/读档、退出恢复、性能和游戏内双NPC交接均**未验证**。生产/搬运/Debug的实际受控接线及统一保存尚未完成，不宣称已防住游戏内所有双重控制。
