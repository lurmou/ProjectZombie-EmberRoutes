# 0.22.0 按需配方链

日期：2026-10-22。基于experiment/modern-ae2-ui，保留另一位AI的d7c5b5a布局及实施期间新增的61c4abe三页界面改动。后者在仓储页引入c/capRatio作用域错误，本轮仅修其作用域与缺失容量值守卫，未撤销新界面。用户批准[设计](../../superpowers/specs/2026-10-22-production-chain-design.md)，主代理独立实施，无子代理。

## 问题与行为

原预检和Production只匹配现成物品，缺木板就停止，没有递归BOM。现在制作入口可先规划、制作中间材料，再继续最终目标。产物索引来自同一原版配方目录，不为原木/木模具写特殊分支。

真实安装脚本generated/recipes/recipes_carpentry.txt:340的Base.MakeWoodenIngotCastMold需要木板1、钉子1，保留锤1和锯1，Woodwork:2、AnySurfaceCraft。Base.SawLogs将原木1变为木板3。需要这些材料、工具、知识、技能和已登记普通平台均满足，不能把“有一根原木”宣传为独自足够完成模具。

## 模块与权威

- ProductionChainPlan：纯有界DFS搜索；分支复制模拟变化，失败回退；先取现成可用物品，再展开缺口。工具跨批复用、产出取整、富余及副产物参与后续需求，路径环路检测、根计入最多4层。不仅回退配方选择，也回退原料分配，避免可替代输入耗掉后继必需的稀缺原件。原版目录顺序稳定尝试配方，不承诺全局最优材料成本。候选库存只读共享，分支只复制变化；最多保留128个待尝试分支，被限额截断且未找到成功路径时报告规划限额，不能谎报必然缺料。
- ProductionChain：只读原版知识/技能/平台与分类箱原件适配。复用CraftingCatalog索引，不再建立第二个全目录扫描器；直接材料充足的新单先走原Supply匹配快路，不等待完整目录。库存扫描及纯计划分片推进。
- Production：整链沿用一个taskId和版本化chain节点，只运行一个节点；原ProductionActions保持原生效果、动作前后校验和未知提交门禁。所有节点继续按实际要求选择手持或普通平台。
- CraftRecord/LaborStore：可选chain格式1与held原件池，仍兼容原format3单配方记录。原料、已入库中间产物及工具持续归同一认领权威；活动资产从池原子移入当前节点，节点切换不释放父单。最终完成/取消才释放剩余认领。
- 库存变更/原件认领释放置脏，一次处理一个等待工人；缺料工单保留，补料后继续。手动暂停不因补料自动撤销。正常保存使用原恢复协议，完成节点不重做；读档仍沿原显式继续边界，不宣称强退零损失。
- CraftingPreview与制作页共享规划结果：现有数量仍显示真实数，前置供应以箭头/金色区别；显示步骤与最终目标，工单展示当前节点。缺前置配方知识时传授目标是那个前置配方，保持最终选择。

边界：只使用现有受支持的固定物品配方，不新增流体、可变数量、特殊工作站或回调动作适配；不取玩家背包。每个计划最多64个节点、40,000个搜索操作、20,000个扫描物品，原料认领和计划中间产出按256个原件的保守上界限制，超限明确阻断/未知，不默认为缺料或可执行。未做真实性能测量。

最低存量、自动伐木、跨NPC分配各节点、完整产业工种调度与滚动裁剪不在本轮。

## AE2参考

用户提供D:/Project/Applied-Energistics-2-main，本轮读取CraftingTreeNode、CraftingCalculation、CraftingSimulationState、ChildCraftingSimulationState及CraftingCpuLogic相关路径，核对LICENSE为LGPLv3。仅参考规划/执行分离、模拟状态分支回退、库存先用/缺口后制、等待产出推进的职责划分，Lua实现独立编写，没有复制Java源码。

该目录未取得Git提交号，以文件SHA256记录阅读截点：

- CraftingTreeNode.java：42A06AC6518F7C25CC30973EA941A5B7E5C80A7F401816C1278A1BA35EFD83A9
- ChildCraftingSimulationState.java：BA54E2017374C3D33F6D2DB7F7761BA2DF7C93C07D53107F05B1671F3ABEF5FD

游戏JAR仍为E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33；ZombieBuddy仍为EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2。用户现有PZ Optimization绘制替换不在本轮修改。

## 验证与实机边界

- tools/recipe-coverage.py：8个当前安装脚本IO样本，新增木质锭模具；脚本/标签及效果解析替身不等于原生执行验收。
- craft-probe-test.lua：637项（累计）相关宿主检查，包含整链取料、制作、交付、原件认领、前置完成后取消、制作中/提交后保存续工、缓存重建恢复、补料唤醒、前置配方知识定位和直接材料充足时不扫描全目录。原生Lua动作运行，但引擎效果、库存、移动和保存宿主仍是替身。
- production-chain-test.lua：18项纯规划检查（含材料分配回退修复前复现）；crafting-catalog-test.lua：7项目录边界检查。
- CN/EN各512项据点页宿主检查与33项物流检查，新增前置供应状态、步骤显示和定向传授检查；不是游戏渲染验收。
- 最终工作区Lua preflight通过：97文件，无阻塞错误；LuaLS保留3项既有信息性警告，日志preflight-final-workspace-0.22.0.txt。构建和release-check通过（error 0 / 提示0）。没有运行真实游戏，也未验证新的帧耗/吞吐指标。

发布包build/packages/EmberRoutesProbe-0.22.0.zip在上述并发改动合入后与最终工作区104个文件逐字节核对通过，SHA256为AE5E3F1FFB65B4B4F803D12B8C5D2B9F3247DC479BC0062E7002BD4442D87D6F，原始结果见build/logs/package-equality-0.22.0.txt及build/probe-build.json。

只需日常实机确认一次用户案例：分类箱放原木、钉子、锤、锯，满足技能知识并登记平台，委托木质锭模具1件；看是否先锯原木再制作、两块余板归仓、原工具归还。不要把本记录的宿主通过改写成“实机已通过”。

## 制作链预检界面停留核查

2026-10-22 实机日志 console.txt 记录 CraftingDraft.set 在原第997行拼接 `IGUI_ContainerTitle_` 与布尔值 true，触发 `__concat not defined`。节点 surface 来自 ProductionRecipe.isAnySurfaceCraft，是是否需要普通表面的标志，不是容器名称。CraftingService.notify 随后移除失败观察者，界面留下 CHECKING，不能据此判断缺料或规划未完成。

本轮核查时工作区已有并行修正：CraftingDraft 按布尔值分别显示平台制作、手持制作，字符串兼容分支才查询容器翻译；保留该修正和成对翻译。本轮补充同一条制作链包含 surface=false/true 的定向断言，确认不会中断投影、两类标签正确且允许下单。CN/EN 各526项据点界面及33项物流宿主检查通过；原生渲染和修复后实机尚未验证。静态检查原始输出见 build/logs/crafting-badges-preflight-full.txt；初次受沙箱限制的记录单独保留在 crafting-badges-preflight.txt。本轮不重建历史发布包，不宣称旧ZIP包含该UI修正。

完整 preflight 最终通过（98个Lua文件）；文档链接检查通过。修复需重新加载游戏Lua后验证，运行中的旧失败订阅不会因磁盘源码更新而自动恢复。
