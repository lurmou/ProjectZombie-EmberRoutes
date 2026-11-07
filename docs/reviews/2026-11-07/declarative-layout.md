# 声明式布局 Phase 1 收口证据

日期：2026-11-07。范围仅 LayoutNode.lua、LayoutSolver.lua；不接入 Host、页面或 DSL，不修改现役 Layout.lua、Java Runner，不交付新测试脚本。

## 源码基线

路径前缀：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/`。

| 文件 | SHA256 |
|---|---|
| LayoutNode.lua | 10AEA2F5412F19358E865A0F04898FC10FF37878DEE1CD118B33471E2B979C2E |
| LayoutSolver.lua | 773B6D11D18801F14D6472945BABD73BB960ADD7CE5DD4818AB2B827D1236983 |

## 修复与契约

- 创建/挂载：Node:add 第79行；bindRoot 第27行。构建期允许组合尚未发布的子树，换池前隐藏旧池叶子槽位。第一次成功 Solver.solve 后设置根的 `_rootLocked`，该独立根不可再挂入其他根，拒绝在拓扑修改前发生。成功发布后的根归属与存活槽位固定；根内动态新增分配新槽位，不重编号已有槽位。未成功求解前暴露的 item 索引不应被调用方当最终映射缓存。
- 正常删除：Node:remove 第118行；clear 第67行。普通叶子和子树均将原槽位置墓碑，子树不提升为新根；移除的是 items 拓扑数组，绝不压缩 _rectPool。
- 独立子节点销毁：Node:dispose 第174行委托 removeChildNode 第179行，再进入同一 remove/clear 链。删除 disposing 布尔旁路。重复 dispose 无副作用；clear 解除 target、owner、child、parent、root 及对共享池的引用，不调用业务控件销毁。
- 已销毁节点的容器 Setter 在写字段前拒绝，避免先污染状态再抛错。
- 失败：Solver.solve 第108行预检活根；非法 bounds 或深层不足均保留已发布池并将整树标 dirty。prepare 暂存标量，publish 第87行统一发布。
- 数值：保留容差负余量归零；新增最大权重缩放的等价 grow 比例计算，避免多个有限大权重相加或 free*grow 中间结果变成无穷。容差内极小几何溢出仍按冻结契约接受，不能宣称绝对无越界。
- 没有加入 Host 所需 revision、叶子适配、激活接口，留给 Phase 2。成功路径是每容器统计与分配两次扫描、再整树发布，整体 O(N)，不是每节点仅访问一次。

## 本轮执行

使用现有 `tests/java/KahluaLaborTest.java` 和安装目录 JAR，不修改 Runner；安装版 stdlib 加载，next 显式不可用。没有初始化游戏世界或原生 UI。

临时案例文件位于被忽略的 `build/layout-phase1/scratch.lua`，未检入 tests/；SHA256 `6636DE70E3C09BB9F4330154FDA12EE1BB5DC53FABC4991F59D0A26F13AE56E3`。

执行命令：

```powershell
java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java ../../build/layout-phase1/scratch.lua
powershell -ExecutionPolicy Bypass -File tools/build-probe.ps1
```

| 检查 | 结果与边界 |
|---|---|
| 安装版 Kahlua 定向执行 | exit 0，PHASE1_CHECKS=136；日志 build/layout-phase1/kahlua.log |
| 定向覆盖 | 负容差、三项残差、巨大/极小有限 grow、双方向四种 cross align、四种 justify、非对称 margin、嵌套 Root-local、初始快照恢复、隐藏/恢复、clean gate、深层失败整池不变、非法 bounds、交叉轴/间距不足、构建换池墓碑、已发布根拒绝迁移、移除/独立 dispose/重复 dispose、存活槽位稳定、target 复用、环/重复挂载拒绝、已销毁 Setter 拒绝 |
| 最终构建 | exit 0 / BUILD_OK，375 份 Lua 普通/Debug 编译通过；模块边界 0 错误，固定依赖哈希通过，2084 对翻译键通过；日志 build/layout-phase1/build.log |
| 包 | build/packages/EmberRoutesProbe-0.29.59.zip，包含工作区既有改动，不是本任务隔离发布包 |

这是有限定向案例的数学/拓扑执行证据，不是所有输入的形式证明。静态审查求解路径未发现 table 字面量、动态闭包或字符串拼接，不等于 Kahlua 运行时或 Java 桥零分配测量。

## 未验证

原生渲染、控件应用、游戏交互、性能与 GC 测量未运行。纯几何模块没有页面接入，不宣称已有 UI 改善。Phase 2/3 未实施，未来页面改动仍须按项目规则运行原生预览并回读截图。
