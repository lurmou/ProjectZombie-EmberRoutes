# P1完整执行路径：集中单人验收

2026-10-23，0.22.13。依据[唯一架构v1.1](../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)与[P1计划任务5](../superpowers/plans/2026-10-23-p1-runtime-integration.md)。完整路径已默认启用；2026-10-23用户报告约定三组测试全部成功，按用户实机反馈记录P1单人验收通过。不是公共任务池、自动优先级认领或生活行为树已完成。

## 本次启用

Boot的controlledExecution固定为true，不提供游戏中热切换。制作、搬运、随从、动作/搬运诊断及保存恢复共用TaskRuntime；旧实现仅保留适配兼容代码。

客户端入口显式加载Persistence和StockService，后台保存/最低存量生命周期不再依赖打开制作界面。Boot核验全部Java控制/保存入口和Lua运行钩子；缺失时拒绝启动。声明恢复失败不开放任务运行。runtimeReady区分正常执行与RESET_REQUIRED原生清理状态；探针关闭或旧载体仍待清理时，不创建新执行会话。

在线需求导出正文SHA256：1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08，与上轮相同。原件、唯一Job/Session、UNKNOWN不重放及单人权威边界均未更改。[上一轮保存实现及限制](../reviews/2026-10-23/p1-unified-save.md)继续适用。

## 开始

完整退出并重新启动游戏，让Lua与Java同时加载0.22.13；使用已有单人测试世界及既有制作/仓储配置。确认仍开启沙盒中的载体探针。当前Workshop加载目录为Contents/mods/EmberRoutesProbe；若游戏使用解压安装副本，更新整包build/packages/EmberRoutesProbe-0.22.13.zip，保持同一mod id只有一个加载副本。安装基础沿用[载体说明](phase0-carrier.md)，不重复旧功能全套测试。

日志应包含：`[EmberRoutes v0.22.13] BOOT RUNTIME controlledExecution=true recovery=READY`。该行只证明入口已启用。MISSING_JAVA、VERSION_MISMATCH、RUNTIME_MODULES_MISSING或RECOVERY_RECORDS_INVALID表示未成功启用；RESET_REQUIRED只允许运行原生退出清理。

## 合并成三组操作

| 组 | 操作 | 观察与记录 | 实机结果 |
|---|---|---|---|
| 交接与原件 | 制作取料后切“跟随我”，再“继续原工单”；另做一次搬运中“暂停任务（保留货物）”后恢复 | 跟随/制作不同时控制身体；旧动作不再派发；恢复同一工单，原材料、工具和产物不增加副本。提交恰好完成时的中断须观察实际产物，不凭动画判断 | 2026-10-23用户报告两条操作成功，随后确认约定测试全部成功 |
| 隔离与诊断 | 两名NPC各有任务，只切换其中一名；选中忙碌NPC，右键箱柜→原版Debug/调试→余烬商路诊断→原版动作测试→吃测试食物（四分之一），再选同菜单“取消当前动作/测试” | 另一名继续原工作；旧回调不清除新队列，诊断也经过停止交接。须开启Debug模式及载体探针；这是世界物件右键中的诊断子菜单，不是面板按钮，也不是“NPC调试”。当前钩子要求worldobjects含有square，右键箱柜便于满足 | 2026-10-23用户报告全部测试成功，按约定诊断/隔离流程验收通过 |
| 保存与续接 | 制作/跟随状态下用Debug“人物存档：正常保存整个世界（不退出）”；再正常退出并读档；观察既有最低存量规则下一次正常补货 | 正常保存后不会永久停派；退出重进无重复NPC/原件或重复制作，原工单ID保留；最低存量周期仍使用原规则。活世界正常恢复可见PERSISTENCE LIVE_RECOVERY_OPEN，读档可见CHECKPOINT_RESTORED | 2026-10-23用户报告保存不退出及退出重进均续工成功，随后确认全部测试成功 |

若出现停止/效果不明导致CHECKPOINT_BLOCKED或RECOVERY_BLOCKED，保留当次现场和日志，按具体原因核查；不能将该状态当作已完成或立即重新生产。真正磁盘故障、强退与跨文件崩溃一致性仍未实测，本轮不要求通过破坏存档来模拟。

## 已执行的开发侧检查

- 新增task-activation-test.lua共30项：默认启用、缺失14个Java能力逐项拒绝、Lua消费者缺失拒绝、先恢复声明后授权、真实Boot推进TaskRuntime、暂停不执行、保存委托、旧世界隔离、RESET_REQUIRED限制与关闭探针不改写账本。原生body与引擎事件由替身提供。
- 相关定向回归：Boot15、随从20、保存61、正式制作28、搬运20、诊断命令8与持久化样本11通过；复用的旧夹具也随相应文件执行。故障门禁为宿主结果，不冒充真实磁盘故障测试。
- 0.22.13构建、Java测试及安装依赖哈希检查通过；preflight全部通过（109个Lua，0错误，LuaLS保留72条既有信息告警），release-check为0错误、54条既有中文提示；包内12关键文件与源码/JAR一致，6文档链接检查通过。原始日志为build/logs/p1-activation-startup-tests.txt、p1-activation-business-tests.txt、p1-activation-build.txt、p1-activation-release-check.txt和p1-activation-preflight.txt。结构lint仍跳过原版ISFluidEmptyAction.lua的0.0f解析缺口，不将其当作本模组检查结果。

实机日志使用C:/Users/MuMu/Zomboid/console.txt及本次重启对应的日志归档。已有tools/log-excerpt.mjs可以截取EmberRoutes版本、BOOT、PERSISTENCE及错误上下文；不新增诊断面板或持续监控。

三组结果及异常原件核对通过后，才将P1记为通过并继续共享任务目录和最小优先级认领。界面视觉仍最后处理。

2026-10-23验收登记：通过依据为用户对上述约定操作的实机反馈，未另行冒充逐帧日志/资产取证。真实磁盘故障、强退恢复、规模/性能及全部原生动作边界仍未验证，不包含在本次通过结论内。下一阶段进入统一任务接入，尚未实现公共领单。
