# NPC 原版位移执行实施计划

**Goal:** 导航保留路径和交互，原版动画流程执行实际位移。

**Architecture:** 按已批准的[从属设计](../specs/2026-11-05-native-npc-movement-design.md)执行。ProbeNpc 同步拦截寻路器位移，原版消费根运动；ProbeMovement 仅提供无引擎依赖的末端长度缩放。

**Tech Stack:** Java 17、安装版 PZ 42.21.0 / ZombieBuddy、现有 PowerShell 构建。

## 约束与关注点

保持唯一身体执行者、当前存档格式及原件责任；无旧链路 fallback。保留其他聊天的工作区改动。重点检查重复移动、路点越过、倒退符号、停止余量及异常时标志/path2 恢复。

## 实施

- [x] ProbeMovement 添加只缩短长度的纯函数；ProbeLogicTest 覆盖直角、倒退、近端、零距离和有限值边界，保留原生命周期测试。
- [x] ProbeNpc 在 path.update 内阻止直接 moveUnmodded，在路径可执行时委托 super.doDeferredMovement；finally 恢复路径和同步标志，停止/闲置仍丢弃残留。
- [x] 构建前递增当前版本；运行 build-probe.ps1、实际产物调用检查和定向文档链接检查。记录实机未验证范围并更新 BACKLOG/INDEX。

用户已明确要求本会话开始实施，直接按授权执行，不另开确认或自动提交。
