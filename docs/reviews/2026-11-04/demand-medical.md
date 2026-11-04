# 需求与工单分离、个人医疗：0.29.36

日期2026-11-04。基线为远端c1229b765f1a8bc111d7cb2bdd2c8e471c6a5bc4；工作在codex/demand-medical独立工作树。原phase-3a-consolidation工作区及其未提交改动保留，不整体搬入旧Java内核。在线唯一需求已读取v4.0，依据用户批准的“基础需求页→工单页→医疗自理”范围实施；没有修改在线需求。

## 实际依据及取舍

安装游戏JAR SHA256：E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。ZombieBuddy2.3.4；安装环境存在pzopt/aot/pzopt.jar的IsoPlayer覆盖，构建基线检查已包含该实际加载顺序。

参考只读D:/Project/ProjectRemnants/NPCFW.jar，SHA256：5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E。对当前根JAR重新javap，不用旧反编译树代替分支证据：SelfCareCoordinator.tick先尝试医疗/tryBandage后吃喝；tryBandage找未包扎伤口及随身干净材料，prepareForSelfCare暂停工作、社交及闲暇；专业MedicalSession包含FETCH_MOVE/FETCH_TRANSFER、ACTION、RETURN_MOVE/RETURN_TRANSFER，tickMedicalAction等原版动作退出后重评伤口，同一治疗无进展最多3次。finishMedicalSession先尝试归还借用物资。

参考Lua NPCFW_SelfCareActions.lua:297的NPCFW_queueSelfCareAction，包扎调用ISApplyBandage:new(character,character,item,bodyPart,true)，包内材料通过ISInventoryTransferAction移入主库存；其:372的NPCFW_queueMedicalCareAction在移除敷料时传nil物品及false。它显式require XpSystem/ISUI/ISHealthPanel，同时会强制部分动作时长。我们采用相同原版动作入口和必要辅助加载，保留原版时长/start/update/complete/perform/stop；不复制其TaskRunner或伪造工具。

安装原版media/lua/shared/TimedActions/ISApplyBandage.lua:50的start负责Bandage动画、BandageType及EventBandage；:90的perform清理声音/面板并退出队列；:101的complete调用SetBandaged并消耗真实材料，移除旧敷料时创建原版实际产物，非可重复使用失效敷料也可能立即耗尽。因此“到了位置”“有动画”“物品不见了”都不能独立证明治疗完成。

## 实现和责任闭环

- 需求：[DemandMonitorService](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/DemandMonitorService.lua)在Ledger.view权限检查后只读投影已有清洁事实、最低库存规则、医疗观察；稳定问题ID去重。取消执行不会抹掉缺口，未知效果仍为需核对。清洁以据点汇总，医疗以成员汇总多个伤口。清洁执行与工具归还保留原责任，不因隐藏UI而删除。
- UI：[DemandPage](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/DemandPage.lua)复用OrderMonitorPage、CachedList、Cards、FilterChips和PageLifecycle。独立只读Service投影，无生产/暂停/取消命令；同步watch不再紧接着重复初始投影，切页释放订阅并阻断晚回调。普通工具保管移入人员详情，异常或实际归还按成员合并。
- 观察：[HealthAssessment](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/HealthAssessment.lua)读取最多64部位，工作资格按NPC/世界缓存1秒；[MedicalCare](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/MedicalCare.lua)复用SelfCare既有观察节拍，不新增全员tick。外部威胁和持续出血分开；急救优先吃喝，不被RECENT_DAMAGE一律拒绝。低总健康但已包扎的浅伤可重新工作，深伤保留专业处理阻碍；未知身体能力拒绝。
- 创建认领：[SelfCare](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCare.lua)沿Record.begin、SelfCareResources、claimPersonal/Commit提交；材料先随身，再按既有成员资格和仓储权限寻找。生产/其他任务已声明原件不可偷用，缺药等待5秒再扫描，不创建公共取料工单。[MedicalRecord](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/MedicalRecord.lua)限定版本、部位、尝试ID、原件ID、阶段、效果及最多1件原版移除产物。
- 正常释放：[MedicalActions](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/MedicalActions.lua)从主库存原件构造原版动作；失效敷料先原版移除再包扎，核对部位和实际消耗后持久化正向回执，仍等待原版perform/队列退出。产物按真实ID扩展同一Claims；SelfCareCustody.returns确认归还后，SelfCareExecution.finish/finishPersonal才释放责任。原工作按既有TaskResume或普通健康恢复重新仲裁，手动暂停、控制不明和业务权限守卫保留。旧物流通用DRIVER_UNAVAILABLE暂停也须经新鲜身体/成员/实际启动校验后才可恢复。
- 异常打断：[SelfCareExecution](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareExecution.lua)的stopAdapter保留原生stop、身体停止确认、效果和持久化分离；[SelfCareReconciliation](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/SelfCareReconciliation.lua)不重放未知医疗效果。只有成功回执可说明材料已消耗，缺原件不能冒充成功。已有个人任务待还时，StudyRelief可在同一Session用随身材料急救，独立医疗回执不会覆盖旧借物；不为急救释放未还书/食物。

