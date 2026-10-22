# Phase 0 Carrier Implementation Plan

> 日期：2026-10-19｜状态：首切片已构建；MP 载体入口未实现，实机未验证
> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 交付可构建的单 NPC 载体探针与可核对的测试说明。
**Architecture:** 独立实现 Java 载体、纯逻辑会话与规则、ZombieBuddy Lua 暴露接口；原版世界调度是唯一物理更新者。SP 先验证载体，MP 在专服模拟入口未成立前明确拒绝创建并报告原因，不生成客户端假权威实体。
**Tech Stack:** JDK 25 工具、当前 PZ/ZombieBuddy JAR（仅编译依赖）、PowerShell、Lua。
**Spec:** [已批准设计](../specs/2026-10-19-phase0-carrier-design.md)。

## Global Constraints

- 当前绑定 PZ 42.21.0 / ZombieBuddy 2.3.4 的已核对哈希，首包 `0.1.0`，每次交付补丁递增。
- 不复制 NPCFW/CommunityTrade 产品实现，不占玩家槽位、不伪造连接、不关闭全服反作弊。
- 测试对象临时存在，不持久化，不声称 MP/恢复已经通过。
- 玩家提示 CN/EN 成对；日志统一版本前缀；无每帧扫描或无界重试。
- 本会话直接实施；不派遣代理。当前用户的启动授权优先于技能的重复评阅流程。

## Review Focus

1. 非有限坐标、过远目标与未加载方格必须拒绝。
2. 重复创建/清理不产生第二个实体，失败构造或清理不能静默丢失所有权。
3. 世界更新不得永久改变玩家实例/摄像机，不接管真实玩家槽位。
4. 离场、死亡或异常对象必须停止活动并允许清理；不能把原地动画记作移动成功。
5. 缺 Java 接入、版本变化或 MP 环境必须给出准确诊断；构建不能混入旧产物。

## Task 1: 可测试的规则与生命周期

**Files:** `java/src/main/java/emberroutes/probe/ProbeRules.java`、`ProbeSession.java`；`java/src/test/java/emberroutes/probe/ProbeLogicTest.java`。
**Interfaces:** 纯 Java `ProbeRules.allowedPoint(...)`、`ProbeRules.canSimulate(boolean, boolean)`；`ProbeSession<T>` 的 `spawn(Supplier<T>)`、`remove(Consumer<T>)`、`get()`，最多持有一个对象。

- [x] 写断言覆盖 NaN/Infinity、距离边界、SP/MP 区分、重复创建、创建失败重试、清理失败保留对象和重复移除。
- [x] 先运行测试确认缺实现失败，再实现上述类并跑过。

## Task 2: 引擎载体、观测与 Lua 命令

**Files:** 同包 `ProbeNpc.java`、`ProbeRuntime.java`、`Main.java`；`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe.lua` 与 CN/EN 翻译。
**Interfaces:** ZombieBuddy 命名类 `EmberRoutesProbeJava`；静态 `command(String, IsoPlayer, double, double, double)` 返回状态字符串；`begin(boolean)`、`tick()`、`reset()`、`clearForSave()` 管理生命周期，`version()` 返回构建版本。

- [x] 查当前引擎构造、原版路径/输入、世界注册/移除和 ZB 暴露契约，记录源码来源。
- [x] 实现 SP 构造、短距 move/stop、inspect/remove；世界调度更新，Lua Tick 仅监测不再调用 update。
- [x] 在构造和更新边界保留/恢复本地玩家与摄像机引用；捕获本探针异常后停止，不吞掉继续运行。
- [x] MP 返回 DRIVER_UNAVAILABLE，不创建角色；不把该拒绝称作联机通过。
- [x] 右键菜单提供生成、移至此处、停止、检查、移除；缺失 Java 接口清晰提示。

## Task 3: 可重建交付与验收记录

**Files:** `version.txt`、`tools/build-probe.ps1`、`packaging/probe-mod.info.in`、`docs/testing/phase0-carrier.md`、本轮验证记录及导航。

- [x] 构建脚本从唯一版本文件生成版本类/模组元数据，校验依赖哈希，编译测试与产品并打包，仅含本项目类。
- [x] 记录环境与产物哈希；不更改游戏配置或自动安装到其他目录。
- [x] 对实际模组根运行 preflight，保留输出，修复可处理的命中项。
- [x] 检查 Java 构建、纯逻辑测试、包内容、翻译与文档；实机统一标为未验证。
- [x] 更新待办/接力；交付安装步骤、测试顺序和已知 MP 阻塞。

执行结果：上述首切片实现、构建、29项纯逻辑断言与完整 preflight 已完成。测试包和记录见 [测试说明](../../testing/phase0-carrier.md) 与 [验证记录](../../reviews/2026-10-19/probe-0.1.0-verification.md)。测试采用真实依赖编译与纯规则/生命周期断言；没有构造模拟引擎来冒充运行时证明。

提交策略：仓库目前无初始提交且原始资料全部未跟踪。本轮不将所有用户资料批量暂存；是否建立初始提交独立处理，不阻塞本地构建交付。
