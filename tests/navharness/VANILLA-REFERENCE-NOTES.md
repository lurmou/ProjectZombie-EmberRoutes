# Vanilla Reference 尝试记录（第 6 项，加分项）

结论：**未打通，无对照 runner。** 原始堵点（`updateThread` NPE）已定位并绕过，
但原版寻路至今未返回过一次 `SUCCEEDED`，两条路都按上限停手。
本文记录全部 4 次尝试（路线 a × 1、路线 b × 3）的精确输出、字节码证据和已知边界，
接手者按 §5 的“下一步”一次运行即可验证最后的缺口。

> 约束遵守：路线 a 上限 3 次，用了 1 次（§3 有数学证明：其余坐标不可能成功）；
> 路线 b 上限 3 次，用了 3 次（B1/B2/B3），第 4 次未跑。
> 生产代码未动；探测程序只留在 `/tmp/nav-spike/`（scratch，不进仓库）。

---

## 1. 背景：验证时堵住的原始问题

`Spike3.java` / `Spike3b.java`（`/tmp/nav-spike/`，只读参照）用同一假地图
（8×8 房间，x=4 立墙、y=3 留缺口）跑 `PolygonalMap2`：

- `pm.init(world.getMetaGrid())`、`addChunkToWorld(chunk)`、
  `addRequest(pf, mover, 1.5f, 3.5f, 0f, 6.5f, 3.5f, 0f)` 都能调，不用 `IsoPlayer`；
- `updateThread` 报 NPE，定位为 `Chunk` 为 null 时调 `Chunk.setData`；
- `Spike3b` 多试了 `allocChunkIfNeeded(0, 0)`，`getChunkFromChunkPos(0, 0)` 仍为 null。

字节码确认的 NPE 链（`projectzomboid.jar`，`javap -c`）：

```
ChunkUpdateTask.execute():
    Chunk c = map.allocChunkIfNeeded(wx, wy);   // 可返回 null
    c.setData(this);                            // 无判空 → null 时 NPE
PolygonalMap2.allocChunkIfNeeded(cx, cy):
    Cell cell = getCellFromChunkPos(cx, cy);    // null → 返回 null
    return cell == null ? null : cell.allocChunkIfNeeded(cx, cy);
PolygonalMap2.getCellFromSquarePos(x, y):
    x -= minX * 256;  y -= minY * 256;
    if (x < 0 || y < 0) return null;
    cellX = x / 256;  cellY = y / 256;
    if (cellX >= width || cellY >= height) return null;
    return cells[cellX][cellY];
PolygonalMap2.init(IsoMetaGrid mg):
    minX = mg.getMinX();  minY = mg.getMinY();
    width = mg.getWidth();  height = mg.getHeight();
    cells = new Cell[width][height];            // width=0 → new Cell[0][0]
```

---

## 2. 关键字节码事实（四次尝试共用）

- 新 `IsoMetaGrid()`：`minX = minY = 10_000_000`，`maxX = maxY = -10_000_000`，
  `width = height = 0`。`minX/minY/maxX/maxY` 是 public 字段；`width/height` 是
  private 字段，全 jar 只有一处赋值——`IsoMetaGrid.CreateStep2()` 内
  `width = maxX - minX + 1` / `height = maxY - minY + 1`，且该方法先扫
  `.lotheader`，无地图数据时抛 `IllegalStateException("Failed to find any
  .lotheader files")`。即：**不靠地图文件配不出 width/height，除非反射改
  private 字段**。
- PM 内部层号 = 世界层号 + 32：`ChunkUpdateTask.init` 调
  `setMinMaxLevel(isoChunk.minLevel + 32, isoChunk.maxLevel + 32)`，
  读格子用 `isoChunk.getGridSquare(x, y, level - 32)`。所以世界 z=0 的数据在
  PM chunk 里是 `minLevel = maxLevel = 32`，`isValidLevel(0) == false`、
  `getLevelData(0) == null` 是**正常现象**，不是空数据；应查 level 32。
- 每个 PM `Cell` 覆盖 32×32 个 chunk；`Cell.allocChunkIfNeeded` 内
  `local = chunkPos - cellPos * 32`，越界返回 null。
- `PolygonalMap2.init` 会启动 `PMThread`（daemon，名 `PolyPathThread`），
  它自己循环调 `updateThread()`（持 `renderLock`）。主线程再手动调
  `updateThread()` 会与它竞跑；真实游戏的分工是主线程只调 `updateMain()`。
