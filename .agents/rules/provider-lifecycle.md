---
trigger: always_on
description: 垂直工种与生命周期闭环铁律：契约对齐、唯一身体控制、原件责任四阶段闭环、零虚构降级、持久事实与释放对称
---

# 垂直工种与生命周期闭环铁律 (Provider & Lifecycle Invariants)

在实现、重构或扩展任何业务工种（如清洁、农业、伐木、采集、烹饪、搬运等）或接入系统任务时，必须严格遵守以下五大铁律：

## 1. 契约绝对一致 (Contract Parity)
- **严禁私设平行接口**：向既有调度或注册表（如 `PublicWorkProviders`）注册的工种，必须 100% 严格对齐基准规约（如 `discover/claim/advance/reconcile/hasWork`）；
- **严禁自创未注册抽象**：禁止发明平行自洽但未接入协调器的私有函数（如 `evaluate/startBatch`），未实现的接口必须显式返回对应拒绝码或保持标准桩签名，禁止伪造或假装可用。

## 2. 身体控制单点受控 (Single Body Control Point)
- **严禁直接驱动身体**：全库除 `TaskController` 外，严禁任何业务服务或工种直接调用 `luautils.walkAdj`、`luautils.walkTo`、`character:walkTo`、`character:pathTo` 或直接向 `ISTimedActionQueue.add` 塞入行动；
- **先授权，后干活**：一切角色移动与原生动作，必须以 `Driver.acquireControl` 获取身体授权、通过 `TaskController` 会话下发为硬性前置门禁。打断（随从指令、睡眠抢占、活动召集）时必须在下一安全帧干净退出。

## 3. 原件责任四阶段闭环 (Asset Lifecycle Closure)
- **严禁半截子工程**：任何产生、收集、消耗或转移物品的劳动，生命周期必须完整覆盖：
  $$\text{PREPARE (工具与前置)} \longrightarrow \text{WORK (物理作业)} \longrightarrow \text{COLLECT (原件锁权)} \longrightarrow \text{DELIVER (仓储交付)} \longrightarrow \text{SETTLED (责任解除)}$$
- **“动作完成 $\neq$ 任务结清”**：严禁在砍倒树、收获作物或采摘完成的瞬间直接将任务置为 `DONE`；必须追踪真实原件 ID，执行受控入仓交付；当仓库满仓或缺失时必须留责等待或隔离，绝不允许产物滞留个人背包或散落地表沦为黑洞。

## 4. 零虚构降级容忍 (Zero Synthetic Fallback)
- **禁止降级伪造**：当划区缺失、工具不足、地块无效或边界受限时，必须直接报错、阻断或进入冷却退避；
- **严禁掩耳盗铃**：严禁私自使用假坐标回退（如 `{x=0, y=0}`）、私自扩大未授权搜索半径、或为拼写错误添加别名兼容（如 `getPolicy = get`）。必须沿调用链修正数据模型与调用源头。

## 5. 持久事实与释放对称 (Symmetric Claim & Release)
- **严禁纯内存黑户**：凡是在公共调度目录（如 `directory:claim`）中认领了资源或地块的任务，必须在 `JobStore` 拥有最小持久化记录（如 `FIELD_WORK`），保障存档重进与打断恢复；
- **有始必须有终**：任务无论是 `DONE`、`CANCELLED` 还是角色死亡，必须显式调用 `directory:release` 归还地块与配额锁，严禁永久泄漏认领配额导致资源点永久死锁。
