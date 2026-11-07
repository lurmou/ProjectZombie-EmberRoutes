# 小队基础 HUD 补全：0.29.53

2026-11-06，用户批准补齐参考基础UI；没有实现接管、物品转移、载具或战斗。

## 玩家可用交互

- 拖标题空白处移动HUD，松手保存归一化位置；拖动中与恢复时限制屏幕边界。
- 拖成员卡片到另一张卡片调整显示顺序，描边提示目标，按稳定NPC ID保存；不改`squadSlot/followSlot`、成员revision或队伍业务。
- “设置”菜单分别选择HUD布局和按钮尺寸85%/100%/120%/140%，可恢复默认布局（不删除呼号）。字体仍使用游戏Small字体，字体变化时重新布局，不通过拉伸文字冒充字体缩放。
- 分辨率事件立即重排；活跃HUD每500ms补查字体/窗口尺寸，隐藏不检查。窗口始终受屏幕约束；卡片区小屏滚动并Stencil裁剪，标题和指挥按钮保留。
- 卡片悬停高亮，提示完整姓名、呼号、生命、命令、实际行动、阻碍及所有已触发状态；移出/隐藏关闭提示。
- 高/中/低血量分别复用READY/UPDATING/ERROR色，阈值60/30；未知生命为空条和未知文案。
- 读取原版BLEEDING、SICK、PAIN、ENDURANCE、PANIC、HEAVY_LOAD、TIRED、HUNGRY、THIRST；参考阈值1/2/2/3/3/3/3/3/3。卡片最多两个SemanticBadge，其余保留在完整提示。没有状态推测或自理副作用。
- 卡片右键提交既有跟随/等待/返回/移出及显式槽位命令，编辑/清空呼号。原生输入框最多24字符，呼号独立于NPC正式姓名。

## 源码与所有权

代码根：`C:/Users/MuMu/Zomboid/Workshop/EmberRoutes/Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`。

| 位置 | 责任与实际行为 |
|---|---|
| `SquadPreferences.lua` | 唯一角色显示偏好读写；ModData.EmberRoutesSquadHUD format=1，归一化位置/scale/buttonScale/order/callsigns。初始化不写默认值；未知格式保留原记录并拒绝写，不迁移。最多3个显示排序ID、512条呼号，不引用业务根表 |
| `SquadService.lua` readMood / refresh | 最多3名成员的有界原版Moodle观察，仍只读；身体/宏观命令继续MembershipService权威 |
| `UI/SquadPresentation.lua` cards | 无状态投影，准备截断名称/全量tooltip/血量色/已测量badge；不观察实体或修改偏好 |
| `UI/SquadHUD.lua:39` show | activation scope创建；拥有信号、头像、主题、TooltipManager、菜单/dialog和拖动捕获 |
| `UI/SquadHUD.lua:98` project | 显示顺序投影、卡片高度/滚动上限、边界clamp；`:137`命中必须在卡片视口内；`:178`拖动只维护显示状态；`:204`松手保存偏好 |
| `UI/SquadHUD.lua:147` updateTooltip | 原生ISToolTip初始化/显示；TooltipManager在update阶段定位，不向render引入观察/测量 |
| `UI/SquadHUD.lua:230` drawCards | 只画缓存；Viewport只提交可见卡片，SemanticBadge预填fontHeight/textWidth，避免draw测量 |
| `UI/SquadHUDMenus.lua` | 当前activation的原生上下文菜单内容与ISTextBox；目标捕获/过期门禁，呼号提交再核当前名单；关闭只隐藏仍持有同一回调的共享菜单，不碰已被其他UI复用的菜单 |
| `SquadUI.lua` resolutionChanged | 关闭自有轮盘，活跃HUD重新布局；隐藏HUD不建立新观察 |

创建：HUD.show创建activation及订阅、tooltip注册、菜单受wrapCallback门禁。正常释放：HUD.hide→PageLifecycle.unmount，逆序关闭轮盘、菜单/dialog、拖动捕获、tooltip注册/头像/主题/信号。异常：session.valid死亡/换世界关闭HUD；OnPreMapLoad reset关闭；过期回调无写入。dialog关闭同时释放原生隐藏colorPicker并unfocus输入框，避免隐藏浮窗/输入焦点残留。该轮不触及身体租约创建/正常释放/异常交接，仍为TaskController/MembershipRuntime已有协议。

