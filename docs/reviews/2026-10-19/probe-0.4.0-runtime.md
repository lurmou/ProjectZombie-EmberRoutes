# 0.4.0 单人随从实机反馈

> 日期：2026-10-19｜状态：用户报告整套测试通过；核心指令有日志佐证

用户反馈：“所有测试通过，日志已经打印”。按此登记0.4.0集中测试的用户验收结果；原始筛选日志为 `probe-0.4.0-runtime.txt`，分项与哈希为 `probe-0.4.0-runtime.json`。

本次 BOOT/READY 为0.4.0、B42.21.0、ZombieBuddy 2.3.4，client=false/server=false。日志直接包含 FOLLOW、HOLD、HOME_SET、RETURNING、HOME_REACHED，最终 REPORT 为 HOLD / HOME_REACHED、motion=REACHED、failures=0，NPC稳定ID为 `1fd815c0-de45-4787-9931-4f1f1c29aecb`。

工作交接、跨层、失败预算和暂停相关项目按用户“所有测试通过”的反馈登记；本次日志没有这些情境逐项成功的独立标记，也未包含 REMOVED / REMOVAL_PENDING，故不能补写并未观察到的事件。完整角色/库存持久化仍未实现，不能由本轮通过推出保存恢复已经完成。

本次 console.txt 检查时约205KiB，游戏仍在写入。只保存带当前版本前缀的快照并计算快照哈希，原文件未清空、删除或截断；不将活动文件当作不可变证据。排查默认用版本/关键词筛选及有界输出，出错时再读取完整堆栈和前后事件。
