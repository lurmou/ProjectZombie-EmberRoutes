# 配送同趟跨仓库集货

日期：2026-11-02；功能分支 phase-3a-consolidation@eb65db6 加本会话未提交修改；候选0.29.23。依据用户本轮明确反馈修复，不另开公共调度器。

## 根因与方案比较

DeliveryService.batch 在首个有货的箱子即返回，picks/counts/used 每箱重建；HaulManifest.valid 同时强制所有 line.sourceId==r.source，DeliveryFlow/DeliveryTarget/计数也只读该单来源。仅延后选货返回会生成执行与校验不支持的任务，不能局部改循环冒充完成。

选择扩展现有逐原件来源事实：manifest 已有 sourceId，由认领意图提供每件真实来源；根 source 保留返仓锚点。收益是同趟跨箱、准确归还、复用原Job/Claims/Session和连续动作；代价是配送执行、校验和收货投影需一同适配。没有引入通用多站工作流或额外持久账本。

## 改动及闭环

- DeliveryService.batch 在多个来源间累计 picks/counts/used，保存分片观察进度；每次观察最多256件，预算不足继续扫描，不能首箱选中后即派送。按实际可用负重及NPC容器接收能力选择。
- 跨来源仍一次创建认领：DeliveryService.claim → Work.assign → HaulAgent.assign → HaulManifest.create(per-item sources) → 既有 HaulJobs/Claims。
- DeliveryFlow 按未取 manifest 的 sourceId 逐站取货，保留已携货，所有本轮原件处理后再去玩家。源失效只撤回该源未取原件，不删除已持货责任；观察缺失不变成其他来源原件缺失。
- DeliveryTarget 的取货校验和取消返还优先位置按对应 line.sourceId，连续取货仍只衔接同一停靠点。已领取的各箱原件分别实际归还，不能全部塞回首箱。
- Service.projectDelivery 是纯计数投影，DeliveryFlow 与最终订单结算共用；按实际来源匹配，指定来源优先，每件凭据只抵扣一条需求。替代原按根source判断和同类型通用/指定来源重复计算的路径。
- Job格式仍为3，旧单箱记录 sourceId 已存在，可按旧事实恢复；新多源记录须使用本版本，不宣称旧版本可读取。
- 技术边界：配送每个Job最多256个原件，与claims有界记录对齐，替代此前30件；正常物流上限不变。超出256件会后续配送，不能承诺此时仍装满物理负重。本轮不扩展无界存档或跨Job携货控制。

## 必要验证

- delivery-service-test：55项通过，增加两箱合并为同一携带上限批次、先取齐再配送、下一趟只补剩余量、取消后分别归还实际来源。库存/寻路/动作底层为替身，不能代替实机。
- haul-routing-test：30项通过，既有普通物流改道行为未扩大；未重跑完整测试。
- 新回归首次在配置远处源箱时触发既有距离门禁；已把测试操作者移动到箱旁完成配置，未放宽生产门禁。
- Java构建、347份Lua普通/Debug编译、CN/EN键集通过；候选包363文件逐项哈希与工作区一致；4份文档引用零错误，git diff --check无错误。不新增模拟场景套件，不运行全库LuaLS/preflight。

## 未验证

真实多仓路径、连续取放与取消/保存重进待用户实机；未测量帧耗时。未提交、推送或上传工坊。
