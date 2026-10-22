# 0.17.2：制作停工定向诊断

> 2026-10-21｜本地实现；原停工根因未确认，新增实机未验证。

用户实机日志在17:14:21及17:15:18两次记录NATIVE_ACTION_STOPPED、uncertain=false，无COMMITTING；期间一次显式归还已CANCELLED。原日志没有动作阶段/原版拒绝原因，不能据此认定平台距离或瑞士军刀不支持。

本轮保留分类仓储、原件认领及恢复协议，仅在动作适配边界区分TRANSFER/CRAFT与步骤，保留首次拒绝原因；失败时一次性记录位置、输入是否在NPC主包、原版输入允许、工具类型/耐久/锋利度、负重余量和最多8个已应用输入ID。正常启动记录CRAFT_STARTED；不每帧输出，不放宽原版条件，不强制制作。原版配方拒绝与额外/替换原件分别为NATIVE_RECIPE_REJECTED和NATIVE_INPUT_SET_CHANGED。诊断读取不重新提交制作；COMMITTING之后不重算输入。

独立确认并修复NpcDebugMenu物品输入框：当前安装ISTextBox:new第7参为target，第9参为玩家整数索引，第10参为回调param1。改为actor、actor:getPlayerNum()、npc，保持原菜单及回调行为，修正日志的expected argument of type int, got IsoPlayer。

## 检查与使用

仅运行制作相关Kahlua夹具，共103项检查通过，新增覆盖原版启动拒绝、输入集合改变、首个原因保留及单次失败快照；原版HandcraftAction为安装Lua，原生逻辑/容器/移动/队列仍为替身。构建和固定JAR检查通过，原始输出见build/logs/craft-start-diagnostics-0.17.2.txt、build/logs/build-0.17.2.txt；必要门禁另存preflight-0.17.2.txt。未运行全历史测试或启动游戏。

重启游戏加载0.17.2；旧单若持有原件，先用已有显式归还入口闭合，再下一次木叉试制。仍停工时直接看同一单的ACTION_REJECTED与PAUSED，定位具体拒绝分支。不要凭诊断版已完成就声称原停工已修复。

[实施计划](../../superpowers/plans/2026-10-21-craft-stop-diagnostics.md)；[既有分类制作实现](probe-0.17.1-classified-crafting.md)；[简短实测说明](../../testing/single-player-native-crafting.md)。

最终preflight通过，release-check零错误/提示，相关5个文档链接检查通过。0.17.2发布包86个文件逐字节与模组目录一致，核对记录build/qa/probe-0.17.2-package-check.json。上述均为本地检查，不代表实机停工已排除。
