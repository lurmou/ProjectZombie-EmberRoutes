# EmberRoutes 接力说明

> 更新：2026-11-06｜本文件只维护接手顺序，不记录版本流水。

## 接手顺序

1. 阅读[项目必读](../AGENTS.md)，确认单人优先、完全不要兼容代码、稳定身份、唯一资产裁决和原件保留约束。
2. 阅读[BACKLOG 的 NPC 架构执行记录](BACKLOG.md#npc-架构执行记录)，确认当前阶段、阻塞、下一步和验证边界。该处是唯一当前进度表。
3. 修改代码前读[开发规则](development-rules.md)；按[任务文档导航](INDEX.md)选择本轮相关设计与计划，不要求全文加载历史资料。
4. NPC行为工作必读[唯一架构](superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)；公共工作另读[统一任务协议](superpowers/specs/2026-10-23-unified-task-dispatch-design.md)。
5. 评审或新设计先读取[在线唯一需求](https://docs.google.com/document/d/1aTOBrzZvh_iCDkv045HNAV13i7vNf7OHk6E_sE7TWNM/edit)。无法读取须说明；本地需求快照不能代替最新在线正文。用户明确批准的阶段范围按决定执行。
6. 核查当前工作区和相关源码。不得清理其他聊天或用户改动，不从旧计划重新实施已接入的功能。

## 判断依据

需求以在线正文及用户明确决定为准；NPC架构以唯一架构为入口，从属设计细化契约；计划描述工作步骤，不能证明实现；证据分别记录静态、宿主、实机、故障恢复和性能结果。遇到文档矛盾应对照当前源码、明确决定及对应证据核查，不能仅按文件日期决定架构变更。

保持中文简短沟通，在授权范围持续完成；不默认启用子代理。成组交付可玩流程，避免把内部切片逐个交给用户测试。

## 本轮接力（2026-11-11）

- 职责身份 spec 与方案 A 的对齐已做完，完整结论在 BACKLOG 的 2026-11-11 条目；本文件不复制细节。
- main `7ae33f4` 已合入 P0 三项（SupplyEstimate、Hauling retained、SelfCare 门禁），各在独立分支推过；spec 对齐本身只改文档，分支 `p0-spec-alignment`。
- 下一步 OPEN 项（按 BACKLOG 条目）：SelfCare `haulOnDuty` 补丁可删；`blocksDecision` / L591 移除须先移走恢复逻辑；会话内退避未做；恢复对等唤醒须先设计；Forager 三阶段重构是长期项。实机复测 UNVERIFIED。

## 历史查询

历史构建探针与阶段审查记录已完整归纳在 Git 提交历史中（可通过 `git log` 追溯）。历史中的“当前”“下一步”、分支回退建议与旧验收状态均不能直接作为本轮指令。

结束本轮时原位更新BACKLOG执行表；长日志与详细验证写对应证据，并从导航或待办链接。不再向本文件和README复制进度。