- `IsoChunk.getGridSquare(x, y, z)` 读 chunk 自己的 `squares[][]`（x、y 须 0..7），
  不读 `IsoChunkMap`。但 `IsoChunkMap.setGridSquare` 内部会调
  `IsoChunk.setSquare(...)`，所以 Spike3 的写法本来就能填进 `IsoChunk.squares`。
- `SquareUpdateTask.getBits(IsoGridSquare)` 的位来源（全是格子自身 flag）：
  `512 = solidfloor`、`1 = solid`、`1024 = solidTrans`、`2 = collideW`、
  `4 = collideN`、楼梯/窗户若干；**`BIT_CAN_PATH_W/N` 来自
  `IsoFlagType.canPathW / canPathN`**，不是从邻居推导的。
- `createVisibilityGraphs()` → `createVehicleClusters()`：**无车辆时直接
  `return`**，`clusters`/`graphs` 为空 → `addCanPathNodes()` 无事可做 →
  `squareToNode` 恒为 0。无车辆世界的完整 A* 节点图目前没有已知的生成路径。
- `findPath` 的快路径：起止同层且 `LineClearCollide.isNotClear(...) == false`
  时直接起止两点成路，不需要节点图。

---

## 3. 路线 (a)：其他 `allocChunkIfNeeded` 坐标 —— 1 次尝试，关闭

尝试 A1（`VanillaProbeA1.java`）：新 `IsoWorld` + `IsoCell(30, 30)`，
打印 metaGrid 后对 12 个坐标调 `allocChunkIfNeeded` + `getChunkFromChunkPos`。

精确输出：

```
metaGrid: minX=10000000 minY=10000000 maxX=-10000000 maxY=-10000000 width=0 height=0
fresh IsoMetaGrid: minX=10000000 minY=10000000 maxX=-10000000 maxY=-10000000 width=0 height=0
pm.init ok
alloc(0,0)=null getChunk=null cell=null
alloc(1,0)=null getChunk=null cell=null
alloc(0,1)=null getChunk=null cell=null
alloc(-1,0)=null getChunk=null cell=null
alloc(0,-1)=null getChunk=null cell=null
alloc(5,5)=null getChunk=null cell=null
alloc(31,31)=null getChunk=null cell=null
alloc(32,32)=null getChunk=null cell=null
alloc(-32,-32)=null getChunk=null cell=null
alloc(100,100)=null getChunk=null cell=null
alloc(-100,-100)=null getChunk=null cell=null
alloc(1000000,1000000)=null getChunk=null cell=null
PROBE-A1 DONE
```

结论：**路线 (a) 不可能成功，不再试第 2、3 次。** 证明：`width = height = 0`
时 `getCellFromSquarePos` 的 `cellX >= width`（`cellX >= 0` 恒真）对一切坐标
返回 null，与坐标无关——这是 `init` 时 `cells = new Cell[0][0]` 决定的，
不是坐标没试对。Spike3b 只试 (0,0) 不是问题所在。

---

## 4. 路线 (b)：配好的 `IsoMetaGrid` 做 `init` —— 3 次尝试，NPE 已过，请求仍 FAILED

共同配置（三次相同）：取 `world.getMetaGrid()` 就地改
`minX = 0; minY = 0; maxX = 0; maxY = 0`，再反射改 private 字段
`width = 1; height = 1`（`Field.setAccessible(true)`，JDK 25 无名模块下成功）。
假地图与 Spike3 完全相同（8×8、`solidfloor` 地面、x=4 立墙 y=3 缺口）。

### B1（`VanillaProbeB1.java`）：配置 + 全流程，手动 `updateThread()`

精确输出：

```
chunk registered: true
world built
metaGrid configured: minX=0 minY=0 maxX=0 maxY=0 width=1 height=1
pm.init ok
alloc(0,0)=zombie.pathfind.Chunk@643b1d11 getChunk=zombie.pathfind.Chunk@643b1d11 cell=zombie.pathfind.Cell@2ef5e5e3
addChunkToWorld ok
addRequest ok, waiting...
vanilla result: FAILED
PROBE-B1 DONE result=FAILED
```

结论：**原始 NPE 已绕过**——`alloc(0,0)` 非空，`addChunkToWorld` 后
`updateThread` 无异常（`ChunkUpdateTask.execute` 拿到非空 chunk，
`setData` 正常跑完）。但请求结果是 `FAILED`，不是 `SUCCEEDED`，
且无任何异常/堆栈。`FAILED` 是寻路器算出的结论，不是崩溃。

