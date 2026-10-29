# P3.5 0.28.1：移动节奏、原版家具定位与坐姿阅读

> 日期：2026-10-25｜开发修正；真实游戏的偏位、动画、节奏和磁盘重进仍未验收。
> 依据：[设计1.3](../../superpowers/specs/2026-10-24-p3.5-leisure-social-fitness-design.md)、[实施计划](../../superpowers/plans/2026-10-25-p35-seating-reading.md)。保留0.27当前格式；需重启游戏加载同版Java扩展。

## 用户观察与源码事实

用户实测0.28.0闲逛频繁、坐床/椅偏位、拿书后站读。原版ISWorldObjectContextMenu.onRest经ISPathFindAction:pathToSitOnFurniture寻找精确位置，perform取getGoalSitOnFurnitureObject后才接ISRestAction；SpriteGrid可能选到另一个部件。旧SelfCareFurniture只找任意相邻格，near即成功，未执行原版家具目标流程。此前“用了原版动作”不等于完整沿用原版定位。

另外ProbeNpc.doDeferredMovement此前在所有状态丢弃root motion。安装JAR javap核对PlayerSitOnFurnitureState.enter会按SeatingManager位置/方向对齐；IsoGameCharacter.doDeferredMovement消费动画位移。丢弃家具坐下/起身动画位移是额外偏位风险，不能只调坐标补偿。两项对实际偏位的贡献仍需游戏复验。

站读是此前明确未交付的组合，不是原版禁止；安装版ISReadABook.getDuration会对isSitting应用原版0.9时长系数，本项目不另外增益。

## 修正

- 移动节奏：STROLL权重1.2→0.25、SITE_OBSERVE 1.5→0.4，固定观察0.15→1；散步后停留1→5游戏分钟、普通观察2→6分钟。散步专属30游戏分钟冷却，散步和赴观察点共享15游戏分钟移动间隔。原地观察不被移动间隔禁用，避免再次变成全无候选。记忆moveAfter是可验证标量。
- 家具：ProbeRuntime.moveSeatWithControl经同一Session/权威/重入围栏进入原版PathFindBehavior2.pathToSitOnFurniture(object,false)。false只选预约部件，若原版返回不同原对象则失败，不静默继承另一个睡位。ProbeMovement.beginNative只接受原生路径完成，不使用通用0.4格距离提前完成。Lua家具叶验证REACHED与实际目标原对象，不走相邻格捷径。
- 根运动：无路径执行且有家具引用时，仅PlayerSitOnFurnitureState/PlayerGetUpState调用super.doDeferredMovement；路径与原生根运动互斥。坐姿/起身仍在同一控制权内，停稳掩码保持。
- 阅读：取书后StudySeat在同层6格内有界发现座位（最多8片/2现实秒），并限制原生路径长度12格，避免近在眼前却绕远。无座/发现超时/争用/不可达，清理并停稳后站读。原版阅读动作在就座后才构造，原生页数、知识、特质、坐姿时长机制原样裁决。
- 责任：readingSite存原件家具标量证明，原书与座位使用同一LaborStore/LaborClaims。读完或中断先停止阅读并起身，身体/家具退出证据成立后只释放repose键；原书声明与RETURN_ORIGINALS保留到实际归还。停止中/保存捕获仍经统一协议；身体未停不能以站读回退绕过。新Store.releasePersonalSeats拒绝删非座位键，不另建库存或义务表。
- CN/EN加入站读/座位变化/退出等待文案。正常阅读不强制卸武器或凭空造椅子。

## 验证与输出

- 16份定向Kahlua文件通过，日志build/logs/p35-seating-kahlua.txt。新增p35-seat-path-test、p35-reading-seat-test；扩展policy/driver控制用例；覆盖精确目标、不选未预约部件、移动共享冷却、原书/座位同账本、正常完成与中断等待起身、保留归还责任、无座站读和活动记录可加载。其余为受影响研习/家具/任务/保存回归，native host mocked。
- Java构建及ProbeLogicTest加入原生目标模式回归（近距离不可提前到达，原生成功可到达，普通移动不变）；最终输出见build/logs/p35-seating-build-final.txt。
- CN/EN UI宿主通过，日志p35-seating-ui-CN.txt / p35-seating-ui-EN.txt，未运行游戏渲染。
- release-check 0 error / 76既有提示，未全量重排混合UI。git whitespace配置报告既有空格缩进偏好，不以此重排整个混合工作区。
- 最终稳定源码preflight全部通过（build/logs/p35-seating-preflight-final.txt）：LuaLS 0 Error / 289 Warning，保留动态字段告警与原版ISFluidEmptyAction的0.0f解析盲区；未声称零告警。文档6份doclink检查0断链；包一致性见下方收尾记录。在线唯一需求本轮重取仍为v3.3，结合用户明确决定执行；未写在线文档。

## 未验证

实际家具动画是否准确、各种朝向/多格床/沙发、玩家占座、灯光对阅读、危险/跟随中断、磁盘保存退出/重进、性能和优化模组兼容仍需实机。开发测试不是截图对齐验证，不声称所有家具零偏差、零损失或MP完成。

## 最终产物核验

版本0.28.1；最终构建UTC 2026-10-25T06:44:22.8380238Z。JAR SHA256 `CF131F790AF6FDFEE5387BFF19C2E8D66F9F45EC4B93A4E702FDE644C4B8E65C`；ZIP SHA256 `78FC85E34B95FB6B4FFA80E8A3C498DC3A151869C3EBE564F6BBBA2D85A78A90`。包内190份实际文件与当前模组源码/资源逐字节一致，0差异；构建报告哈希一致。未发布工坊、未替换用户存档、未启动游戏。