## 参考与API证据

实际读过`D:/Project/ProjectRemnants/42/media/lua/client/ISUI/NPCFW_PartyUI.lua`：readSavedDockPosition/saveDockPosition、moveDockBy/finishDockDrag、moveSlotToIndex/finishPortraitDrag和OnResolutionChange；排序与链路连接在参考中有关联，本项目只复用显示拖排，不带入队伍链接业务。
`NPCFW_PartyPortrait.lua`：collectPortraitMoodBadges/getTooltipText、getHealthColor、鼠标捕获/finishMouseInteraction、callsign dialog与保存全链路。参考普通点击会接管角色，本项目继续单选，不照搬业务。
原版`ISContextMenu.lua`实际使用get/addOption/onSelect及hideAndChildren；`ISTextBox.lua`初始化entry后才配置，destroy不负责其隐藏colorPicker，故明确清理；`ISTextEntryBox.lua`核对focus/unfocus/setMaxTextLength；`ISToolTip.lua`核对new/initialise/instantiate/setDescription。当前JAR `zombie.scripting.objects.MoodleType` javap确认全部九个常量，原版ISHealthPanel/ISVehicleMenu使用getMoodles():getMoodleLevel。没有凭旧包路径断言API缺失。

## 检查结果

通过：
- 9套定向Kahlua：squad-command-ui、squad-preferences、membership-command、membership-slot-menu、membership-runtime、membership-save-lifecycle、task-companion-runtime、companion-handoff、companion。59条小队UI断言+18条偏好断言；末轮菜单空目标/共享菜单所有权修正后重跑UI/偏好通过。
- 真正生产HUD、Preferences、Presentation、Service、Menus与Lifecycle进入替身检查；覆盖拖动屏幕限界、保存/恢复、排序不发命令、不改业务槽/版本、血量三档、最多两徽章但完整tooltip、渲染不观察/不测量、小屏滚动、字号变化、过期回调、dialog隐藏colorPicker/焦点及共享菜单不误关闭。
- 隔离build-probe：Java真实编译、96桥、94基础断言及既有控制/检查点/轨迹/姿态/指标与内核检查；369份Lua普通/Debug均0失败。
- check-i18n.py：2041对IG_UI键，CN/EN对称、静态helper与动态小队域检查0错误；键位UI.json继续对称。
- 五个功能模块结构lint无finding（原版ISFluidEmptyAction方言无法解析的既有项不产生结论）；六模块隔离LuaLS 0error/34warning（33动态字段、1原版可选参数存根）；不宣称全库类型检查。

未运行：所有游戏内视觉、真实鼠标拖动/提示、字体/分辨率切换、磁盘重进及帧性能。Kahlua用原装VM但原生控件/角色为替身，不代替实机；没有启动用户游戏，没有提交/推送/发布。上一轮其他田地夹具依赖失败不在本轮改动内，本轮不宣称全库回归。

## 可测试版本

0.29.53，隔离快照`build/squad-hud-foundation-0.29.53-114845`，候选包`build/packages/squad-hud-foundation-0.29.53/EmberRoutesProbe-0.29.53.zip`。
SHA256：`92d59a4d1d6e5d5c38a1ab77d839d29adb3cc026e3ac7bcc0be1712c56a322ee`。
最终验证构建输入无漂移、包内392项与工作目录全部对应文件逐字节一致；游戏未运行时只同步验证JAR/mod.info/Build.lua，没有覆盖同期据点UI文件。该一致性只针对验证时点，后续其他聊天变更仍须以新构建为准。

用户验收：三名加入→点选/Shift/指挥→拖标题到屏幕角落→拖排并确认编队不变→设置两种独立缩放→悬停/右键呼号→低血量及饥渴状态→缩小窗口滚动→隐藏重开→保存重进核位置/顺序/呼号。用用户既定独立测试档。
