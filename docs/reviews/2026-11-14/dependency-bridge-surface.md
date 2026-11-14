# 依赖图与桥面签名门禁证据

日期：2026-11-14。main 工作区（HEAD `cc77901` 加既有未提交改动），版本 0.29.62。保留此前责任账本、claims 单实现、QA 与翻译改动；本批未切换分支、未提交、未推送。

## 一、依赖图现状与门禁

### 测量口径

`tools/check-architecture.py` 的 `tokens/requires` 只解析字面 `require('EmberRoutesProbe/...')` 与 `pcall(require, ...)`，跳过注释、字符串示例和拼接名；目标必须能解析到实际存在的模块。因此下列数字是**静态字面依赖**，不含动态加载、别名访问、`Probe.*` 全局调用或事件订阅。`EmberRoutesProbe.lua` 入口按 `Integration` 计。

### 现状（工作区实测）

- 跨模块字面边总数 208：同层 126（client→client 113、shared→shared 13），跨区 82（全部 client→shared），shared→client 为 0。
- `shared/Kernel` 与入口的 Kernel 依赖没有同层出边；Kernel 只作为目标出现。
- 同层出度最高的 client 域：Integration 12、Runtime 10、UI 10、Work 10、SelfCare 9、Cooking 8、Warehouse 8、Crafting/Field/Hauling/Leisure 各 7、Activity/Logistics/Settlement 各 6。
- 反向读取确实存在：`client/Runtime` 直接 require 10 个 client 业务域（Activity、Chatter、Cooking、Crafting、Field、Hauling、SelfCare、Settlement、Warehouse、Work）；`Runtime ↔ Work`、`Runtime ↔ SelfCare`、`Cooking ↔ Crafting` 等双向边都在基线内。
- 结论：文档原先写的“UI → 业务 → Kernel/Runtime 单向铁律”不是当前事实，只有 UI 反向依赖与 shared→client 被禁止。

### 新增门禁

`tools/check-architecture.py`：

- `DOMAIN_EDGE_BASELINE` 冻结上述 126 条同层边。新边报 `new same-area cross-domain dependency`；基线中存在但源码已无对应 require 的边报 `frozen dependency edge is gone`，要求下调基线（与 COMPAT/DIRECT_CALL 棘轮一致）。
- `check_dependency_graph` 对 `Kernel` 出边单独硬拒绝：即使把该边写进基线也会失败，避免用改基线的方式让 Kernel 依赖业务域。
- 跨区规则继续由 `inspect` 负责：shared 不得 require client，业务域不得 require UI（Integration 是组合边界）；缺失模块与平铺模块仍单独报错。

反例覆盖（`tests/python/test_context_gates.py` 新增 `DependencyGraphTests`，5 项）：新 client→client 边失败、新 shared→shared 边失败、基线内边通过且注释里的 require 不算边、删除边要求清基线、Kernel 边即使入基线仍失败、同域与拼接名不产生边。`python -m unittest tests.python.test_context_gates` 共 47 项通过（此前 42 项 + 新增 5 项）。

本批不拆循环、不改 Runtime 对业务域的读取、不改任何运行时调用路径；基线只记录现状，不宣称无环或分层已达标。

## 二、Java 桥面完整签名

`tests/java/emberroutes/probe/ProbeBridgeSurfaceTest.java` 由“119 个方法名 + 20 个身体入口签名 + claimsCommand 特判”改为：

- `SIGNATURES` 冻结 119 个公开静态入口的 `name | return type | ordered parameter types`；夹具行数必须为 119，名称不得重复。
- 每个入口必须仍是 `public static`，返回类型与有序参数类型必须完全一致；参数用 `Class.forName(..., false, ...)` 解析，不初始化游戏类。
- `ProbeRuntime` 不允许出现夹具之外的公开静态入口，也不允许同名重载；内部 `log` 必须保持包可见静态；已删除的 `lumberjackSquareHasTree` 不得回流。

正向结果：`PASS 119 complete Lua bridge signatures; metadata only, game NOT RUN`（当前工作区源码编译出的 classes）。

反证（在不改生产源码的前提下，把源码复制到 `build/sigcheck/neg/` 后变异再编译运行）：

