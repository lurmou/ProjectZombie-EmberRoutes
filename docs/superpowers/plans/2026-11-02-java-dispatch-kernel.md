# Java公共调度计算实施计划

日期：2026-11-02；状态：已实施必要范围，目录试验已撤回，实机待验收。

用户已批准：Java更适合计算时，底层由Java承担。基线为本会话0.29.24工作树；沿唯一NPC架构，不改变领域注册/身体/资产权威。

1. DispatchDirectory.newState/upsert/claim/withdraw/release 接管候选索引；TaskDirectory API保留。公开offer仍是同一个可观察Kahlua表，不另建持久责任。认领重复返回与已分配不更新、撤回留责、凭KNOWN+obligationsCleared释放保持。
2. DispatchSelection.choose接管候选遍历，优先级/评分/稳定key排序保持；非法/禁用候选不参与。选择结果仍是原候选引用。
3. PlanningInvalidation接管失效版本索引、依赖捕获/比较、512观察项裁剪和跨世界隔离；PlanningWake继续连接现有事件。revision读取不额外初始化世界。
4. ProbeRuntime.workerDecisionWindow批量读取轮转窗口，单次最多16人；PublicWork仍逐人调用领域资格/发现/认领，最多4个可评估人，按实际访问推进cursor。禁止把参考项目TaskRunner迁为第二执行器。
5. 实施前比较：PrecheckQueue当前limit=4且validate/request.step/complete必须Lua回调，搬其循环会增加往返，暂保留；TaskRuntime控制权、Claims与持久格式不变。
6. 必要验证：现有公共派工78项在Java后端与原Lua后端运行；Java无游戏数据边界用例；比较宿主仲裁/目录/失效计算成本，不把它当实机帧性能；编译与构建。不重复完整回归和新增大套场景模拟。

调用闭环：PublicWork.directory.claim分配候选 → provider.claim创建现有Job/Claims；领域效果确认后directory.release；撤回/异常不凭超时释放已分配目录。Java持有的索引随同一目录/观察者的Lua所有者销毁，不建立跨世界静态缓存。

执行状态：目录Java试验因热身补测出现反向成本而否决，实验代码已撤回；步骤2～4已接，步骤5保留回调边界。最终Java内核12项及公共派工78项通过；目录继续用既有Lua实现，详见[证据](../../reviews/2026-11-02/java-dispatch-kernel.md)。
