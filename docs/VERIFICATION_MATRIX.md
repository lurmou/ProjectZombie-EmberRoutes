# EmberRoutes 验证矩阵（Verification Matrix）

> 状态：草案（Phase 1 / E）— 由 2026-11-11 多智能体审计的 E 项（缺验证矩阵、CI 不跑 Lua 测试）驱动建立。
> 事实源：本地版本指纹 `audit-baseline-fingerprint.json`（HEAD `3fe5f32c…`，生产 Lua 指纹见该文件）。
> 本矩阵是"未来质量门禁"的定义，不是对历史测试的盘点。历史验证记录薄弱（BACKLOG 引用 ~50 次评审，仅 7 份留存），不在此追溯。

## 0. 首要原则

**测试通过 ≠ 游戏机制正确。**

Lua 模拟环境（Kahlua + mock native host）可以验证状态机、契约、资源所有权逻辑；但**不能证明 Build 42 中 NPC 真能开门、爬窗、执行动画、完成 TimedAction**。因此 L5/L6 的实机部分必须保留，自动化只能覆盖"逻辑正确性"，不能覆盖"机制正确性"。

任何一项 L2–L4 的自动化，都必须明确标注它**不验证**什么，避免给人"CI 绿了游戏就对了"的错觉。

## 1. 分层矩阵

| 层 | 验证内容 | 当前自动化 | 工具 / 入口 | 缺口 |
|----|---------|-----------|------------|------|
| **L1 静态检查** | 模块边界、未声明全局、翻译对称（CN/EN 2211+ keys） | ✅ CI（`static-checks` job，GitHub runner 可跑） | `tools/check-architecture.py`、`check-i18n.py`、`check-undeclared-globals.py` | 无（D 已修复：原未跟踪脚本已 `git add`，待提交后干净检出即含） |
| **L2 Lua 单元验证** | JobStore / Claims / 调度 / ExecutionSessions / 物流 | ⚠️ 仅本地、**写死本机游戏路径**、未进 CI | `tests/lua/*.lua` + `tests/java/KahluaLaborTest.java` | **致命缺口**：运行器硬编码 `D:/…/ProjectZomboid/stdlib.lua`（`KahluaLaborTest.java:29`），换机/干净检出即失效。需参数化 stdlib 路径后镜像 `jar-checks` 进 CI |
| **L3 Java 桥验证** | 114 方法公开桥白名单、接口、类型 | ⚠️ 本地 / 自托管 runner（需 `game-root/*.jar`，GitHub runner 跳过） | `tests/java/emberroutes/probe/ProbeBridgeSurfaceTest.java` | 未进 GitHub CI（受专有游戏 jar 限制，符合既有设计） |
| **L4 跨语言集成** | Lua ↔ Java 交互（labor / dispatch / jobData 桥） | ⚠️ 同 L3（本地 / 自托管） | `KahluaLaborTest` 的 `--java-labor` / `--java-dispatch` / `--java-job-data` 分支 | 同上；且依赖 L2 的 stdlib 解耦才能 CI 化 |
| **L5 游戏实机验证** | NPC、TimedAction、家具、寻路、动画 | ❌ 无自动化 | 手动 / 实机 | 必须保留，不可被自动化替代 |
| **L6 生命周期验证** | 保存、读档、退出、世界切换 | ⚠️ 部分有 Lua 用例（`persistence-test.lua`、`exit-save-test.lua`），但本地且未进 CI | `tests/lua/*lifecycle*`、`exit-save-test.lua` | 自动化部分可随 L2 进 CI；"存档后真能读回且状态一致"仍需实机组合 |

## 2. 当前自动化缺口（最关键的一条）

**L2 不是"没接 CI"，而是"根本无法跨机器复现"。**

`tests/java/KahluaLaborTest.java:29`：
```java
run(thread,env,Path.of("D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/stdlib.lua"));
```
该路径是开发者本机游戏安装目录的绝对路径。后果：
- 在 CI（GitHub runner）上：`game-root/` 无 jar、`D:/…` 不存在 → 直接失败。
- 在他人机器 / 干净检出上：除非该绝对路径恰好一致，否则失败。
- 因此 285 个测试文件 / 4.1 万行测试代码当前只在**一台开发者机器**上可跑，投入巨大却无回归护栏。

**修复方向（见 `docs/ci-l2-poc.md`）**：把 stdlib 路径改为环境变量 `GAME_ROOT` 驱动（回退到 `game-root/stdlib.lua`，再回退到仓库内 vendored 最小 shim），然后新增 `lua-labor-tests` job 镜像 `jar-checks`（无 `game-root` 则跳过）。这是 E 能真正落地的先决条件。

## 3. L2 候选首批接入清单（按用户表：JobStore / Claims / 调度）

现有 `tests/lua/` 中可直接作为 L2 门禁 POC 的用例（均为纯逻辑、mock native）：
- `labor-core-test.lua`（默认首批）
- `execution-sessions-test.lua`（Claims / ExecutionSessions 状态机）
- `logistics-progress-test.lua`、`haul-multi-target-test.lua`（调度 / 物流）
- `field-work-test.lua`、`membership-runtime-test.lua`（运行时契约）
- `persistence-test.lua`（生命周期 / 存档，对应 L6 自动化部分）

## 4. 与治理路线图的对应

- **Phase 1（D+E）**：D 已暂存修复；本矩阵即 E 的制品；stdlib 解耦 + `lua-labor-tests` job 为 Phase 1 收尾动作。
- **Phase 2（G）**：NATIVE 转移事务修复后，其故障注入测试应进 L2（物品所有权不变量）。
- **Phase 3（A/B/C）**：可靠性治理的回归用例进 L2/L4。
- **Phase 5**：重新审计前，本矩阵须"有效"（L2 能在 CI 或自托管 runner 稳定跑绿）作为新功能准入门槛之一。

## 5. 反目标（不要做）

- 不要"把所有 285 个测试一股脑塞进 CI"——先建矩阵与最小 POC，确认门禁能稳定跑绿再扩面。
- 不要用 L2/L4 的绿取代 L5/L6 实机验证。
- 不要在未解耦 stdlib 路径前声称"L2 已自动化"——那只是把单机脚本搬到另一台同路径机器。
