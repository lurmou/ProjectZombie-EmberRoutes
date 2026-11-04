# 搬运目录迁移与 Java 桥表面审计

基线：phase-3a-consolidation / 991c933；[设计](../../superpowers/specs/2026-11-04-domain-layout-design.md)与[计划](../../superpowers/plans/2026-11-04-domain-layout.md)。

## 搬运执行领域

client 8 个、shared 2 个 Haul* 模块迁入各自 EmberRoutesProbe/Hauling，原名不变，无旧路径转发。调用方同步更新。特殊动态路径：BuiltinJobContracts 的 record('Hauling/HaulJobRecord')、BusinessJobs 测试的 stub('Hauling/HaulManifest')。Boot 的 tickHaul 采样名和 HAUL providerType 不是模块路径，保持不变。

等价检查：42 个被修改/移动的现有源码/测试文件，逆向替换字面与动态路径后逐字节（仅归一 CRLF）等于基线；另核对启动文件的其他会话医疗调试 require 保持原样，未纳入提交。全生产/测试/工具/Java 文本旧模块路径残留为零，client/shared 模块名大小写折叠无重复。详细本地报告 build/domain-layout-equivalence.json。

创建/认领仍为 client/EmberRoutesProbe/Hauling/HaulJobs.lua 的 claim；正常 settle/finish 保留活动尝试/未结原件守卫；暂停仍为 HaulAgent.pause，恢复为 HaulJobs.prepareRecovery 与 HaulJobRecovery.restore。未改任务格式、声明、数量/容量或物理动作，不实现混装多目标搬运。

迁移前后相同安装版 Kahlua 命令（--java-labor --java-dispatch --java-job-data --keep-going）：haul-test、haul-source-backoff、hauling-provider、dec003-haul-migration、dec003-haul-recovery-boundary、labor-capacity-commit 通过；haul-routing、logistics、delivery-service 均在迁移前已由 multi-worker/work 宿主夹具失败，迁移后同样失败。9 套中 6 通过，不能写成全部通过。日志 build/domain-layout-before.log、domain-layout-after.log。modscan 扫描 358 个 Lua，与已安装模组整文件覆盖冲突 0。

首轮替换遗漏动态 record 路径曾引起 3 个新增失败，补齐后失败集合恢复基线；记录此检查的作用，不以文本扫描代替真实路径加载。真实游戏加载、动作、磁盘恢复与性能未验证。

## Java 与最终交付

ProbeRuntime 当前源码的 96 个 public static 方法中，91 个存在直接/局部别名引用，3 个使用字符串调用；log 供 Main/ProbeNpc 同包使用，改为 package-private；lumberjackSquareHasTree 无生产/测试/工具/Java 调用，删除桥转发而保留 CleaningFastScan 实现。其余 94 个正式名称保持不变，包括 laborCreate/laborMutate/laborCancel。不是删除“约20个未使用方法”，也不宣称性能提升。Main 暴露同一类与 Lua 全局名，业务权威未变。

ProbeBridgeSurfaceTest 在修改前准确失败为 extra=[log, lumberjackSquareHasTree]；修改后对实际编译类反射通过，检查 94 个名称、无意外重载、包可见日志与已删转发。新检查接入既有 build-probe.ps1，不增加运行时注册层。反射 metadata 测试不初始化世界，不代替游戏 Exposer 实机加载。

0.29.38 实际依赖构建通过：358 Lua 普通/Debug 编译、Java 编译、既有构建中的逻辑/保存/原生读取/提交内核检查以及桥表面检查通过。实际加载目录 JAR、Build.lua、mod.info 已重建；ZIP 的 10 条新 Lua 路径齐全、10 条旧路径均不存在。保留的另会话 NpcMedical 调试文件仍在本地工作区，因此本地包还包含这份未纳入本轮提交的文件，不宣称包与 Git 提交完全相同。

最终历史 Kahlua 全量为 210 套、139 通过/71 失败；与此前 demand-medical-final-regression.log 的失败名称集合完全相同，无新增或消失。日志 build/domain-layout-full-regression.log。release-check 仍是基线 PageLifecycle.lua 两处 print 错误与 22 条 CJK 提示；本轮未改该文件，不称正式发布门禁全绿。6 份相关文档链接检查零断链。

完整 preflight 退出 0：Lua lint 358 文件 0 error/12 warning，结构与 prerender 规则通过，候选规则未命中，LuaLS 0 error/675 warning（未逐条审查）、索引新鲜度 10 项通过；EOL 专属检查因本模组非 EOL 结构明确跳过。日志 build/domain-layout-preflight.log。原版 ISFluidEmptyAction.lua 中 0.0f 导致知识库解析跳过的既有覆盖限制仍在，不宣称原版全部建模成功。
