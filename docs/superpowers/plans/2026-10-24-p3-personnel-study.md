# P3 人员详情与实体书研习实施计划

> 本轮用户已明确继续开发，由当前会话原生执行，不启用子代理。

**目标：** 人员详情可查看真实技能/知识与研习状态；安全闲暇及缺配方工单驱动原件借阅、原版阅读、归还。

**架构：** 复用SELF_CARE个人Job、TaskRuntime与SelfCareCustody，把STUDY作为低于工作/生活的个人候选；LibraryIndex只提供共享候选，不调度身体。PersonnelService提供选中人员的只读详情。

**技术栈：** PZ42.21 Lua/Kahlua、ISReadABook、现有Java载体桥。

**设计：** [P3细化](../specs/2026-10-24-p3-personnel-study-design.md)。用户继续开发授权后，根据现有接口收敛为扩展个人执行器，不另建StudyRecord/StudyExecution；稳定身份及资产边界不变。

## 全局约束

- 单人、本地世界裁决；不宣称MP或原生动作实机通过。
- 原件ID、唯一声明、归还义务；不复制书、不直接写配方或经验效果。
- 保存恢复经统一Job及个人资源恢复，不在加载回调直接执行。
- 仅暴露已实现工种；翻译CN/EN成对；保留既有工作区修改。
- 在线需求已于本轮通过主机网络读取v3.2，临时下载只作为本轮核查，不建立第二份需求源。

## 重点风险

- 两人传阅同一本书，恢复的是各自页数；同一本同时借阅声明冲突。
- 阅读停止/旧回调不能提前或重复产生学习效果。
- 书籍来源失效或丢失时保留归还责任，不回收声明冒充结清。
- 阅读不能阻塞危急自理，闲暇不能抢占已可执行工作。
- 详情不每帧/全员扫描知识，切页停止详情刷新。

## 任务1：共享图书候选与原版阅读叶

文件：新增`client/EmberRoutesProbe/LibraryIndex.lua`、`StudyActions.lua`与定向Kahlua测试。

- [x] 共享索引按据点/观察版本分组，扫描预算由现有个人服务提供；登记STORAGE容器为可借阅图书箱，未授权书架不自动窃取。
- [x] `LibraryIndex.choose(actor,npc,entry,target,budget)`提供候选/完成标记/原因；候选含具体item、id、container、endpoint、entry、npc。
- [x] `StudyActions.read(c,item)`返回BT叶，原版方法逐项代理并围住Session/attempt；记录页数与完成/停止事实。
- [x] 验证传阅个人页数、重复完成、中断和丢失原件；JAR与Lua证据分开记录。

## 任务2：接现有个人仲裁、工单及恢复

文件：SelfCareRecord、SelfCareResources、SelfCare、SelfCareExecution、PublicWork。

- [x] 增加STUDY及可校验的阅读事实；借还复用现有原件声明、归还BT与正常保存。
- [x] 只有HOLD、安全、无携货/待恢复工作且没有可执行公共候选时才研习；自理需求出现停止阅读后先归还/安全使用个人物资。
- [x] 缺配方检查登记个人目标；取消后重验目标；完成只唤醒工单评估，不跳过认领资格。
- [x] 运行相关个人执行、恢复、公共任务定向Kahlua用例。

## 任务3：人员详情与可见状态

文件：新增PersonnelService、UI/PersonnelDetails；修改PersonnelPage及CN/EN翻译。

- [x] 所选NPC惰性读取全技能、知识、阅读进度和借阅原因；列表保留轻量摘要。
- [x] 单人优先级入口复用矩阵同一命令；床位、岗位及区域按实际数据展示，未实现明确标注。
- [x] 选中、升级、阅读完成失效；页面关闭释放所选缓存；人员UI定向检查CN/EN。

## 收口

- [x] Lua preflight并保留日志；Java有修改则构建与相关测试。
- [x] 递增版本并构建交付；doclink、更新BACKLOG/INDEX及专题证据。
- [ ] 原生阅读、正常存档和多人争用按集中实机验收核对；当前未运行，不计P3完成。
