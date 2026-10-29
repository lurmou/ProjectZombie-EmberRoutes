# P3.5 闲暇、徒手锻炼与双人社交实现记录

> 日期：2026-10-24｜交付版本：0.26.0｜仅单人。本轮开发检查与实机结果分开；不记P3或P3.5已完成游戏验收。
> 依据：[设计1.1](../../superpowers/specs/2026-10-24-p3.5-leisure-social-fitness-design.md)、[实施计划](../../superpowers/plans/2026-10-24-p35-leisure-social-fitness.md)、[来源核查](p3.5-leisure-design-review.md)。

## 已接入

- 复用SELF_CARE个人Job、TaskRuntime/TaskController、原件声明与BT，不新增每工种调度器。新增LeisurePolicy/Record/Service及动作模块；活动记忆和游戏时间冷却保留在同一版本化个人payload中。
- PublicWork可对正在闲暇/研习的成员继续做不认领的候选预检；发现可执行工作只请求旧活动收束，停稳和归还完成后重新正常认领。真实自理、未结归还和UNKNOWN不能借此绕过。每NPC有界逐步观察完整工单集合，未加载/观察未完成不当作无工作；沿用共享预检预算。
- 原件消遣阅读复用LibraryIndex/ISReadABook与借还，区别技能研习资格；小说及符合原版消遣条件的报刊支持原生已读身份。阅读媒体不打开玩家媒体/地图UI，不额外发身心收益。
- 主背包真实香烟与匹配火源统一声明，绑定原版动作的特定火源；记录启动耗材、结束/部分消费。仅适用Smoker，不借用其他任务原件，不重复点火或重复消费。当前白名单为Base.Cigarettes/CigaretteSingle/CigaretteRolled；不宣称任意模组烟草自动适配。
- 原地观察、据点内短距离散步、门窗附近观察使用受控移动及等待动作。SettlementFacilities的同一共享扫描补充门/窗特征，ReposeSites继续只接受床/座位能力。原对象拆除后失效，不自动开关门窗或点燃营火。雨天/天气未知不选室外接近站位，目标地块排除楼梯/门口和非参与者占用。
- 双人主动邀约/唯一参与登记、双方分别授权、各自到位屏障、同层/视线核验、35现实秒接近上限、面对面手势/气泡、一次有界身心收益及独立取消/释放。晚间仅提高闲暇邀约概率，不越过工作层。最小版选择直接结束，未强制增加告别动画。
- 徒手白名单沿用原版ISFitnessAction构造/重复经验及负担，适配AI输入、UI常量、迟到回调和currentExe清理；停止/完成不调用原版玩家倍速路径，不全局改写setGameSpeed。5游戏分钟训练上限，成功后12游戏小时冷却；身体与待发作酸痛资格先过滤。这些为保守初值，不是平衡实测结论。
- 原生停止掩码新增Fitness/currentExe与PlayerEmoteState，停止仅请求结束、等待真实状态退出才交权。Java新增只读社交距离/视线核验，不授予额外控制权。
- 保存沿用现有屏障：已结闲暇保持IDLE，未完纯闲暇读档取消而不恢复半段动作；效果提交意图未结进入UNKNOWN。阅读原件责任仍沿用P3，已发生的原版锻炼/消费不补发。正常保存不等于强退跨文件事务。
- 人员详情及监控显示具体闲暇活动，短语与状态CN/EN成对。

## 与计划的接口收敛

计划中的公开probeIdle没有另建：只读探测收敛到现有PublicWork私有候选流程，用careProbeWork/leisureWorkReady连接个人服务，避免第二套工单规划；真正认领仍只有原入口。SocialCoordinator实际接口为advertise/invite/accept/view/arrive/cancel/release；不直接操作任何身体。保存分支扩展现有SelfCare.prepareRecovery，不新增独立保存事件。新增LeisureTimed和LeisureSmoke分别隔离原生队列生命周期及耗材语义。

## 开发验证

| 检查 | 结果与证据 |
|---|---|
| Java构建、安装基线/会话/库存/编码相关门禁 | 0.26.0构建成功；build/logs/p35-build-delivery.log；原生游戏未运行 |
| 安装Kahlua定向验证 | 16个文件通过，见build/logs/p35-kahlua-delivery.log；包括7个P3.5用例及公共工作、P3阅读、自理、共享家具、身体控制和保存相关回归，原生host mocked；另有2文件会话/停止补充通过（build/logs/p35-runtime-supplement.log） |
| CN/EN UI宿主 | 均通过，build/logs/p35-ui-CN.log、p35-ui-EN.log；实际ISUI/输入与游戏渲染未运行 |
| Lua preflight | 全部通过（含结构检查与LuaLS），build/logs/p35-preflight-delivery.log；原版Fluids/ISFluidEmptyAction.lua的既有解析例外由工具单列，不计模组错误 |
| 文档链接 | 交付前doclink，见本轮检查输出 |
| 原生动画/经验/酸痛/倍速/消费 | 未实机验证 |
| 正常保存重进、强退与性能规模 | 未验证 |

定向覆盖：资格/冷却、无新鲜无活观察不发闲暇、工作唤醒而不提前认领、配对冲突/到位/过期代次、原件移动、火源部分消费及重复启动、锻炼旧回调、真实Job/Claims/BT/停止适配、读取恢复时不续播与UNKNOWN隔离。逻辑替身没有证明引擎动画事件必达或原生状态必能退出。

## 基线与适用限制

ProjectRemnants参考根JAR SHA256：5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E；当前PZ及动作Lua基线见来源核查与构建报告。pz ask核查ISFitnessAction/IsoGridSquare.canReachTo，均有规范覆盖缺口，结合直接安装版Lua及javap；modscan发现52处原版替换，扫描总览不代表运行中的全部补丁兼容。未把第三方实现当作本项目实机证据。

安装JAR的CharacterStat注册确认BOREDOM/UNHAPPINESS/PAIN为0～100、STRESS为0～1，社交采用一次6/3/0.02的开发初值，未验证平衡。原生PlayerEmoteState执行使用EmotePlaying；FitnessState及currentExe均纳入停稳判断。未知/未加载资源、未明消费、缺原生API不以默认成功掩盖。P2/P3原有验收缺口继续保留；本文不将其他会话同步修改算作本轮独立成果。

## 交付与下一步

构建产物：build/packages/EmberRoutesProbe-0.26.0.zip；交付JAR SHA256：82F3DB6BE55B695850420F7BF18B837751E13804A80C249E5E851ED9424D1A0D。未发布工坊，未提交混合工作区。

按[单份P3.5实机验收](../../testing/p35-runtime-acceptance.md)集中验证后再调整数值。优先核对原生锻炼循环/姿态退出、社交手势与停止、原版身心量纲、阅读/吸烟真实消费及保存重进。发现某动作不可靠时限制并记录对应动作，不宣称整组已验收。
