# 浅层领域目录与 Java 桥收敛实施计划

> 执行方式：用户已授权开始，由当前会话按任务顺序执行，不启用子代理。

**Goal:** 首批搬运执行模块按领域归档，并收回经审计确认不属于 Lua 契约的两个 Java 桥入口。

**Architecture:** client/shared 原加载域内新增 Hauling；共享 Job/Claims/Session、记录格式和物理动作不变。目录移动与 Java 表面收敛分开提交。

**Tech Stack:** PZ B42.21.0 安装版 Kahlua/Java、ZombieBuddy 2.3.4、Git。

**Spec:** [已批准设计](../specs/2026-11-04-domain-layout-design.md)。

## Global Constraints

- 只迁移设计列出的 10 个模块，保持原名与加载域，无根级转发桩。
- 只替换模块路径，不改变 HAUL format、声明、权限、效果或恢复规则。
- Java 正式 94 个入口保留，三个字符串内核入口不能误删。
- 其他会话的 EmberRoutesProbe.lua/NpcMedical.lua 不纳入提交。

## Review Focus

- 字符串 require、loaded 替身键或 dofile 漏改：全仓旧路径扫描及现有定向套件。
- 新旧同模块同时加载：模块唯一性及构建 ZIP 新旧路径核对。
- 目录移动夹带语义变化：所有改动源码仅替换路径的逐文件等价核对。
- 暂停/读档丢原件责任：现有 haul-routing、dec003-haul/recovery、delivery-service 回归。
- 动态 Java 调用误判未使用：94 个公开名称反射白名单检查，保留内核入口。

## Task 1：保全并收口现有展示改动

- [x] 备份当前 27 项修改及哈希，保留其他会话医疗调试文件。
- [x] 五套需求/工单/职业/楼层定向回归与实际构建。
- [x] 单独提交 0.29.37 展示修改为 4ccb093，未宣称高级视觉/多目标搬运完成。

## Task 2：目录迁移

Files：设计列出的 10 个 Lua 及全部真实引用方、相关测试。

- [ ] 先跑迁移前相同搬运/配送/恢复套件并记录结果。
- [ ] 移动文件，精确替换 EmberRoutesProbe/<原名> 路径及直接文件路径，保留字节换行。
- [ ] 核对每份源码除路径外无变化、无旧路径引用、无重复模块与大小写错误。
- [ ] 运行相同套件，记录前后失败集合；单独提交目录迁移。

## Task 3：Java 桥表面

Files：ProbeRuntime.java、tests/java/emberroutes/probe/ProbeBridgeSurfaceTest.java、tools/build-probe.ps1。

- [ ] 增加 metadata 白名单反射测试，先观察两个不应暴露的方法导致失败。
- [ ] log 改包可见，删除无引用 lumberjackSquareHasTree 桥转发。
- [ ] 将反射检查加入既有构建流程，重建 0.29.38 并核对包路径及 94 个正式入口。
- [ ] 一次集中历史回归与 preflight，按风险记录基线失败；文档链接与翻译/版本一致性检查。
- [ ] 更新 BACKLOG/证据，提交并普通推送 phase-3a-consolidation，保留其他会话改动。
