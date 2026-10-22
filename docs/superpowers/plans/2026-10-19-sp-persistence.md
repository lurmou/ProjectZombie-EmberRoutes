# 单人 NPC 保存恢复实施计划

**Goal:** 0.5.0 提供正常世界保存、单次恢复与故障阻塞，保留稳定 ID 和原版实例状态。

**Architecture:** Java 编解码封装与原版人物序列化分离；Runtime 持有唯一实体；Lua 负责取消任务、夹具清理和指令恢复。

**Tech Stack:** Java 17 / 当前游戏 JAR / Lua 5.1 / ZombieBuddy。

**Spec:** [设计](../specs/2026-10-19-sp-persistence-design.md)。按本项目规则由当前代理顺序实施，不派生代理，不擅自提交 Git。

## 检查重点

损坏或旧快照不可回退生成；正常存档不能再次删除活人物；失效夹具不能进入人物快照；恢复失败不能留下半附着实体；世界切换清理阻塞必须保留所有权。

## 实施任务

- [x] `ProbeCheckpoint.java`：纯 Java 有界封装、元数据验证与校验和；增加独立纯测试并接构建入口。
- [x] `ProbePersistence.java`：当前世界 GlobalModData 接入、原版字节保存/加载及递归库存身份验证；查证原版保存调用与方格保存范围。
- [x] `ProbeRuntime.java` / `ProbeNpc.java`：唯一恢复、生成门禁、安全附着、死亡/删除标记与诊断；保留退场协议。
- [x] `Boot.lua` / `Companion.lua` / 新 `Persistence.lua`：保存交接、恢复一次、驻点和意图恢复、菜单及 CN/EN 文案；增加边界测试。
- [x] 构建 0.5.0，运行 Java/Lua、preflight、release-check、doclink；记录原始输出。
- [x] 更新 HANDOFF/BACKLOG/README，提供一次会话加退出重进的集中测试说明，实机状态写未验证。

结果：300项独立断言通过；preflight、release-check及9份文档doclink通过。游戏原生保存/恢复与十二项实机验收尚未运行，不能因以上勾选记作实机通过。
