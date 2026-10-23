# Execution Session Foundation Implementation Plan

> **For agentic workers:** Implement task-by-task in this session, independently. User/project instructions prohibit subagents or delegated review for this work; do not dispatch them.

> 日期：2026-10-22｜状态：本基础切片已实施并验证；运行入口适配仍后续｜范围：P1 会话协议基础，不是全部 P1 接入。

**Goal:** 提供能在真实 Kahlua 使用的每 NPC 独占会话内核，供后续控制器、动作适配和保存编排共用。

**Architecture:** 纯 Lua 模块 `ExecutionSessions` 管理运行期授权、停止交接、受保护调用和保存停派屏障。它不管理资产、不调用原生动作、不自动恢复任务；旧流程本轮不接入，明确不能宣称实际 NPC 已受新协议保护。

**Tech Stack:** PZ 42.21.0 安装版 Kahlua、既有 Java 宿主、PowerShell；没有新增依赖。

**Spec:** [已确认设计 v1](../specs/2026-10-22-npc-behavior-architecture-design.md)，主要落实第2/3.3/4/5.1节的纯协议部分。

## Global Constraints

- 单人、多 NPC，稳定 npcId/jobId；不建立第二套库存账本，不改变原件声明。
- 原件托管独立于身体授权；停止确认不等于效果已知，UNKNOWN 允许身体交接但要求调用方保留核对义务。
- 旧调用失效后不能再派动作；正在执行的同步调用返回前不能释放会话或授予下一任务。
- 保存门禁只在所有会话完成停止确认后允许重新打开；它本身不是世界保存或崩溃事务。
- 未知原生状态不能由内核推断；本轮不宣称原生停稳、持久化、行为树或生活行为完成。
- 保留工作区配方链、UI、翻译及测试修改；独立新增文件，版本按0.22.1构建一致，不改产品界面。

## Review Focus

- 两 NPC 同时工作，停止一个不影响另一个；同 NPC 第二个任务必须被拒绝。
- 同步回调中请求停止、确认停止或抢权；返回前必须保留旧拥有者。
- 回调已发生效果后抛错；会话转停止中，不得被当作无效果或自动释放。
- 伪造/旧会话、修改快照、旧屏障票据、跨世界内核票据不能修改当前拥有者。
- 未知效果与资源托管独立；保存屏障及世界退役不能隐式释放 LaborClaims。

## Task 1: 可执行的会话协议与定向回归

**Files:**
- Create: `Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/ExecutionSessions.lua`
- Create: `tests/lua/execution-sessions-test.lua`
- Create: `tools/test-execution-sessions.ps1`
- Reuse without edits: `tests/java/KahluaLaborTest.java`

**Interfaces:**
- `ExecutionSessions.new()` 返回独立世界的内核；内部状态闭包私有，票据为空表且按对象身份核对。
- `acquire(npcId,jobId,kind) -> token|nil, reason`：同 NPC 独占，生成递增运行期代次。
- `canAct(token) -> boolean, reason`：只对 ACTIVE、未退役、无屏障且没有受保护调用的当前票据授权。
- `dispatch(token, callback) -> boolean, valueOrReason, detail`：callback 无参数、最多保留两个业务返回值；pcall 边界明确报告错误。调用期间禁止重入派发和释放；异常转 STOPPING，不自动认定或回滚效果。
- `requestStop(token,reason) -> boolean, reason`：立即禁止新动作，重复请求不覆盖首次原因。
- `complete(token,evidence)` 与 `confirmStopped(token,evidence) -> receipt|nil, reason`：分别用于 ACTIVE 正常完成和 STOPPING 停止确认。证据必须包含 `bodyStopped=true` 及 `effects='KNOWN'|'UNKNOWN'`；调用方负责真实核验和持久义务，内核不验引擎状态。
- `inspect(npcId) -> copy|nil`：无票据和原生句柄的诊断副本。
- `beginDrain(reason) -> ticket|nil, reason`：冻结派单，并把当前会话标为 STOPPING；`drainStatus(ticket)` 返回剩余数；`endDrain(ticket)` 仅在剩余为0时重新开放。
- `retire()`：永久停止新派发，保留旧记录供同步调用退出及最后效果/停止确认；新世界重新 new，不重用旧内核。

- [x] 编写回归并运行，确认模块缺失时失败；测试以上五类真实协议风险，不以界面或引擎替身证明实机行为。
- [x] 实现接口，定向安装Kahlua宿主48项通过；测试不提供 next，不依赖游戏事件或原生身体。
- [x] 自查失败路径和不变量，确认派发异常、重入停止、UNKNOWN与声明独立、退役后退出都符合契约。

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tools/test-execution-sessions.ps1`

Expected: installed Kahlua suite PASS；明确无原生角色运行。

## Task 2: 验证、版本与准确续接

**Files:** `version.txt`、构建生成的 `Build.lua/mod.info`、本计划、HANDOFF/BACKLOG、独立阶段证据。

- [x] 版本升至0.22.1，运行preflight并保留原始输出；仅类型层写权限失败，获准单独补跑通过；文档链接检查通过。
- [x] 执行现有构建，记录其实际执行的既有检查；未额外重复历史全套。release-check 0错误，包内新增模块和版本SHA-256一致。
- [x] [证据](../../reviews/2026-10-22/probe-0.22.1-execution-sessions.md)记录接口、定向结果和未接入边界；BACKLOG下一步固定为P1入口适配，未记为已保护游戏角色。

## 本切片未覆盖的设计部分

原生动作停止识别、全调用入口强制授权、Work/Companion/Production 接入、真实保存屏障、多任务持久结构迁移、HFSM/效用/BT、吃喝休息均为后续工作。本内核只是这些功能的共同协议基础。不得绕过此边界直接解除现有 retains 或库存互斥校验。
