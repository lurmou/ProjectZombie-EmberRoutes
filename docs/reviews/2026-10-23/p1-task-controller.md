# P1任务1：运行控制器与停止证据协议

2026-10-23，版本0.22.5。仅实现可供接线的控制器模块，未接管游戏NPC；P1整体未完成。

新增client/EmberRoutesProbe/TaskController.lua、TaskStopEvidence.lua，复用shared/EmberRoutesProbe/ExecutionSessions.lua。模块没有事件注册、世界读取、原生动作调用或资源释放。调用方每世界创建一个new()实例并统一持有，未来任务2～4接Driver/Java、各业务及保存入口；现在无运行消费者。

## 接口

- request(npcId,jobId,kind,adapter)：返回不透明ticket；只入队，同NPC已有请求即拒绝。requestStop/observeStop/persistEffects均为adapter闭包，不传self。每实例最多保留256个排队/活动记录，满时明确CONTROLLER_LIMIT。
- step()：每次最多推进4条记录，轮转公平；排队请求在step才获得Session，不能在旧回调栈中启动新业务。终结记录从内部索引及轮转列表回收；ticket只保留最终展示摘要，不保留adapter和原生对象。
- dispatch(ticket,callback)：只有ACTIVE且世界未退役、保存未冻结、无重入调用才进入Session派发；异常转STOPPING，不能假定没有效果。
- requestStop(ticket,reason)：立即禁止后续派发，排队请求直接取消；实际停止在step中由adapter执行。stop回调返回false或抛错均不认定成功；当前实现按有界step再次尝试，尚无原生超时强制处置，留任务2/3逐动作适配。
- observeStop()：adapter提交bodyStopped=true及effects=KNOWN或UNKNOWN；这些是业务断言，不是本模块证明。persistEffects(detachedFact)必须幂等记录事实/UNKNOWN义务并明确返回true，才允许关闭身体会话。错误/拒绝均保持STOPPING；不能用队列空或超时直接制造bodyStopped证据。
- beginSave()：同步冻结并请求停止，取消未授权请求；不step、不等待、不假定OnSave还有后续tick。finishSave(true)须在世界仍活跃且业务验证通过后由保存编排调用，只有全部Session已关闭才开闸；false保留阻塞。该布尔参数不是引擎落盘证明，不可直接绑定OnPostSave。
- retire()：永久拒绝新派发；允许后续step收集旧停止/效果，但不得向新世界复用实例。inspect返回状态副本，仅供诊断，不授予权限。

## 定向验证

先在新模块不存在时运行task-controller-test.lua，require失败；实现后安装Kahlua定向28项通过。覆盖：同NPC互斥、双NPC隔离、同步停止/step/派发重入、UNKNOWN持久前后、迟到ticket、保存冻结/失败/待停止、排队取消、停止返回false及异常、效果调用异常、退役、记录上限与回收。既有execution-sessions-test.lua 48项通过。测试不提供next，不运行游戏身体。

命令：java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java task-controller-test.lua execution-sessions-test.lua。

preflight原始输出：build/logs/p1-controller-preflight.txt；发布检查：build/logs/p1-controller-release.txt。preflight全部通过（0错误，LuaLS 71条信息性警告，其中undefined-field 67条；未逐条归因，不称零警告）。release-check 0错误/54条提示。沙箱内编译资源关闭失败两次，同一脚本获准在沙箱外构建成功；包内两个模块哈希与源码一致。真实Java授权、停止快照、游戏动作/保存、实机与性能均未验证。不得因模块存在就宣称已阻止当前制作/跟随抢身体。

## 下一步

按[P1计划任务2](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)核查并接Java许可与停止快照，再按任务3接实际业务。保持原单、Claims和保存门禁，不提前启用公共派工或放宽多挂起任务存档。
