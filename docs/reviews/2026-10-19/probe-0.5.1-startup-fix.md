# 0.5.1 修复原版JAR识别错误与误导启动提示

日期：2026-10-19。状态：0.5.0实机启动失败原因已确认；0.5.1修复、安装文件与类路径冒烟通过，游戏重启复测待运行。

## 用户报告与直接证据

用户报告所有原有操作均显示“探针Java接口未加载”。[启动日志摘录](probe-0.5.0-startup-failure.txt) 直接确认：ZombieBuddy 2.3.4将项目中的EmberRoutesProbe.jar加入类路径，调用Main成功，输出v0.5.0 BOOT，并向Lua暴露ProbeRuntime和ProbeNpc。不是JAR未加载，也没有授权或版本拒载证据。

console.txt第1771行实际是 `BASELINE_CHANGED ... BCE7EA210FC5C5392CA691A14345D90131B1D664D4D8A1876600A1AC46FD1D3D`。本机读取文件证明它是 `pzopt/aot/pzopt.jar` 的哈希；原版projectzomboid.jar仍为 `E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。见 [文件哈希](probe-0.5.1-installed-hashes.json)。

0.5.0误把 `IsoPlayer.getProtectionDomain().getCodeSource()` 当原版JAR位置；优化模组从优先类路径提供IsoPlayer，使这个假设失效。Lua又把“Java存在但begin拒绝”合并到“接口未加载”，掩盖了真实原因。这是本项目引入的回归，不要求用户禁用优化或NPCFW，也未修改其启动配置。

## 修复

- 按当前JAR javap验证的 `ZomboidFileSystem.init`：base为游戏根目录，workdir为media。使用 `base.canonicalFile/projectzomboid.jar` 校验原版文件，不从IsoPlayer的CodeSource推断安装文件。
- 新ProbeBaseline只处理安装文件；缺文件或哈希真的变化仍阻塞，不加入pzopt哈希白名单，不跳过版本检查。
- BASELINE_CHECK日志同时输出检查文件、哈希与IsoPlayer实际CodeSource，避免再把两种身份混淆。
- Boot保留begin的失败码；菜单、动作、随从及存档入口区分接口缺失、Lua/JAR版本不匹配、基线拒绝与其他驱动未就绪。
- 构建增加本机真实安装文件回归，以及存在pzopt时的真实优先类路径冒烟。后者仅 `Class.forName(...,false,...)` 读取类来源，不初始化IsoPlayer、不启动世界。

## 对测试的修正

原300项断言覆盖纯输入、所有权、存档封装与Lua调度，但Boot测试将Java.begin固定为READY，没验证真实类加载来源，不能证明包能启动。数量不能替代覆盖面；之前将它放在交付结论的突出位置不合适。

这次针对实际故障补上安装文件/优先类路径回归，以及“Java存在但拒绝启动”的文案分支。既有断言保留作便宜的回归网，不把再增加的数量当作实机成功。本轮已读取真实pzopt优先类路径，得到IsoPlayerCodeSource为pzopt.jar且安装基线通过。Java构建、Lua回归、preflight、release-check及文档检查分别归档；游戏内生成/移动和存档恢复仍待用户复测。

更新后完整重启游戏，先确认v0.5.1的BASELINE_CHECK指向原版projectzomboid.jar且随后READY，再试一次生成和移动，成功后继续 [原十二项存档测试](../../testing/single-player-persistence.md)。不必先重做全部动作和搬运测试。
