# 床/沙发使用策略与个人休息

日期：2026-10-24｜版本：0.24.3集成候选｜游戏未运行。

2026-10-24用户后续修订：床位选择应覆盖NPC所属据点，不受NPC附近10格限制。下文“实际行为”的同层半径10格是当前旧实现事实，后续须改为据点范围床位候选；本轮仅核查并记录修订，尚未改代码。目标是据点内设置床位即可纳入候选，保留策略、占用、加载和可达性检查，以共享索引及有界查询维持性能。

用户批准附近设施选择、唯一预约、到位重验，并新增指定某NPC或禁止NPC的硬策略；实施从属于[唯一架构5.3](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)，见[实施计划](../../superpowers/plans/2026-10-24-repose-sites.md)。在线唯一需求本轮成功读取，正文SHA256为1E802DFE03A43437C77DC8EF5D04A2E38EC9AE9970A71D349B302B9EFE2EFB08，与既有基线一致；本轮细化依据用户对话决定。

## 实际行为

- 据点内右键床/沙发→本模组→休息设施使用策略。公共为默认；专用绑定稳定npcId，成员缺席不自动公共；禁止NPC仅限制NPC，玩家可正常使用。整件家具的任一部件配置均修改同一策略，旧菜单版本不能覆盖新策略。
- 同层半径10格有界搜索，复用扫描/寻路预算及5秒共享观察缓存（最多1024格）。按原生BedType/座位能力识别，不按中文家具名称猜测。候选只读，最终准备时登记整件/部件稳定ID并预约。
- 多格家具按原版sprite grid归并；未验证独立睡位时整件单睡眠预约，休息仅占所选部件。个人任务仍走唯一JobStore和LaborStore声明，不生成公共Order，也无永久自理工单历史页。
- 准备、准入、移动和休息均重验策略版本、原件身份、据点权限、实际玩家占用及唯一声明。实际玩家睡眠使用床引用补足原生isFurnitureOccupied仅检查坐姿的缺口。不操作玩家队列或睡眠状态。
- 移动至可达邻格，再进入受控Java家具休息/睡眠。策略修改、拆床或已知路径失败使旧尝试退出，确认醒来/身体停止后释放原声明；失败位置冷却10秒再重选或地面回退。未知效果保留责任，不通过超时把正在使用的预约转让。
- 持久化只保存稳定家具/部件ID、位置、策略版本及自理事实，不保存原生对象句柄；同坐标替换件不继承旧预约。家具ModData策略随原版世界保存；真实世界保存重进仍待验收。
- Java入口沿用原版床引用、床质量、isResting/isAsleep与SleepingEvent；观察原生Stats达标，不直接加耐力或减疲劳。停止位增加床引用，退出清床引用。启动要求新家具控制接口，需完整重启游戏加载新Java。

## 核查与验证

安装基线PZ42.21.0，projectzomboid.jar SHA256 E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33，ZombieBuddy2.3.4，由build-probe核查。检查当前安装ISWorldObjectContextMenu、ISRestAction、SleepingEvent与IsoObject字节码；原始javap片段在build/research/repose-IsoObject-javap.txt，在线需求导出在build/research/requirements-repose-sites.txt。修改前modscan未见整文件路径冲突。

安装Kahlua定向通过：家具身份/策略/占用/菜单24项、实际个人树和声明生命周期集成12项、REST/SLEEP10项、受控Runtime57项、启动15及32项、保存编排61项；另相关生活组合20及服务9项通过。新集成覆盖策略改变后先醒来再释放、过期会话不能干扰后继、真实树观测疲劳完成、准备后尚未启动的准入拒绝释放声明。身体、世界家具、路径与Stats均使用替身，保存编排通过不等于世界落盘成功。

0.24.3 Java构建及相关Java测试通过。正式CN/EN界面各713及物流页面33项通过。release-check为0错误/77提示，归档158文件与当前Contents/mods逐项SHA256一致。原始日志：build/logs/repose-sites-{build,release,package,ui-cn,ui-en,save}.txt；最终家具回归见repose-sites-final-regression.txt。

完整preflight最终退出0，各层通过，原始输出repose-sites-preflight.txt。尾部收口修正将失败目标排除固定在本轮扫描开始，避免分片扫描超过10秒冷却后反复选择同一路径；最终源码另跑Lua lint（151文件0错误/1条既有比例布局提示）和结构检查通过，新增回归覆盖冷却在扫描中途过期，最终包已重新构建核对。原版ISFluidEmptyAction.lua的0.0f仍是结构工具的已知解析覆盖缺口。文档6文件0断链，空白检查通过；对应日志repose-sites-{lua-lint-final,structure-final,doclink,whitespace}.txt。

## 保留边界

家具坐卧动画尚未适配；实际NPC可能在家具旁使用原生休息/睡眠状态，不把此实现宣称为已躺在床上。原生疲劳恢复、床质量实际影响、玩家交互、正常存读及游戏内两NPC争用均未验证，统一纳入[单份P2集中验收](../../testing/p2-runtime-acceptance.md)。不宣称联机、强退/磁盘故障安全或真实规模性能通过。

保留同版本并行调度性能、UI及既有P2/工单清理改动，未提交混合工作区或发布工坊。
