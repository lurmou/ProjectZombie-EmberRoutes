# P1任务3：正式制作与搬运接线（0.22.9）

## 2026-10-23：0.22.15实机续工修正

下文0.22.9为历史接线状态；0.22.13已开启完整路径，P1仍未通过实机验收。用户在0.22.14报告锯原木途中切跟随，只能看到暂停；回据点后显示继续但无动作。

console.txt中同一NPC adbba889…、工单b633e1c2…在帧28403记为PAUSED REPLACED，28405进入FOLLOW；32043进入RETURNING，32443记录HOME_PATH_ENDED（距目标约0.401格），32444最终HOLD。随后未见此工单RESUME resume。另一NPC 00f750b5…的续工实际收到命令，但因MATERIALS_UNAVAILABLE暂停；不能混为同一工单。过滤证据保存在build/logs/p1-follow-resume-game-evidence.txt。

定位与修正：

- CraftingOrders误把Work.busy（身体被任何任务占用）当作制作执行中。Service快照补独立orderBusy，按钮与继续提示按本单执行状态判断；暂停工单可明确申请接替跟随，仍经过原有TaskRuntime停止与获授协议，不直接抢身体。
- CraftingService.resume在无工作台且未选择工作台时，nil==nil成立，错误调用Surfaces.resolve(nil,nil)，提前返回CRAFT_SURFACE_REQUIRED。现仅真实benchId匹配时走旧工作台兼容校验；手持锯木无需虚构平台，平台配方仍重验原定位。
- 每次人工制作命令记录npc/command/result，包括在Service提前拒绝的情况，避免只有执行成功后才出现日志。
- 0.22.14翻译修复不完整：getText参数进入格式化时会成为字符串，旧%d导致IllegalFormatConversionException。最低存量10个及制作链4个动态翻译键成对改为原版%1/%2；制作链调用同时携参，移除先无参翻译再string.format的错误用法。以当前安装JAR的Translator.formatFixer/getText核对，字节码在build/research/follow-resume-translator-javap.txt。

定向Kahlua：受控制作46项（依赖既有652项制作夹具），界面543项通过，包含跟随期间的本单状态和实际Service无平台续工；安装Translator中英文28项参数检查通过。0.22.15构建、preflight（0错误/74信息告警；need-check-nil较此前增加2条，现有order/worker逻辑关联未被类型推导识别，尚未清零）、release-check（0错误/44提示）、7个关键Lua/翻译文件包内一致性和文档检查通过。原始日志build/logs/p1-follow-resume-*。实机修正效果、极近距离HOME_PATH_ENDED及P1其他验收仍待确认；本轮未调整寻路阈值。

状态：正式Production与Work搬运的申请、受控动作、暂停及正常完成已接入TaskRuntime；最低存量接受异步启动回执。**迁移总门闩仍关闭，P1任务3未全部完成，游戏继续使用旧路径。**

本轮依据：[唯一架构v1.1](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)、[P1实施计划](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)、[0.22.8运行服务](p1-task-runtime.md)。不重选架构，不迁移为公共Order或多挂起Job存档，不增加新的任务选择器。

## 运行接线

- Production的run/resume/return在总门闩开启时先提交申请，复制选项、固定NPC和Job ID、重复核验当前世界及业务代次；只有身体获授后才创建业务记录、认领原件和建立执行上下文。原件继续由LaborStore裁决。
- Work搬运的人工启动、自动assign和resume同样经过TaskRuntime。队列请求不提前发布伪运行记录或锁住原件；实际启动再次核对端点/原件/容量，发布原记录并使用同一Job ID恢复。自动分配/自动恢复为非抢占申请，LogisticsService把QUEUED作为已接收处理。
- 制作与搬运上下文保存绑定票据的body能力。移动、动作入队及清理走受控出口；旧Work调度不再重复推进受控NPC。body.current与原业务代次/声明共同约束原生动作的有效性。
- 运行服务为劳动流程提前捕获停止adapter，业务完成移除上下文后仍能完成停止核验。暂停先封派发，再保留实际原件和恢复点；正常完成只在物理交付核验后释放业务声明，再经原生及Lua停止确认关闭身体会话。
- 劳动adapter明确自行核对异常后的效果：搬运重索引原件位置，制作保留提交事实及uncertain。只有提供这种证据的流程才设置reconcileErrors；通用运行服务仍不能把异常当回滚。缺失原件、未知制作提交不会自动重放。
- 新body.requestStop只作用于原票据，stopJob只取消匹配Job；迟到动作的perform/stop/动画回调不能调用继任会话的原生队列处理。运行中的清单清除、移除人物先等待原会话退出，不能先擦掉恢复记录。
- 查当前安装版ISTimedActionQueue：clearQueue可擦除queue数组而保留current字段，resetQueue才显式清current。body.clear只整理本票据拥有的空队列引用；**没有把这一整理当作停稳证据**，关闭仍须原生停止位图与业务效果共同满足。
- StockService收到QUEUED后保留PREPARED及瞬态回执；实际制作记录出现才attach。仍存活的排队请求不能当孤立准备单回收；拒绝/取消只回收未启动准备单，规则关闭时取消对应Job。未改变最低存量原有产品语义。

