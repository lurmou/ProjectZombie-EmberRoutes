# 0.3.0 实体容器搬运单机实机验收

> 日期：2026-10-19｜状态：用户反馈正常；17 步主流程日志通过

用户反馈：“测试成功，日志已经打印，没有什么问题”。本次 BOOT/READY 为 0.3.0，游戏 42.21.0、ZombieBuddy 2.3.4，client=false/server=false。相关原始日志见 `probe-0.3.0-runtime.txt`，分项和哈希见 `probe-0.3.0-runtime.json`。构建时的 runtimeTestsRun=false 保留历史含义，本文件记录后续实机结果。

## 已观察到的结果

- 全部 17 步 PASSED，最终 BATCH PASSED cases=17、REPORT state=PASSED cases=17。
- 铅笔 ID=1577720200、螺丝刀 ID=978995276、勺子 ID=737495034；12 次转移核对均 copies=1，耐久分别为 1、9、2。
- 接近目标箱及返程均有 MOVE_REACHED，并通过可触及检查；到达源箱的部分步骤因已在附近直接通过。
- 最终 ITEM_LOCATION 三件均 root=false/source=true/destination=false；静默观察确认三件原物品返回、队列为空，随后有 FIXTURES_CLEANED。

这证明当前测试场景中的 SP 原版世界容器转移、路径与动作衔接、实例保留和往返闭环可用。用户同时反馈表现正常。

## 不扩张的边界

本次提取日志未见容量不足、撤销标签、容器拆除、未知容器清理阻塞等异常场景的独立结果，不能把它们从替身回归自动升级为实机通过。也未证明多楼层搬运、性能规模、断电恢复、专服或双客户端同步。

日志末尾为 REMOVAL_PENDING，未见 REMOVED；末尾记录的帧号停在 30008。暂停/退出期间的退场进度仍待核查，不能把“已隐藏”认作已删除。继续要求保存/退出前等待 REMOVED / carrier=absent。

下一关口转向专服独立模拟与双客户端代理同步；不继续把单机功能叠加当作 MP 可行性证据。
