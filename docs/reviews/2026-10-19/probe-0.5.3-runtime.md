# 0.5.3 单人存档实机反馈与证据

日期：2026-10-19。版本：EmberRoutes Probe 0.5.3；游戏42.21.0、ZombieBuddy 2.3.4，沿用[评审基线](baseline.json)。本轮归档日志，未重新计算安装JAR哈希。未修改代码或重新打包。

结论：结合用户实机反馈，正常单人保存/恢复主流程通过；第11步样本清理保留未确认。仅覆盖当前单NPC探针，不外推崩溃无损、完整身体/技能状态、MP或正式劳动系统。

## 用户反馈

- 前述问题已解决，测试至第九步成功。玩家离开约20格后退出重进，NPC起初未出现，点击重试恢复后出现在原位置。
- 第10步跨世界测试成功。
- 第11步未理解如何测试，已打印日志；不能记为通过。
- 第12步成功，整体基本通过。

第九步行为符合距离保护和显式重试设计，但当前console与本轮检查的DebugLog中未检出RESTORE_TOO_FAR或CHECKPOINT_PENDING；此情境依用户反馈，不补写独立门禁日志结论。

## 直接日志证据

来源为本机console.txt，按版本前缀筛选并保留原行号：[日志摘录](probe-0.5.3-runtime.txt)、[来源元数据](probe-0.5.3-runtime.json)。

| 项目 | 已观察证据 | 边界 |
|---|---|---|
| 人物/物品恢复 | f1 CHECKPOINT_RESTORED，UUID为8a52627b-1bba-42fd-8d2b-0f193e33cc92，items=3，HOLD，位置7960.211,11405.789,0 | 不据一次记录证明所有退出方式 |
| 搬运中正常保存 | f9423 HAUL BATCH CANCELLED SAVE、FIXTURES_CLEANED、CHECKPOINT_SAVED，items=3、nativeBytes=4183、home=true | 本段搬运主动中断，没有完整17步PASSED，不作为新一轮完整搬运验收 |
| 存档样本 | f12456 SAMPLE_PASSED，failures=0；包693070104、铅笔1322296177、水1437127019 | 样本核对不等于样本清理 |
| 跨世界 | 有CHECKPOINT_EMPTY及其后同UUID恢复，与第10步成功反馈相符 | 日志没有A/B世界独立情境标签；具体切换顺序依用户反馈 |
| 显式删除后保存/重进 | f16584 REMOVED；f17125 CHECKPOINT_EMPTY explicit removal/death committed with next world save；后续启动f1 CHECKPOINT_EMPTY no saved NPC | 确认本轮正常删除/保存；未测试异常退出 |

## 第11步说明与处理

在右键EmberRoutes菜单中选择“人物存档”的“清理验收样本”，预期提示SAMPLE_CLEANED，只移除测试书包、铅笔和嵌套水瓶，保留其他物品。样本包穿在身上时先卸下；包中放入其他物品时须先移出。

当前Samples.cleanup成功只返回SAMPLE_CLEANED供界面显示，没有独立成功日志。本轮打印状态与SAMPLE_PASSED不能证明已执行清理，也不能确认其他物品保留。因此此项维持未确认，不阻塞正常存取主流程验收；第12步已删除NPC，无需为此重新创建人物补测。以后使用存档样本时顺带观察即可。

实现原因与本地检查见[靠近点修复记录](probe-0.5.3-approach-fix.md)，完整操作见[集中测试](../../testing/single-player-persistence.md)。本轮只更新验收文档，检查使用doclink，不以重复逻辑测试替代实机结果。
