# Phase 3A Work 格式接纳门禁

> 日期：2026-11-01｜修改前 HEAD：`33fdc84`｜代码提交：`59d8d1f`｜状态：实现待外部审查，B.5 未关闭，Stage C 冻结。

## 问题与改动

此前 Registry 先写 `format`/`containers`，JobStore 才拒绝未知账本；Save.load 的成员/库存/制作恢复也先于任务格式检查。专项测试在旧代码上失败：无版本但含 taskJobs 的根表被错误初始化。

现在 JobStore.check 与 open 共用只读 prepare，保持原有任务接受范围；Registry 在默认值前执行检查，仅空根表可作为新世界初始化。按根及 taskJobs 表身份缓存接纳结果，同一已接纳世界读取不重复扫描。此缓存不代替后续写入口自己的生产校验。

MembershipLifecycle 的 OnInitGlobalModData 必须把引擎提供的根表直接交给同一 Registry 门禁，再写 npcMembership；不能在 bridge.begin 前使用上一世界的缓存。Save.load 先取得已接纳根表，再调用恢复钩子。没有删除 Production、Haul、ToolCustody 的任何现役认领/释放/恢复接口。

## 实际验证

使用真实 Registry/JobStore，替换 ModData 与原生缓存桥，专项 `tests/lua/work-format-admission-test.lua`：**57 项 PASS**。

- 直接 ModData 与缓存桥两条路径拒绝未知根/任务格式、非表 containers、旧独立任务账本及非法 Job 包络；逐字段比较拒绝前后原根数据不变。
- 新世界初始化不擅自发布 taskJobs；当前 CRAFT3、HAUL1/2 保留，非法 CRAFT 载荷与函数注入拒绝。
- 实际 TaskPersistence.load 在格式拒绝前未调用任何恢复钩子。
- 实际 MembershipLifecycle 新世界事件绕过旧缓存，并拒绝未知格式；重复读取不重复执行 Job 检查，替换任务表重新检查。
- JobStore 35 项、task-save-runtime 71 项、membership-save-lifecycle 与 exit-save 12 项，以及原有 11 个核心套件全部退出码 0（计入重叠，共 15 套件）。
- 安装版 `projectzomboid.jar` Kahlua 宿主加载真实 JobStore/Registry，验证新根、未知账本保留、显式新根与只读检查：PASS；非接纳依赖为空替身，没有提供 next。安装 JAR SHA256：`e1a69eb743ede60b213a0fe7f8b83d4fcab773036d256cc4543a336f3b058a33`。
- 完整 preflight：退出码 0；LuaLS 0 error / 626 warning（未逐条审查 warning）；文档链接检查 0 错误。

复现宿主套件：配置 shared/client/tests 的 LUA_PATH，运行 `lua tests/lua/work-format-admission-test.lua`；其余套件命令同文件名。

## 未验证与范围

实机保存、退出、重新载入由用户执行，本轮未运行。检查范围为 Work 根版本、containers 表形状及 JobStore 原有任务契约；不是所有业务子账本的完整审计，也不声称磁盘原子性、异常退出零损失或性能提升。未修改历史存档，未迁移或清洗数据。并行 UI/人员系统修改排除在本轮提交之外。

用户随后收紧测试节奏：本轮已启动的全量检查完成；后续开发只做必要定向检查，正式实机前集中跑一次完整回归。
