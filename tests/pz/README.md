# B.5 PZ 实机验收覆盖包

> 日期：2026-11-01｜状态：QA 候选，实机未运行，B.5 未关闭。

此目录只用于 QA 包，不进入正式模组构建。正式生产源码仍冻结；合成 CRAFT 任务只验证持久化契约，不执行 NPC 动作，不代表 Production 已切换。

## 制作与边界

运行 `pwsh -File tools/package-b5-qa.ps1`。脚本从当前 Git HEAD 导出正式模组和本目录两个覆盖文件，复用哈希匹配现有构建报告的 Java JAR；输出独立 zip、逐文件 SHA256 manifest，不覆盖游戏安装、不发布工坊、不带入工作区 UI 改动。Java 未重新编译；依赖与版本不符会拒绝打包。

夹具使用真实玩家库存创建四支 Pencil，建立两个诊断 Job，并注入可持久化的冲突事实。容量 3/4 是隔离账本测试额度，不是仓库实际负重验收。只接受空任务/隔离账本；部分准备失败会保留诊断责任，不自动清除现场。请仅在一次性新世界使用，不能用作长期游玩存档。

## 一次集中实机操作

1. 使用独立 QA 包及对应 ZombieBuddy 版本，只启用一份 EmberRoutesProbe（不能同时加载正式与 QA 同 ID），开启游戏 Debug 和 CarrierProbe，创建一次性新世界；不要先派工或生成 NPC。原版右键 Debug 子菜单内选择 **B.5 验收 → 准备持久化样本**。日志应出现 `B5_ACCEPTANCE OK PREPARED_SAVE_QUIT_AND_RELOAD`。
2. 正常保存，完整退出到桌面，重新启动游戏载入同一世界。选择 **完整退出重进后检查**；日志应出现 `B5_ACCEPTANCE OK COLD_BOOT_PASS 1 capacity=3 originals=protected`。
3. 再次正常保存，完整退出到桌面并重新启动，载入同一世界，再检查；日志应出现 `COLD_BOOT_PASS 2`，容量和保护结果一致。
4. 保留世界名称、QA manifest/sourceCommit、两次启动及检查日志，交外部 AI 独立判定。任何 FAIL 都保留现场，不以重建 Lua 表、reloadLua 或手动清缓存代替实际重进。

同一 Lua 会话重复点击检查会返回 `B5_SAME_LUA_SESSION_NOT_A_COLD_BOOT`；计数只是防误用辅助，不是磁盘保存证明，仍需完整启动/退出日志。检查失败不会增加 coldBoots。

## 检查内容与未验证项

检查合法新 claimId、原始身份与冲突证据、20 条合法重复隔离事件、三件原件的 SYSTEM_QUARANTINE、容量 3 的冷启动恢复与同实例重复恢复幂等、非法 Evidence 解除被拒绝且 Job revision 不变、四件样本真实 ItemID 保留。未知历史格式的拒绝沿用独立门禁专项结果，不在此世界破坏性注入。

宿主测试 `tests/lua/b5-acceptance-fixture-test.lua` 只验证夹具与真实 Store 的接缝及菜单安装，不是实机证据。既有完整回归结果不覆盖 native UI、实际磁盘和游戏内加载，不能提前宣布通过。LuaLS 757/626 是不同全库检查的汇总，不相加；原工具输出没有保留逐条诊断，本轮未宣称 warning 已逐条复核，后续需保留明细按风险审查。

Codex 主导准备、打包和进度；按此前选择由本地用户操作游戏，外部 AI 负责独立审查与结果判定。若更换实际操作者须明确记录。B.5 尚未关闭，Stage C 尚未开始。
