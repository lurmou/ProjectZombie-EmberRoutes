# Java 搬运与配送读取路径实施计划

用户已授权优先Java并参考ProjectRemnants；沿现有唯一身体/资产协议实施，不另建执行器。基线为本会话0.29.23工作树。

1. 核对参考当前NPCFW.jar及安装游戏API；参考只读，独立实现。Java规划/批量处理可借鉴职责，TaskRunner/独立库存提交不迁入。
2. 增加 InventoryIndex.begin/step/index，将 InventoryView 的整个有界扫描循环与重复ID索引移到Java。沿用2000件单容器限额、列表身份/大小变化语义、原件实例与duplicate count；Lua保留无桥宿主路径。
3. 增加 DeliverySelection.scan(source,npc,sourceId,requests,owners,state,budget)。Java原生扫描、请求索引、排除Claims/保护物品、容量/负重和来源累计；读取当前唯一owners，不认领/写Job。Lua只提供端点政策和来源切片编排。ModData元方法保留显式Lua能力回退，不当成可直接读取的原始字段。
4. DeliverySelection.received(order,payload)实现收货投影；Lua提交仍是唯一权威，不保存Java业务账本。
5. 在ProbeRuntime暴露批量接口，接通生产调用；保留单件activeAttempt/物理核对/停止与恢复，不改变已确认配送范围和256件记录上限。
6. 必要检查：新增Java数据/实际ItemContainer边界检查、现有配送/改道/连续动作定向回归、编译与构建。实机、磁盘恢复和帧性能交用户，不重复全套测试。

预期减少：逐物品get/ID/type/weight/eligible跨语言读取，Lua逐请求匹配循环和库存索引循环。未测量不宣称实机性能提升。

实施状态：步骤1～5已接，步骤6必要宿主检查通过；构建记录与未验证边界见[证据](../../reviews/2026-11-02/java-haul-read-paths.md)。实机未验收，不宣称整体Java化或性能达标。
