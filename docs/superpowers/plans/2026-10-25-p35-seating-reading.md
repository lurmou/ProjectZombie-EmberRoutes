# P3.5 家具精确定位与阅读坐姿修正计划

用户已批准三项修正，本会话连续实施，不启用子代理。依据[P3.5设计1.3](../specs/2026-10-24-p3.5-leisure-social-fitness-design.md)，不改变唯一身体控制/原件责任。

- [x] 移动节奏：Config/Policy/Service引入移动类共享间隔、降低权重并延长停留，原地回退仍可用；验证不因观察冷却全部无候选。
- [x] 原版定位：ProbeMovement加入原生目标完成模式；ProbeNpc通过pathToSitOnFurniture(object,false)推进，捕获实际目标；ProbeRuntime受控桥与Driver沿同一Session接入；SelfCareFurniture座位分支只接受原生成功及原件一致，不用相邻格。
- [x] 坐姿阅读：StudySeat在取书后有界发现近座、同账本声明、原版定位/就座/阅读/起身；无座站读。SelfCareRecord保存标量readingSite；中断先停止阅读、退出姿态，身体停稳后释放座位；归还责任继续。已知保存读档取消姿态，保留原件。
- [x] 验证：原生目标精确模式Java回归；Kahlua移动节奏、座位路径、阅读姿态/回退/中断/保存；受影响研习/家具/保存回归，preflight、构建、包源码一致、doclink。只报告实际通过；实机动画偏移未测不写修好。

修改文件：ProbeMovement/ProbeNpc/ProbeRuntime、Driver、SelfCareFurniture、LeisureConfig/Policy/Service、StudySeat（新增）、SelfCareExecution/Record、LaborStore、ReposeSites、Boot版本桥检查。验证输出build/logs/p35-seating-*；进度只更新BACKLOG。

执行结果见[本轮开发证据](../../reviews/2026-10-25/p35-seating-reading.md)：16份Kahlua、Java构建/逻辑、CN/EN UI宿主与最终preflight通过；包内190份实际文件0差异。原生游戏画面对齐、正常磁盘重进及性能未验收。
