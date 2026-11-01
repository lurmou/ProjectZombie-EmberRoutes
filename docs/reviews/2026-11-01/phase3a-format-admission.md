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

## 独立 B.5 QA 候选（实机尚未执行）

基线 `e3c2d54`，使用 [QA 说明](../../../tests/pz/README.md)及 `tools/package-b5-qa.ps1` 从提交导出。QA 夹具只在覆盖包内进入原版 Debug 子菜单，正式构建不包含它。实际创建四件 Pencil 和合成诊断 Job，用于验证两次保存重进后的身份、隔离及容量，不是 NPC 制作执行证明。

定向宿主：`b5-acceptance-fixture-test.lua` 通过两次模拟重建、同会话拒绝、真实 ID 缺失失败、序列化事实检查及菜单接缝；明确不代替 PZ 磁盘。包内 341 文件与 manifest/zip SHA256 一致，原正式源码与 Git blob 逐字节一致（声明的 QA 翻译除外）；CN/EN 原值保留、QA 键集一致。Java 复用既有构建报告匹配 JAR，未重新编译，未安装或发布。

ZIP SHA256：`d702547bdfa7879f9b4dfa3b650183e3994802e4e621d758b5170fa847f33fd9`。

**release-check 未通过**：退出码 1，基线 PageLifecycle.lua 两处 print 故障日志触发发布检查，另有 23 条既有硬编码中文提示；本轮不修改并行 UI。此为 QA 候选，不能标为正式发布包。原 LuaLS 输出仅保留汇总及性能日志，无法从中恢复逐条 warning；没有将 757/626 相加或宣称逐条审查完成。后续完整检查应保留诊断明细，按本轮风险审查。

B.5 独立复审、PZ 实际磁盘保存/退出/重进仍待完成，Stage C 保持冻结。Production 前置原生效果提交契约只补了草案，未修改生产代码。
