# 工单结清清理

日期：2026-10-24｜版本：0.24.2｜依据：用户本轮批准“做完消失、未结保留”，覆盖旧禁止自动删除完成历史的限制。

## 行为

- 公共Order、制作和搬运Job在交付/取消归还完成、效果已知、原件及容量声明解除、身体会话与待启动候选结束后删除。只删除记录，不调用物品删除或按类型补造。
- 暂停、缺料、待归还、UNKNOWN、提交中、保存阻塞及尚需原任务恢复的记录保留。已恢复的工作完成早于自理观察时，RESTORE_QUEUED可根据其确定完成事实标RESTORED，个人托管不随之释放。
- 持续SELF_CARE记录继续用于有限attempt与恢复，不属于公共工单历史。普通任务删除通过唯一JobStore同步维护byNpc及容量计数，未建第二份历史账本。
- 每200ms在正常主循环末检查，最多清8张公共单及8个独立Job；正常已知终态旧记录同样按证据清理。不会在原生完成回调栈里删除，不因记录缺失推测交付成功。
- 公共单清理同步退出目录、清理最低存量activeOrder、旧预检请求及失败冷却；下一次补货仍须库存刷新与重新观察。未结单不会因最低存量规则关闭而删除。
- 下单token由PublicWork签发，签发/完成技术回执共最多128条。现有活动单保持幂等；完成单的近期重试只确认原ID，不重建工单。回执过期后返回REQUEST_EXPIRED，不将未知旧token当新意图。UI与最低存量改用签发token；提示为中英文。无永久业务历史、无新增历史页面。
- 旧执行现场继续受Session/attempt代次保护；删除后旧完成/停止回调不能写回Job或再次制作。清理仅移除确切旧Job的NPC索引及保存引用，不影响同NPC的新工作。

## 代码与验证

JobStore.removeSettled为受限终态删除；LaborStore.hasTaskClaims只读核查真实协调声明；BusinessJobs负责业务和身体证据；PublicWork负责公共关联及有界请求回执；TaskRetirement在Boot正常tick接线。UI仍消费现有监控投影，结清记录移除后从列表消失。

安装基线由本轮build-probe校验：PZ42.21.0 JAR SHA256 E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33；未改变Java实现。改动前modscan扫描143个Lua，无已安装模组整文件路径冲突。

定向Kahlua通过：JobStore26、清理16、公共协调51、受控制作最终66、保存61、诊断保存12、自理恢复23、生活组合20；下层已有夹具不重复计为新增覆盖。新用例含300张取消公共单、600个完成Job不触顶、未停稳/声明未清/UNKNOWN/恢复依赖不得删除、同NPC后续工作不被误删、删除后原生制作perform/stop迟到不重放、真实取消归还后清理及缺失原件取消不得清理。

监控22、配方偏好/请求16项通过；正式CN/EN翻译驱动的完整界面各713项及物流页面各33项通过，翻译文本/原生文本测试通过。裸占位翻译的直接界面运行不作为布局结果，最终以tools/test-ui-kahlua.ps1 -SettlementTabs -Language CN/EN为准。

原始日志：build/logs/task-retirement-regression.txt、task-retirement-production-final.txt、task-retirement-ui-regression.txt（含不使用正式翻译的失败尝试）、task-retirement-ui-CN.txt、task-retirement-ui-EN.txt及task-retirement-ui-translated.txt。

0.24.2构建成功，最终归档151文件与当前源码逐项一致；release-check为0错误/78提示，文档检查5文件0断链，空白检查通过。完整preflight已运行：结构/规范/索引通过、LuaLS 0错误/213信息性警告；首次只有lua_lint因人员页原版tryGetTexture未登记白名单而失败。当前安装原版ISUI/AdminPanel/ISItemsListTable.lua:468直接调用同一函数，已在共享.workbuddy/lua_lint.js补登记这一个全局，未改变人员UI；源码不变后仅复跑失败层，144文件0错误/1条既有比例布局提示。原版ISFluidEmptyAction.lua的0.0f解析覆盖缺口保留。原始完整preflight的非零结果保留，不改写成整条命令成功；各层通过的最终证据由该输出及task-retirement-lua-lint-final.txt组合记录。

构建/归档/发布/文档/空白输出位于build/logs/task-retirement-{build,package,release,doclink,whitespace}.txt。游戏实际完成消失、取消收尾及正常保存重进尚未复测；宿主身体/库存/原生制作效果使用替身，不宣称实机、故障磁盘或性能验收。

本轮保留全部并行仓储/UI/P2修改，不提交混合工作区或发布工坊。
