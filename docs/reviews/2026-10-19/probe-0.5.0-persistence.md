# 0.5.0 单人 NPC 原版快照与恢复

日期：2026-10-19。状态：实现与本地检查；新增实机未验证。依据 [设计](../../superpowers/specs/2026-10-19-sp-persistence-design.md)、[计划](../../superpowers/plans/2026-10-19-sp-persistence.md)；交付 [集中测试](../../testing/single-player-persistence.md)。没有迁入旧 CommunityTrade / NPCFW 实现。

## 当前安装版本证据

构建重新验证 projectzomboid.jar SHA-256 `E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`，ZombieBuddy.jar `EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2`。运行时启用单人驱动时还读取 IsoPlayer 的 CodeSource JAR 并复核游戏哈希；这不验证外部 Java agent 的全部运行时补丁。

本轮从此JAR以CFR 0.152重新提取的关键路径：

- `IsoPlayer.save(ByteBuffer,boolean)` / `load(ByteBuffer,int,boolean)`：原版人物负载包含角色描述、外观、BodyDamage、Stats、XP、库存、穿戴、手持、营养、健身和其他原版状态。加载消耗首两个对象标记字节；世界格式249。没有调用零参 `save()`、`save(String)` 或玩家DB接口。
- `IsoGameCharacter.save/load`、`ItemContainer.save/load`、`InventoryItem.save/load`：原版库存按实例序列化，包括物品ID。探针另存排序后的 ID/父容器ID/类型/耐久清单，恢复后不一致则阻塞；没有按类型删除后重造替代物。
- 原版人物文件没有保存 `AttachedItems` 槽位关系，探针额外记录槽位到原物品ID并重绑；穿戴及手持也用ID清单核对。`ItemBodyLocation.toString()` 经 javap 确认为注册表资源名。
- `GameWindow.save(boolean)` 在保存当前世界路径中触发 OnSave，然后保存 cell / 原版子系统及 GlobalModData。探针只替换内存中的单个 record，交由同一次原版世界保存写出。GlobalModData 自己的 tmp/copy 并不使全部世界文件成为跨文件原子事务。
- `GameWindow.StringUTF.save/load` 使用有符号short的UTF字节长度。因此完整封装Base64按16000个ASCII字符分块，不能直接写长字符串。SHA-256覆盖元数据与所有原版字节，缺块/错序会失败。
- `IsoGridSquare.save` 保存静态尸体列表，没有保存普通 movingObjects 中的活 NPC；`PlayerDB.savePlayersAsync` 遍历真实 `IsoPlayer.players`，探针不注册该数组，避免和快照形成第二个保存者。
- `IngameState.exit` 停世界工作线程，卸载区块、重置模型，再 `IsoWorld.KillCell`；后者调用 `IsoCell.Dispose` 清空对象列表、将全部chunkMap置null并替换IsoWorld实例。只有世界实例不同、旧列表为空、所有旧chunkMap为null三条件同时成立，探针才释放旧引用，完全不再调用旧人物的原生stop/remove。没有这些证据则保留所有权并阻塞。活世界删除仍走原有攻击关系静默退场。
- 正常保存菜单使用原版 `ISSleepDialog.lua` / `ISWorldObjectContextMenu.lua` 中相同的 `save(true)` 入口；引擎负责最终磁盘结果，菜单返回 `WORLD_SAVE_REQUESTED`。

选段和签名见同目录 `probe-0.5.0-source-evidence.json`。完整临时反编译输出在忽略的 `build/reference/pz-current`；不能把旧42.20.4反编译行号混为当前证据。

## 实现边界

Java checkpoint封装限制4MiB原版字节、4096件物品、16层嵌套；带格式号、世界路径、游戏哈希、UUID、原坐标、驻点与FOLLOW/RETURNING/HOLD。GlobalModData命名空间为 `EmberRoutes/NpcCheckpoint/v1`；LIVE / EMPTY / BLOCKED仅随正常世界存档提交。保存异常或夹具清理失败写BLOCKED，不能继续回放旧资产快照；引擎事件无法取消整个世界磁盘保存，故失败后退出仍可能损失NPC状态。

原版载入先在未附着的人物上执行并验证，最后由唯一Session接管再附着。保留相机及IsoPlayer.instance。格式、世界、基线、校验、库存/装备或方格不符都拒绝，原数据保留；没有旧检查点回退、自动瞬移、无界重试或玩家槽位占用。需要原方格加载且玩家在16格内。删除或死亡后保存空记录；意外离场写阻塞，不让旧快照复活。

Lua保存前导出标量意图，再取消所有动作/工作并清理0.2/0.3夹具；保存成功后重新建立随从策略。跨载入也只重建意图，不保存Lua闭包、userdata、玩家索引或半截TimedAction队列。额外验收样本持久保存自己的ID/状态标记，清理时仅移除确切实例；含外来物品或穿戴/挂载样本时阻塞清理。

原版序列化覆盖面不代表所有模组私有状态、引擎临时动画或跨存储崩溃安全；未实现离场虚拟化、自动生产、社区/商队持久化、多NPC、MP或载具转换。改名/搬移世界目录会触发世界路径不匹配。任意备份必须整体恢复世界文件，不能单独回滚全局表。

## 本地验证

检查的原始输出、包哈希与版本见同目录 `probe-0.5.0-*` 文件；用户尚未运行本包。Java纯逻辑和Lua替身不验证真实原版序列化、模型/身体恢复、楼梯、引擎事件线程、同进程主菜单重载或故障恢复。

最终300项独立断言：Java原有65、checkpoint/门禁42；Lua批次16、动作14、搬运42、随从36、跟随策略29、暂停8、控制器交接6、保存交接27、存档样本15。嵌套复跑的旧套件不重复计数。preflight全部通过，LuaLS零错误零警告；release-check零错误零提示；9份文档doclink零错误零提示。原版知识库仍有一份`0.0f`语法解析缺口，不据此声称原版文件已验证。

旧lua_lint未收录原版save宿主全局，初次新增正常保存菜单时报未定义；已通过当前JAR的GlobalObject.save字节码和原版两处调用查证，再以有类型守卫的`_G.save`取得入口。没有修改共享工具、伪造全局或吞掉引擎保存错误；原版GlobalObject本身捕获Throwable并记日志，故菜单只报告请求，不报告磁盘成功。