## 验证记录

- 构建：358 Lua普通/Debug编译无失败；Java release17按固定安装基线编译，身体/检查点/存储/读取/派工门禁通过；实际Java容量提交17项、DEC-003内核20项通过，候选包EmberRoutesProbe-0.29.36.zip生成。
- 定向16套全部通过：medical-service 12、medical-native 12（加载安装版ISApplyBandage）、medical-loop 16（实际JobStore/Claims/Commit/执行与恢复，原生身体替身）；demand-monitor 13、demand-page 59；原监控、个人自理、清洁/尸体、接近点/退避、烹饪/阅读入口回归。新增供需、争用、原版perform等待、效果已生效但perform前打断的原版stop清理、停用前中断、换药产物、冷回执/未知效果和受阻借物随身急救均覆盖。原生动画/寻路未因此验证。
- 需求页真实CN/EN翻译表在安装Kahlua各59项通过。宽度/中文文本、Tooltip60、Lifecycle558和页面生命周期194通过；完整旧UI脚本仍在settlement-storage:76失败，两种语言均不能报告全UI通过。
- 集中历史回归：使用实际Java内核，--all共210套，139通过、71失败。对远端c1229b7同命令审计（审计工作树另含5份local-regression探针）后，共同199套远端失败74、本轮失败71，无新增共同失败；容量契约和两份自理宿主修正后通过。71份历史失败仍存在，包括旧资产/运行时/烹饪宿主与settlement-tabs旧仓库列表夹具；这不是全项目验收通过。原日志在独立工作树build/demand-medical-final-regression.log与基线审计日志，可按下述命令复跑。
- 旧capacity测试调整为远端已切换的失败分类、收缩先于CAS及保留KNOWN原记录契约；没有为测试回滚生产内核。两份自理测试保留实际Java桥和成员资格，公共工作/库存测试显式提供健康能力；旧95阈值断言改为未处理伤势拒绝。没有删除失败套件。
- Lua静态lint：358文件0错误、12既有比例布局提示。pz结构lint及prerender规则、候选规则检查通过；modscan无整文件替换冲突。CN/EN键集一致；release-check仍有PageLifecycle:22/:347两处既有错误诊断print，另22处既有硬编码中文提示，发布门禁未全通过。完整preflight首轮退出1：新增模块误用PZ未声明的package全局，已改用正常模块依赖及观察者阻碍事实，单项Lua lint复核0错误。该轮其余阶段全部完成通过，包括LuaLS 0 Error/775 Warning及索引新鲜度10项；没有将首轮命令退出码改报为0，也未重复耗时的全量LuaLS。
- Git diff按trailing-space/space-before-tab无错误；本机core.whitespace另配置indent-with-non-tab，会对仓库既有空格缩进风格报错，不进行全库格式改写。

复跑：从本工作树用最新build/compile-*/classes和安装游戏目录组成classpath，执行tests/java/KahluaLaborTest.java --java-labor --java-dispatch --java-job-data --keep-going --all；先运行tools/build-probe.ps1生成对应类，勿使用原目录旧JAR替代远端内核。定向清单见build/demand-medical-targeted.log所列16套及新增tests/lua/medical-*-test.lua、demand-*-test.lua。

## 未完成及实机边界

未进游戏，未做真实包扎动画/跨楼层寻路、保存重进/强退、多NPC性能或联机验收。专业医生、缝合、异物、夹板、撕布配方尚未实现。已暂停的旧个人借物如无法归还，紧急分支只使用随身材料；此时再次借公共急救材料涉及第二来源责任，未在首批扩大。不能称完整医疗系统完成。

用户指定五项作为下一步独立任务：双手拖把和清洁剂组合、尸体接近/方向/动画、放下效果和终态、自动返回点/35秒限制、清洁/托管行数。选择性集成旧修复不等于实机验收；保留待办，不在此关闭。原游戏加载目录仍是用户原工作树，独立候选包须按正常安装流程切换，不能把独立工作树构建说成游戏已更新。
