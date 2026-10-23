# P1保存生命周期：安装JAR核查

2026-10-23。静态字节码证据，不是实机退出/磁盘故障测试。

安装projectzomboid.jar SHA256：E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33。

原始输出：build/research/p1-gamewindow-javap.txt和p1-ingamestate-javap.txt，由javap -c -p读取当前安装JAR。初次猜测的zombie.savefile.Savefile类不存在，已改为从实际JAR目录定位GameWindow/IngameState，不使用失败输出作证据。

## 已确认事实

- GameWindow.save(boolean)内直接调用LuaEventManager.triggerEvent("OnSave")，回调返回后继续同方法的保存工作，不在此等待下一游戏tick的停稳协议。
- IngameState包含GameWindow.save(true)及随后触发OnPostSave的路径；所见调用周围有异常捕获，故不能仅收到OnPostSave便认定保存成功。
- 以上不能推出“退出几毫秒就杀VM”，也不能证明所有保存路径都提供相同事件；完整文件落盘顺序、失败传播和运行时插件影响仍须进一步核查。

## 已落实到设计/计划的约束

1. 提前准备可以跨正常tick停止派发、请求停稳；原生OnSave不可等待这套异步流程。
2. OnSave同步捕获业务事实。停止/效果未知时保留原件标识、业务恢复点和UNKNOWN，不伪造安全检查点，不把抛Lua异常当取消引擎存档。
3. 恢复只在后续正常tick、世界仍有效且关联/声明核对通过后授权；退出没有后续tick时无需恢复。OnPostSave只作观察信号，不单独开闸。
4. 清队列/硬超时是停止尝试，不等于效果回滚或身体停稳，不默认传送角色。

唯一设计见[NPC架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)，执行入口见[P1计划](../../superpowers/plans/2026-10-23-p1-runtime-integration.md)。0.22.12已按两路径接入，见[统一保存证据](p1-unified-save.md)；原生实机仍未验，不能在OnSave内循环step或睡眠等待。