- `workerCount` 返回值 `int → long`：`AssertionError: bridge return type changed ... expected int`。
- `version()` 增加一个参数：`AssertionError: bridge signature changed or removed: version|java.lang.String`。
- 追加 `version(int)` 重载：`AssertionError: unexpected bridge overload`。

三种变异均以退出码 1 被拒；未拆桥面、未改公开签名。

## 三、文档、注释与术语对齐

- `docs/INDEX.md`：Kernel 示例去掉并不存在于 shared 的 `LaborStore`；client 拓扑补上实际存在的 `Chatter/`，去掉不存在的 client `Kernel/`；“依赖流向单向铁律”改为目标方向 + 现行门禁（含 126 条冻结边和 Kernel 规则）；DECISIONS 范围由 DEC-005 更正为 DEC-012。
- `docs/domains/kernel.md`：§5 写明三条强制规则与基线的“现状”含义；§6 桥面说明改为 119 个完整签名；§7 按 `KahluaLaborTest` 当前默认套件（labor-core、sort-policy、logistics、multi-worker、companion、persistence、boot-pause）重写，不再声称 task-* 在默认套件内。
- `docs/domains/work.md`：`KERNEL_CATEGORY_LITERAL_COUNT` 由陈旧的“10→2”更正为 PublicWork 0 / PublicWorkOrders 2 / 注册表 0；`GLOBAL_WRITE_BASELINE` 由“17 处”更正为当前 15 个名字；§7 测试套件说明与源码一致。
- `docs/CHANGE_CHECKLIST.md`：桥面由“114 方法白名单”更正为“119 个入口的完整签名”，通过输出文案同步；BuildInfo 生成位置不再写易漂移的行号区间。
- `AGENTS.md`：callback-first 条目保留 main `6ed6b25` 历史计数，并补一句“当前计数以 `DIRECT_CALL_BASELINE` 为准（只减不增）”。
- `tests/python/test_context_gates.py`：`ProviderRetainedTests` docstring 改为当前 BuiltinJobContracts → PublicWork → `Providers.register` 链路；删除对已删除模块 `CraftLegacyRecovery` 的示例引用。
- `tools/check-architecture.py`：同步修正 provider-retained docstring 的坏句与已删除模块示例。
- `LaborClaims.lua`：头注释改为“写操作只有 Java 一处实现；Lua 保留只读查询”；删除被文件后部同名 Lua 定义覆盖、不可达的 `methods:canShrink` 桥包装（4 行）。Lua 的只读 `canShrink` 仍由测试使用，行为不变；Java `ClaimsKernel` 的 `CAN_SHRINK` 分支仍保留给内部 `shrink` 预检，但 Lua 已不再发送该命令。

## 四、验证

- `tools/check-architecture.py`：0 error；`check-undeclared-globals.py`：456 份生产 Lua 通过。
- `tests/python/test_context_gates`：47 项通过。
- `ProbeBridgeSurfaceTest`：119 项完整签名通过；三种变异反证全部失败（预期）。
- `tools/build-probe.ps1`：0.29.62 BUILD_OK，456 份生产 Lua 普通/Debug 编译、Java 编译、架构/未声明全局门禁、2189 翻译键与固定回归通过；日志 `build/dependency-bridge-build.log`，包 `build/packages/EmberRoutesProbe-0.29.62.zip`。首次运行因未设置 `GAME_ROOT`，Kahlua L2 stdlib 步骤拒绝运行；设置后同一命令通过，不是代码失败。
- Kahlua 默认七项：通过（`labor-core`、`sort-policy`、`logistics`、`multi-worker`、`companion`、`persistence`、`boot-pause`）。
- 显式 `claims-kernel-recovery-test.lua`：16 项 Java claims 轮换/隔离/冷恢复/释放检查通过。
- 显式 `phase3a-stage-b-test.lua`：在 `restoreClaimIdentities`/`byId` 处失败；临时恢复被删除的 `canShrink` 包装后同样失败，确认与本次删除无关，属既存显式历史测试失败，不在默认七项内。

未验证：游戏内行为与延迟、真实磁盘保存/崩溃恢复、性能；依赖图只覆盖字面 require，不证明运行时调用图。未测量拆循环或桥面拆分的收益。

## 五、工作区

源码仍为 main 未提交工作区；未提交、未推送。构建产物在 `build/`（已忽略）。未改持久格式、资产结清/恢复语义、生产守卫或公开桥签名。
