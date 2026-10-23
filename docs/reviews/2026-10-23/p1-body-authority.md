# P1任务2：Java身体授权与停止快照

2026-10-23，0.22.6。已实现授权/快照接口和Controller—Driver桥接，未将Production/Work/Companion等旧业务切换至新接口；P1整体未完成，游戏未运行。

## 实现与兼容范围

- 新增Java BodyAuthority：每NPC唯一capability、单调会话代次、错误/迟到凭据拒绝；保存冻结不允许新授予/移动，仍允许必要停止；退役不再授予，已有拥有者可停止与释放。世界切换重建独立注册表；旧凭据不能跨世界使用。
- ProbeRuntime通过当前线程、SP模式、世界与cell、载体身份共同验证。Main.java原本通过Exposer.exposeClass注册ProbeRuntime，新增静态方法沿同一注册入口，无另建桥。
- acquireBodyControl只在原生停止位图为0时尝试授予；这是接线前置检查，不是Lua队列和业务结算的完整证据。世代为1～2^53-1整数，重复/降低代次拒绝。凭据不保存到存档或UI。
- 新增moveWithControl/stopWithControl/releaseBodyControl、bodyStopMask、freeze/thaw/retireBodyControl。控制调用进行中拒绝同NPC重入控制、释放或停止采样。moveTo会清动作，故受控移动还要求原生characterActions为空，不能以移动代替合法中断。
- 对已进入managed模式的NPC，旧stopCarrier、command/commandFor写操作及clearForSave/saveCheckpoint/restoreCheckpoint绕行被拒绝；inspect仍允许。授权释放后managed标记保留，不退回旧控制。reset及世界清理是明确系统退役路径。
- 未进入managed模式的旧NPC维持兼容。目前正式业务没有调用attachDriver，运行行为仍走旧入口。本阶段不宣称所有动作入队/直接调用原生对象已被封堵；Task3仍须收敛Lua动作与诊断入口，Task4仍须接保存路径。第三方模组直接操作引擎对象不属于capability的沙箱安全保证。

## 原生快照契约

当前安装projectzomboid.jar SHA256仍为E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。javap核对了IsoGameCharacter.getCharacterActions/isMoving/getPath2及PathFindBehavior2.isGoalNone/getIsCancelled/pathNextIsSet。

bodyStopMask返回-1表示不可观察/身份或凭据无效；非负整数为：1自有移动循环活动、2原生isMoving、4原生动作栈非空、8已发布path非空、16未取消的寻路目标、32pathNextIsSet。0只表示这些采样项均清空；不代表没有迟到回调、没有物品效果，也不代替Lua队列检查。无“调用stop返回true便当作停稳”的捷径。

Driver.stopEvidence返回available/nativeMask/nativeStopped，不直接制造TaskStopEvidence的bodyStopped断言。业务adapter须结合Lua队列、动作尝试及效果记录作最终判断。

## Controller接入契约

新增attachDriver(ticket,binding)：只接受ACTIVE票据及同npcId绑定，以控制器私有Session generation取得Java凭据；不能在停止/保存或同步派发中附加。move通过原Session.dispatch调用Driver；stopBody只允许STOPPING拥有者，供adapter.requestStop闭包调用；bodySnapshot只读。凭据留在控制器内部，不在inspect中返回。

效果记录成功后，控制器还需成功releaseControl才关闭会话；Java仍未停稳则保持STOPPING。beginSave同步冻结Java和Lua；finishSave检查会话已清空再恢复Java授予，不把OnPostSave当成功凭据。retire同步退役Java注册表，旧停止清理仍可按身份处理。

## 实际检查

BodyAuthorityTest已加入既有构建脚本，验证单NPC互斥、错误NPC/凭据、代次防重放、保存冻结与停止例外、释放前置、退役与新世界隔离，不实例化游戏身体。

安装Kahlua：task-controller-test.lua 28项、task-driver-control-test.lua桥接场景及execution-sessions-test.lua 48项通过。桥接替身验证授权附加、同NPC、原生掩码、移动/停止、保存/释放、过期票据；不是Java原生身体实测。原始输出build/logs/p1-body-lua-tests.txt。

0.22.6构建及Java相关回归通过；preflight输出build/logs/p1-body-preflight.txt，release-check输出build/logs/p1-body-release.txt（0错误/54条已有UI提示）。preflight全部通过，LuaLS 0错误/72条信息性警告（undefined-field 67、duplicate-set-field 2、need-check-nil 1、missing-fields 1、redundant-value 1），不宣称零警告。最终包Controller/Driver哈希与源码一致，JAR包含BodyAuthority；释放授权抛异常时仍保留STOPPING的桥接回归通过。实机移动/停止、原生回调、存档恢复及性能均未验证，按用户决定交集中游戏测试，不另搭独立探针项目。

## 准确下一步

按[P1计划任务3](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)接Production/Work/Companion/CraftProbe及Debug动作入口；旧单/原件声明保持，停止证据不得直接等于nativeMask==0。保存统一恢复在任务4完成；Task3与Task4闭环前，不自动将全部NPC切换managed模式。
