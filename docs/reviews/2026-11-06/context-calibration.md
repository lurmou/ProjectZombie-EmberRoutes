# 工程上下文校准：0.29.54

更新：2026-11-06｜状态：本轮校准完成，扩展回归未全绿。用户授权校准迁移后的文档/技能/门禁及旧提示入口；未提交、推送或发布。

## 修正范围

- 三份技能：add-provider、develop-ui-page、verify-codebase按真实调用契约重写；区分静态扫描、调用点清单、指定Kahlua、UI文本及构建各自覆盖范围。移除虚构TaskController.acquire、session.walkTo/queueAction/finish等可执行示例。
- 九份领域文档、INDEX权威矩阵/物理路由、ui-architecture当前入口及两份UI设计中的提示模块引用校准。清除虚构存档键、API、业务状态/自动恢复能力；保留已批准设计为链接，不把目标当实现。SquadPreferences仍仅布局/显示顺序/缩放/呼号；跟随授权和小队身份仍由MembershipService独写。
- provider-lifecycle规则不再要求取消/死亡即无条件release；与现有TaskDirectory.release的KNOWN+obligationsCleared证明门禁对齐，没有改变生产语义。

## 真实协议与所有权证据

代码根：`Contents/mods/EmberRoutesProbe/42/media/lua/`。

创建/认领：`client/EmberRoutesProbe/Work/PublicWork.lua`发现分支使用provider.discover(envDiscover)，自己先生成jobId与directory.claim，再调用provider.claim(selected,npcId,jobId,env)。`client/.../Runtime/TaskRuntime.lua`校验完整spec并submit，Controller.attachDriver经Driver.acquireControl获得身体授权。

正常释放：`shared/.../Kernel/TaskDirectory.lua`只保存可重建offer，release(key,jobId,proof)要求KNOWN与义务清偿；`client/.../Hauling/HaulingProvider.lua`确认对应Work记录DONE后才释放。不是“reconcile被调用就全部释放”。

异常打断：`client/.../Runtime/TaskController.lua` stopOnce要求requestStop/observeStop/persistEffects，经TaskStopEvidence.validate后释放身体；HaulingProvider缺记录时保留责任并报RECONCILE_REQUIRED。身体停止和原件结清分别处理。本轮未修改这些身体/资产协议。

## 等价归属与旧接口清理

1. CookingBudget从shared/Cooking移到client/Cooking：它实际提交client/Work/LaborStore；公开require名不变，旧物理文件删除，准入/Jobs/Claims逻辑未改。
2. BatchStoragePainting从shared/Warehouse移到client/Warehouse：原实现通过pcall(require,...)调用客户端ContainerRegistry；公开require名不变，无旧文件或转发。
3. RecipeOrderEntry从client/Crafting移到client/Integration，入口与相关fixture同步改当前路径；原版UI接入行为未改。
4. PersonnelService.rows的完整展示函数移到UI/PersonnelPresentation.rows；两个真实UI调用方和人员测试同步，颜色/文本仍保持原结果，业务服务不再依赖Theme。
5. 全部TooltipAnchor生产消费者及fixture改TooltipManager；原attach参数原样转为register配置，owner缺省逻辑不变；clearOwner调用改dismissOwner。删除TooltipAnchor文件和Manager.attach/clearOwner旧兼容入口。60项原管理器测试与24项面板接缝通过。

## 门禁修正与证明边界

`tools/check-architecture.py`使用轻量词法分解排除注释/字符串示例，建立实际client/shared/server模块索引，检查字面量require与pcall(require,...)。覆盖所有业务目录对UI的依赖（Integration和入口脚本负责UI装配）、shared对非shared模块、失效本地模块名、根目录散落文件、UI直接ModData写入/创建及直接角色ModData赋值。构建开始运行一次并在失败时退出，不重复执行。

它不证明动态拼接加载、别名数据流、循环依赖或运行时资产/身体所有权；输出明确标记未证明项，禁止把0静态违规说成全库架构正确。

`check-i18n.py`按当前源码树定位MembershipMenu/SettlementDashboard；缺失/重复均报错，不再使用迁移前路径然后静默跳过。所有有限动态小队键仍保留前置检查。

13组Python测试（含各业务目录子用例）验证新检查会失败而不是只对现仓库全绿：目录缺失、反向依赖、pcall、bootstrap入口、注释/字符串/动态加载排除、ModData写入与比较区分、必需源码丢失/重复、迁移后菜单新键实际被检查。临时语料不写生产数据。

## 本轮检查

通过：
- `python -m unittest discover -s tests/python -p test_context_gates.py`：13组通过。
- `python tools/check-architecture.py`：0静态错误；`python tools/check-i18n.py`：2050对IG_UI键及UI/Sandbox文件对称、有限动态域通过。
- 定向Kahlua：tooltip-manager(60)、storage-panel(24)、squad-command-ui(59)、squad-preferences(18)、p3-personnel-relief(12)、delivery-cart(76)、settlement-overview-ui、cooking-foundation(30)、task-controller(33)、task-driver-control、companion-handoff、player-stash-routine(23)。原生动作/控件为替身。
- UI总脚本在失败前完成中文/换行/窄宽文本、UI基础、TooltipManager、lifecycle-scope(558)和page-lifecycle-integration(194)；这些部分通过不代表整条命令通过。
- 最终build-probe通过：新边界门禁、370份Lua普通/Debug双模式、真实Java编译、96桥、94基础断言及现有控制/检查点/轨迹/姿态/指标与内核检查。
- doclink检查当前领域、三份技能、导航、UI工程契约与计划无finding；定向空白检查按仓库空格缩进策略执行。
- 身体审计--changed生成`build/context-control-audit.json`，为文本调用点清单；不能凭exit0认定无越权。本轮没有改原生身体调用方法。

未通过，完整保留：

| 用例/命令 | 实际失败及界限 |
|---|---|
| public-work-test.lua | 缺知识时未观察到预期studyTarget，断言失败；未判定根因，不修改生产准入或删除断言 |
| multi-worker-test.lua | 所需tests/lua/work-test.lua不存在；未凭想象重建旧fixture |
| dec003-kernel-workcapacity-test.lua | 宿主arg未提供，line156读取arg[1]失败；未记成烹饪/容量业务通过 |
| tools/test-ui-kahlua.ps1 | 前述文本/生命周期通过后，在settlement-storage同阵营重叠身份断言失败；命令整体失败 |

本轮不宣称全库回归通过，也未证明这些失败均由本轮引入或均属历史问题。下一步应分别核对夹具/宿主入口和真实生产行为，不能放宽守卫迎合测试。

未运行：游戏内鼠标/提示/显示、原生动作效果、磁盘重进与性能；没有启动或控制游戏。保留同期迁移/防御UI等改动。

## 交付

版本0.29.54；隔离构建`build/context-calibration-0.29.54-135205`，候选`build/packages/context-calibration-0.29.54/EmberRoutesProbe-0.29.54.zip`。
最终构建输入无漂移；包内395项与验证时工作目录对应文件逐字节一致，没有TooltipAnchor或旧shared预算/批量标记文件。游戏未运行时仅同步已验证JAR/mod.info/Kernel/Build.lua。
ZIP SHA256：`e65f36f02eefa3ae4a69fd2671868fd41b357d8325bb0f38554078e7b3f62ea8`。