### B2（`VanillaProbeB2.java`）：去掉手动 `updateThread()`，只调 `updateMain()`，加诊断

改动理由：`PMThread` 已在循环调 `updateThread()`，手动再调是竞跑；
改成真实游戏的分工（PM 线程管 `updateThread`，主线程只调 `updateMain`），
并在 chunk 任务消费后（sleep 2s）打印 PM 内部状态。

精确输出：

```
chunk registered: true
world built; isoChunk minLevel=0 maxLevel=0
metaGrid configured: width=1 height=1
pm.init ok
addChunkToWorld ok
squareToNode.size=0
pmChunk(1,3)=zombie.pathfind.Chunk@5d5eef3d
  minX=0 maxX=7 minY=0 maxY=7 minLevel=32 maxLevel=32 validLevel0=false
  squaresForLevel(0)=null
  levelData(0)=null
trivial request result: FAILED
wall-crossing request result: FAILED
PROBE-B2 DONE trivial=FAILED wall=FAILED
```

结论：两条请求（开阔地 `(1.5,1.5)→(2.5,1.5)` 和穿墙
`(1.5,3.5)→(6.5,3.5)`）都 `FAILED`。当时误判 `minLevel=32`、
`levelData(0)=null` 为“数据未写入”，后经字节码核实是 +32 层号偏移
（§2），数据其实已写入。真正的异常信号是 `squareToNode.size=0`：
没有生成任何寻路节点。

### B3（`VanillaProbeB3.java`）：核查 `IsoChunk.squares`，查 level 32 的位

改动理由：怀疑 `ChunkUpdateTask.init` 读到的格子全是 null
（`IsoChunk.getGridSquare` 读自有 `squares[][]`，而 Spike3 只写了
`IsoChunkMap.setGridSquare`），于是先打印 `chunk.getGridSquare`，
再用 public 的 `IsoChunk.setSquare(x, y, 0, sq)` 直接补填 64 格，
重跑全流程，并用反射调 `Square.has(int)` 查 level 32 的位。

精确输出：

```
chunk registered: true loaded=true wx=0 wy=0
world built
BEFORE fix: chunk.getGridSquare(1,3,0)=zombie.iso.IsoGridSquare@34ce8af7 (0,0,0)=zombie.iso.IsoGridSquare@b684286 (4,3,0)=zombie.iso.IsoGridSquare@880ec60
BEFORE fix: cm.getGridSquare(1,3,0)=zombie.iso.IsoGridSquare@34ce8af7 cm.getChunk(0,0)=null
AFTER fix: chunk.getGridSquare(1,3,0)=zombie.iso.IsoGridSquare@34ce8af7 (4,0,0)=zombie.iso.IsoGridSquare@511baa65 (4,3,0)=zombie.iso.IsoGridSquare@880ec60 loaded=true
pm.init ok
addChunkToWorld ok
squareToNode.size=0
pmChunk(1,3)=zombie.pathfind.Chunk@7dc7cbad minLevel=32 maxLevel=32
squaresForLevel(32)=8x8
  pmSq[1][3]=zombie.pathfind.Square@2a5ca609 pmSq[4][0]=zombie.pathfind.Square@20e2cbe0 pmSq[4][3]=zombie.pathfind.Square@68be2bc2
  sq[1][3] bits: CAN_PATH_W=false CAN_PATH_N=false SOLID=false SOLID_FLOOR=true
  sq[4][0] bits: CAN_PATH_W=false CAN_PATH_N=false SOLID=true SOLID_FLOOR=true
trivial result: FAILED
wall-crossing result: FAILED
PROBE-B3 DONE trivial=FAILED wall=FAILED
```

结论：**“格子没进 IsoChunk”的假设被证伪**——补填前
`chunk.getGridSquare` 已能返回格子（`IsoChunkMap.setGridSquare` 内部的
`setSquare` 已生效；顺带：`cm.getChunk(0,0)=null` 说明 chunk-map 自身的
chunk 索引查不到该 chunk，但与 PM 无关）。PM chunk 的 level 32 数据
正确：地面格 `SOLID_FLOOR=true, SOLID=false`，墙格 `SOLID=true`。
**真正的缺口是 `CAN_PATH_W=false, CAN_PATH_N=false`**：地面格没有
`canPathW/canPathN` flag，`getBits` 不置 `BIT_CAN_PATH_W/N`，于是
`addCanPathNodes` 找不到可连边的格子，加之无车辆时 `graphs` 为空，
`squareToNode` 恒为 0；连开阔地直路请求也 `FAILED`
（`LineClearCollide.isNotClear` 很可能把无 `CAN_PATH` 的线判为不通，
或快路径之外的回退无节点可用——未再深挖，见 §5）。

