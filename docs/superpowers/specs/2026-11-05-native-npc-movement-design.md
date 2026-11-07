# NPC 原版位移执行对齐

2026-11-05：用户已批准“导航提供意图、原版继续执行”，并要求直接实施。

## 问题与取舍

ProbeNpc.doDeferredMovement 原先用 PathFindBehavior2.update 代替原版动画位移执行。安装版寻路器取动画位移长度后直接沿路径点方向 moveUnmodded，身体尚在转身时位移已改变方向。仅降低转身速度不能解决两者脱节。

保留现状无法解决目标；整体照搬参考模组的自建导航会扩大范围。本轮保留原版寻路、障碍交互与朝向处理，用有界调用范围拦截寻路器直接位移，再让原版 doDeferredMovement 消费动画根运动。其间临时摘下 path2，绕过原版“有路径则由寻路器执行”的提前返回，并在 finally 恢复。

参考只读：D:/Project/ProjectRemnants/NPCFW.jar（SHA256 5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E）。NPCMovementUtil.manualMovement 提交移动意图，IsoNPC.update 调用父类，getDeferredMovement 仅限制末端位移长度。当前游戏 JAR 的实际字节码已核对；不照搬其导航或控制器。

## 契约

- 普通行走与已有原生精确目标统一由原版动画流程提交物理位移，每帧最多一个执行者；不得按路径方向重写根运动向量。
- 仅在同步 path.update 范围拦截 moveUnmodded；异常必须 finally 解除。原版朝向、倒退拖尸、开门和翻越分支保留。
- 根运动只缩短至当前路点的剩余距离，不改变方向；原生停止减速继续消费，完成后不额外位移。
- 未找到路径、取消、失败和空闲清掉残留根运动；已有家具姿态及床姿锚定保留。
- 创建端仍为 moveTo/moveToFurniture/moveToBed/moveToCorpse；正常终止仍由 ProbeMovement.tick → stopProbe；异常仍为 update.catch → freeze → stopProbe。stopMask、Session、原件责任与保存格式不变。
- 不调转身速度、不新增导航器、不改已有联机适配。

## 验证边界

构建、现有移动生命周期回归、根运动缩放的转角/倒退/末端边界回归，以及实际编译产物的调用检查。实机须集中观察直角转弯、精确接近家具、拖尸倒退、障碍翻越及停止后重进；未运行前不认定视觉和玩法验收完成。

在线唯一需求已读取；其较旧联机与兼容条目由用户当前 AGENTS 决定覆盖。本轮不修改需求。
