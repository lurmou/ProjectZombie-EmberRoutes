# 据点三页可视状态实施计划

依据[设计](../specs/2026-10-21-settlement-visual-status.md)，主代理独立实施。

- [x] 新增UI/StatusVisual：准备状态徽标与阶段轨道，用现有Theme矩形绘制；Theme.enable包裹原版禁用处理，保留命令门禁。
- [x] UI/Summary与WarehousePage/Details：计数卡片、真实覆盖条、不完整提示和警示形状；来源定位保持原逻辑。
- [x] UI/LogisticsCards/Page/Presentation：卡片数量条、阶段轨道、运行/人数徽标及端点标记，移除可见内部编号。
- [x] UI/CraftingCards/Page：可视工人卡、阶段轨道及原平台详情；复用所有既有命令，主操作随状态切换，改善详情导航。
- [x] CN/EN成对文案、完成/暂停/未知提交/其他任务忙碌回归；绘制禁止测量、字体/屏幕适配、切页释放与后台业务独立检查。
- [x] 可选预览只在tests与tools中生成，不混入模组运行时；每页独立中英文布局预览。
- [x] 完成必要静态检查、构建、包核对，记录实际证据；游戏实机未运行应明确保留。
