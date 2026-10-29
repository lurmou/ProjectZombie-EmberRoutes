# 0.29.6 自主搬运 R1 实施证据

> 日期：2026-10-26｜状态：实现、定向宿主、构建及最终静态门禁通过；实机未运行。

依据[从属设计0.2](../../superpowers/specs/2026-10-26-haul-routing-and-custody-design.md)及[实施计划](../../superpowers/plans/2026-10-26-haul-routing-r1.md)。用户在设计修订后明确“开始吧”，本轮实施R1与当前有效共享Job有界升级；R2、人工核销和显式端点语义变更未实施。

## 已接入行为

- 自主LOGISTICS经WorkAgent薄委托进入HaulAgent，显式端点搬运保留旧路径。仍使用TaskRuntime、TaskBusinessStop、WorkTransfer及原版ISInventoryTransferAction，不新增独立调度器或转移引擎。
- format=2清单保留完整items和计划分母；HaulManifest派生未结原件声明。已核验交付形成逐原件回执，LaborStore.settleHaulLines与LaborClaims.shrink同步缩减原件/容量声明，暂停与恢复不按完整items重新认领已交付货物。
- 初次仍同源同目标成批拿取；目标规则/容量失效后停止取新货、撤回未取行，持货可重新选箱并逐站交付。候选复用据点容器、StorageFilter、SortPolicy和共享容量；持货不要求新增负重余量。
- 路线失败先停止、核验旧尝试，再经新Session恢复；动作绑定精确端点和不可变attempt。分类拒收不冒充UNKNOWN，私人端点不因核对而获得读取例外。真实缺失/未决效果保留责任，禁止重复转移或删除任务掩盖问题。
- 无目标、容量不足、未加载和路径退避分开报告；系统路由等待通过现有LogisticsService共享tick有界轮转，依赖变化或错峰低频兜底唤醒。USER暂停、FOLLOW/WAIT上下文、保存屏障及UNKNOWN不能被自动恢复绕过。
- 当前有效共享Job的format=1搬运，仅在暂停、原身体已停止且源箱/NPC/目标箱逐ID核验完整时同Job升级；私人、未加载、缺失、重复或controlUncertain不自动升级。不导入共享Job之前的旧格式。
- 人员/工单监控保留已交付计数，区分持货、尚未取货和撤回行，显示当前交付端点及路由等待；CN/EN成对。BusinessJobs回收增加清单未结/未决尝试门禁。

## 实际验证

游戏安装JAR及ZombieBuddy哈希仍由既有构建脚本固定校验；本轮未修改Java行为。版本递增至0.29.6，构建及版本包已生成。首次误用Windows PowerShell 5执行构建时，JVM原生访问警告被当成NativeCommandError；改用本机pwsh后构建通过，未改JVM测试或降低失败门禁。

| 验证 | 结果与边界 |
|---|---|
| 新haul-routing-test | 26项定向断言通过：部分入库后拒收、食物/工具分箱、无目标等待/新增箱唤醒、容量token缩减/换代/空集合、受控暂停继续、当前任务升级、排队PUT变私人、旧回调、世界缓存重建后只恢复未结声明；原生身体及动作宿主为替身 |
| 相关既有Kahlua | logistics-test、task-work-runtime-test、task-transfer-uncertain-test、order-monitor-service-test、task-save-runtime-test通过；与新用例合计6个入口，未重跑全历史套件 |
| UI宿主 | 中文settlement-tabs 711项及logistics-page 33项通过；不代表实际游戏绘制通过 |
| 构建 | 固定依赖构建、既有Java/编解码/原生批读取检查通过；不代表实机运行 |
| preflight | 最终完整门禁通过，包含结构检查、类型检查和索引新鲜度；原版Fluids/ISFluidEmptyAction的0.0f语法仍为工具已知解析盲区，不属于本模组源码 |
| 发布与包一致性 | release-check 0 error（76项既有提示）；最终版本包198份文件逐项SHA256与当前工作区一致，重打包后的zip哈希已更新build报告 |
| 游戏实机、磁盘重进、强退、规模性能 | 未运行；世界缓存重建不是原生磁盘存档恢复验证 |

原始记录：[R1定向宿主](../../../build/logs/haul-r1-kahlua.txt)、[6入口回归](../../../build/logs/haul-r1-regression.txt)、[UI宿主](../../../build/logs/haul-r1-ui.txt)、[构建](../../../build/logs/haul-r1-build.txt)、[最终preflight](../../../build/logs/haul-r1-final-preflight.txt)。构建目录不作为永久需求来源。

fixture增加了新适配模块的重载清理，并把物流事件测试从“最后一个listener必是物流回调”改成向全部库存监听者发出真实ID通知；否则新注册的PlanningWake会使旧测试错误地调用另一模块的回调。这是测试接缝修正，不是删除失败断言。

## 实现细化与剩余边界

当前交付站点以单件预约逐件推进并复用同一目标，未实现主动混装或全局最短路径；数据结构支持换站不等于已支持R2。路径失败记录跨Session保留，按端点退避15秒，表有界90条；恢复候选每轮最多2个，选箱组合预算为共享50ms窗32个、单次最多8个；无目标兜底约5秒加错峰。这些数值未做实机负载测量，不承诺响应上限或NPC容量。

当前原件观察使用原有View有界切片；缓存重建只证明声明索引按manifest恢复。外部移走持货、私人化发生在物理效果与回执之间、无法访问的旧现场等仍可能需核对，不能保证安装即可救活所有旧任务。没有任何删除重造、丢弃或人工核销出口。

建议一次实机复验覆盖原现场：拿取多件→第一件入库→冰箱拒收→剩余改送；另选一次无目标等待后开放新箱，并在持货暂停状态正常保存重进。已有原件保持实例状态；不能只看TAKE/TRANSIT判断物理位置。