---

## 5. 已知边界

**已打通（可复用）：**

- 配好的 `IsoMetaGrid`（public 字段改 min/max + 反射改 private width/height）
  使 `pm.init` 建出非空 `cells`，`allocChunkIfNeeded(0,0)` /
  `getChunkFromChunkPos(0,0)` / `getCellFromChunkPos(0,0)` 全部非空。
- `addChunkToWorld` + PM 线程消费 `ChunkUpdateTask` 不再 NPE；
  PM chunk 数据正确写入（level 32，8×8，`SOLID`/`SOLID_FLOOR` 位与假地图一致）。
- `addRequest` + `updateMain()` 循环能拿到确定的 `FAILED` 回调（不是挂起、
  不是异常），`FakeMover`（`getID`/`getPathFindIndex`）与 `FakePF`
  （`Succeeded(Path, Mover)`/`Failed(Mover)`）可直接复用。

**未打通：**

- 至今无一次 `SUCCEEDED`，无可用作对照的原版路径输出。
- `squareToNode.size` 恒为 0；穿墙请求和开阔地直路请求都 `FAILED`。
- `createVehicleClusters` 在无车辆世界直接返回，`graphs` 为空——
  无车辆时完整 A* 节点图的生成路径仍未知。

**下一步（精确到一次运行，接手者可直接试，不再是本项的第 4 次）：**

1. 在假地图搭建时，给每个地面格加
   `sq.getProperties().set(IsoFlagType.canPathW)` /
   `.set(IsoFlagType.canPathN)`（只给 W/N 邻居也是地面格的格子；
   墙格不加；缺口格 (4,3) 按地面处理）。
   依据：`getBits` 里 `BIT_CAN_PATH_W/N` 只认这两个 flag（§2）。
2. 同 B3 流程跑：若 `sq[1][3]` 的 `CAN_PATH_W/N` 变 true，
   且 `trivial` 请求变 `SUCCEEDED`，则原版对照在开阔地已可用；
   再看穿墙请求——若仍 `FAILED`，缺的是无车辆时的可见图/A* 节点生成，
   需另找 `createVisibilityGraph` 的非车辆触发点（或加一辆假
   `BaseVehicle`/`Vehicle` 进 `pm.vehicles` 凑出一个 cluster，
   但那是新路线，不在本项已试的两条路内）。
3. 若 (1) 后仍全 `FAILED`，打印 `LineClearCollide.isNotClear` 的
   返回值分段（或直接调 `pm.findPath` 的等价路径）定位快路径在哪一步拒绝。

**不在本项范围内的说明：**

- `IsoMetaGrid.CreateStep2()` / `load()` 的正规配法需要真实地图
  `.lotheader` 文件，未试——本项只允“配好的 IsoMetaGrid”，反射改字段
  已满足 `init` 的读取需求。
- 未碰 `PathfindNative.useNativeCode`（native 寻路分支）；
  全部尝试走纯 Java 的 `PolygonalMap2`。

---

## 6. 探测程序清单（scratch，不在仓库）

| 文件 | 路线/次数 | 结果 |
|---|---|---|
| `/tmp/nav-spike/VanillaProbeA1.java` | (a) 第 1 次 | 12 坐标全 null，`PROBE-A1 DONE`，exit 0 |
| `/tmp/nav-spike/VanillaProbeB1.java` | (b) 第 1 次 | NPE 已过，`vanilla result: FAILED` |
| `/tmp/nav-spike/VanillaProbeB2.java` | (b) 第 2 次 | `squareToNode.size=0`，两请求 `FAILED` |
| `/tmp/nav-spike/VanillaProbeB3.java` | (b) 第 3 次 | 位诊断：`CAN_PATH_W/N=false`，两请求 `FAILED` |

另有字节码反编译中间件 `/tmp/pm-dump/`（`pm2.txt`、`cut.txt`、
`sut.txt`、`icm.txt`、`igs.txt`、`ic.txt`、`chunk.txt`），供核对 §2 的引用。