## 剩余工作与启用条件

下一步仍是任务3：旧CraftProbe格式1/2及旧草稿执行路径、Actions/Haul/NpcCommands/Persistence样本等诊断写入口，随后汇总控制旁路清单。正式Production的tickPending现在经公共execute提交非抢占申请；旧CraftProbe自动续工及全局恢复仲裁尚未收口。

再执行任务4统一保存/退出事实捕获、读档和StockService恢复。当前OnSave尚未切到统一运行服务，不能打开Boot.controlledExecution；也不能在已有旧会话运行中直接翻开门闩。P1验收前不开放公共任务目录、完整优先级或新工种。

本轮未改界面布局。后续界面仍按需求11.1～11.4与现有UI基础契约实施；视觉稿可以由用户另找AI提供，业务命令、状态投影和实现必须使用同一架构，不能另造任务状态。

## 检查证据

- 安装Kahlua：新增受控制作28项、搬运20项；包含真实Production→Companion→同Job恢复、取料后暂停保留认领、缺失原件UNKNOWN、制作未知提交不重放、两NPC隔离、迟到回调不清新队列。
- 运行服务36项、StockService18项（含5项排队周期检查）、随从接线20项、停止边界14项、未知搬运保护及物流167项通过。依赖夹具中的旧制作652项、多NPC48项及相关搬运/动作回归也通过；它们由定向入口复用，不是原生实机证据。
- preflight通过：107个Lua文件语法/结构检查无问题，LuaLS初次为0错误、112条信息性告警。同一源码的明细复核为0错误、72条告警（undefined-field 67，其余5），与既有分布一致；明细集中于StockRules动态UI字段及已有4处检查项。本轮未修改源码来消除告警，计数波动原因未定位，不将重跑减少解释为代码修复。原版知识库中ISFluidEmptyAction.lua的`0.0f`解析失败仍为工具覆盖缺口，不作该文件的检查结论。
- 0.22.9构建成功，包含现有Java、检查点、名册、身体授权及安装基线检查；发布检查0错误、54条既有硬编码中文提示。ZIP中的15个关键Lua/翻译文件逐一SHA256匹配工作区，Build.lua、mod.info与version.txt均为0.22.9。5份本轮文档链接检查无断链；定向diff空白检查通过。
- 原始输出：`build/logs/p1-labor-runtime-tests.txt`、`p1-labor-runtime-preflight.txt`、`p1-labor-runtime-release.txt`；构建沿用现有build/logs日志。类型告警详情另存`p1-labor-runtime-luals-details.json`。
- 新路径的游戏内动作/交接、保存读档、退出恢复和性能**未验证**；本轮不宣称正式NPC已经迁移或P1通过。

## 在线需求读取恢复

本轮已重新获取Google Docs导出正文，SHA256为`1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08`，与上次成功读取的导出相同。输出保存在`build/logs/requirements-current.txt`，不建立平行需求。

失败原因已缩小到读取通道：网页工具直接打开URL失败，沙箱内curl使用Windows Schannel报`SEC_E_NO_CREDENTIALS`；在正常网络上下文对同一导出URL进行只读请求成功。本次不是文档权限拒绝，不应直接要求用户改共享权限。此事实不保证所有未来网络故障都同源。仍保留用户在对话中明确批准的阶段修正，不用旧导出覆盖这些决定。
