# Java资源与记录提交内核计划

日期：2026-11-02；状态：本阶段已实现并按成本试验缩小启用范围；基线0.29.25工作树，交付0.29.26。

用户批准先评估资源协调与Job提交，再评估Runtime/Controller；不改变现有领域契约、身体控制、持久格式与恢复责任。

1. 已试验：Claims操作逐项桥接、通用JobUpdateKernel、完整LaborCommitKernel。均操作同一Kahlua owners/capacity/token/byId，没有第二权威。
2. 成本否决：逐项Claims桥接与通用JobUpdateKernel撤回，普通制作提交继续Lua；删除未启用的Java更新内核，不把试验代码留进包。
3. 最终启用：已持有至少4个资源的Job、且mutation包含capacity命令时，单入口LaborCommitKernel负责集合校验、容量预检/变更、调用原store.update、失败回滚、成功缩减与终态清理。内部ClaimsKernel直接操作现有声明表，不逐件跨桥。门槛只选择等价后端，不改变接受范围。
4. 保留Lua：创建、加载、隔离解释、领域校验、JobStore通用CAS/通知/索引，以及小型/无容量提交。能力缺失走既有实现；Java出错不静默重试。
5. 必要验证：制作与搬运真实接线的定向Kahlua回归，容量不足、CAS失败、提交后所有权变化、终态与嵌套通知；宿主成本对比。补齐测试宿主所需userdata后运行原恢复/证据检查，不放宽生产守卫。

实机帧耗时、游戏Exposer回调、真实磁盘恢复未验证；下一阶段Runtime/Controller尚未实施。详细数据与闭环位置见[证据](../../reviews/2026-11-02/java-labor-commit-kernel.md)。
