# 0.2.0 单机动作白名单实机验收

> 日期：2026-10-19｜状态：用户反馈动作正常，日志十项通过

本次 console.txt 的 BOOT/READY 确认为 0.2.0、B42.21.0、ZombieBuddy 2.3.4、client=false/server=false。用户反馈“测试完毕，日志已经打印，动作没有问题”。原始相关日志保存为 `probe-0.2.0-runtime.txt`，哈希与分项结果见 `probe-0.2.0-runtime.json`。

十项均 PASSED，最终 `BATCH PASSED cases=10`，REPORT 同样为 PASSED/10。搬运前后 cargoID=1546516700、copies=1、condition=1；吃饭消耗 0.075，喝水消耗 0.25；中断吃饭保留 0.0263323 的消耗，中断喝水保留 0.0656341；静默观察通过。用户对动画/动作表现反馈正常。

验收范围为当前 SP 探针的吃、喝、自身容器原实例转移及对应中断；不外推到世界仓库、专服、全部 TimedAction 或故障恢复。

退出时保存触发 REMOVAL_PENDING，随后 GameThread exited，未见 REMOVED，不能认定保存前已完整退场。仍须在保存/退出前显式移除并等待 REMOVED；此问题留在生命周期关口。
