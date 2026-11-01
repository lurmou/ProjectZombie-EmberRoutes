# Phase 3A 写入前格式门禁实施计划

**Goal:** 不支持的 Work 根表在默认值写入、任务恢复和 Runtime 准入前拒绝；不迁移，不删除现役业务路径。
**Architecture:** JobStore 的打开前校验提取为共享的只读准备函数，open 与 check 使用同一生产契约。ContainerRegistry 在首次接纳根表时检查根/容器/Job 格式，成功才建立默认值；TaskPersistence.load 在所有恢复钩子之前获取已接纳根表；MembershipLifecycle 将引擎新世界根表直接交给同一门禁，避免旧世界缓存。检查结果仅缓存当前根表及 taskJobs 身份，避免每帧扫描。
**Tech Stack:** Lua / 安装版 PZ Kahlua；无 Java 改动。
**Spec:** [主规格 v1.5 §6](../specs/2026-10-31-phase3a-job-contract-standardization-design.md#6-存档支持边界与写入前拒绝-p0-5)

## Global Constraints

- 当前 CRAFT format=3、HAUL format=1/2 仍为现役格式；保持 JobStore 已接受范围。
- 只有空根表可初始化；非空且无根格式、未知根格式、错误 containers 类型及 JobStore 拒绝的数据均不修改原件。
- 不自动迁移/清理历史记录，不扩展 Quarantine，不启动 Stage C，不覆盖并行 UI 修改。
- 检查不证明 PZ 磁盘保存可靠性；实机验收由用户执行。

## Review Focus

拒绝后原根表及嵌套引用不变；新世界正常初始化；支持格式重新打开；原生缓存桥与直接 ModData 路径一致；恢复钩子不能早于校验。

## Tasks

- [x] 增加真实 Registry + JobStore 边界测试，覆盖不支持的根/容器/任务格式、非法 Provider 载荷及新世界/当前格式恢复；先复现写入污染。
- [x] 提取 JobStore 只读 check，Registry 接纳前调用；TaskPersistence 调整恢复顺序。按根/任务表身份缓存，只对接纳边界扫描。
- [x] 验证失败前无默认值写入和恢复钩子；运行 JobStore、格式门禁、Stage B 及保存生命周期相关回归。
- [x] 运行 preflight、doclink；原位更新 BACKLOG，独立提交推送供外部复审，B.5 保持开放。

用户后续明确验证节奏：本轮已启动完整 preflight 继续完成；后续切片只做必要定向检查，正式实机前统一跑一次完整回归。
