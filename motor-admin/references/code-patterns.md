# 实现范式与反例

用于落地具体功能。以下是审读目标 ref 的定位路线和有条件的实现建议，不是必须新增的框架，也不保证列出的源码已无缺陷。任何形状示例均需适配实际 API；不复制占位类名、权限键或测试设施。

## 后端范式

### B1 列表查询

从 `Motor::ApplicationController#order_collection` 和资源 controller 读取实际排序、分页与授权范围。排序列/方向使用 allowlist，追加稳定主键；参数原始类型和范围由契约决定，不能先 `to_i` 再把非法输入当正常页码。

预加载 serializer 实际读取的关联，依据查询数量与规模优化。`exists?`、`pluck`、`find_each` 都有适用边界，不能机械替换已加载集合或业务排序。

### B2 状态转换

先判断是否需要 validation、callback、审计或关联变更。简单转换可用条件 UPDATE 并检查受影响行数；复杂领域动作可在 `with_lock` 内重检并 `update!`。二者都需数据库约束，不是统一选一种语法。

`with_lock` 自带事务并重新加载；`lock!` 需由调用者维持事务。内部事务块返回不证明外层已提交。客户端编辑冲突还需版本校验，不能仅靠串行行锁。

### B3 聚合更新

阅读 `Motor::UserSettings#mutate!`：用户行是聚合写的共同锁，锁内从存储值构造副本、修改、检查容量并保存。不要把旧内存副本整列写回。公开偏好与秘密渠道分开输出。

这个形状用于同一聚合的 read-modify-write；所有竞争写入口都要参与。领域允许的 `false` 不应被 `present?` 或 `compact_blank` 意外丢弃；具体配置字段仍需查 schema。

### B4 全局不变量

阅读 `AccountLifecycleJob#with_administrator_guard` 与调用方。保护“至少一个可用管理员”需要共同序列化点，单独锁两个用户不够；还要覆盖角色变化、人工禁用等相关竞争入口。

不要仅因当前自动任务已有 guard 就宣称全项目不变量已证明。也不要把某个 advisory lock 常量复制到其他业务。

### B5 一次性 credential

沿 MFA challenge、recovery code、session 版本的实际读写路径检查。要求一次性时，消费条件必须与写入原子化；并发请求只能有一个获准继续，失败后不能泄露 challenge 内容。

条件 UPDATE 或锁内领域操作均可。检查消费之后的失败是否导致不合理的重放、丢失或越权；不要只测试验证码正确。

### B6 外部效果与执行归属

阅读 `Motor::Netconf::Executor`：认领后锁外 I/O，结果和错误落地前检查 attempt 与 terminal 状态。临时超时保留执行未知，稳定幂等键用于远端重试。还要检查取消、恢复、dispatcher 和 client 的完整链路。

这不是当前通知系统的统一实现。通知沿 `NotificationPublisher -> NotificationDispatchJob -> NotificationJob -> adapter`；核对 schema 中的派发意图和加密载荷，不臆造 Delivery 模型或声称已有渠道成功记录。

### B7 提交与入队

任务依赖 DB 状态时，检查**最外层**提交边界。支持的 Rails 版本可使用 `ActiveRecord.after_all_transactions_commit`；普通 service 内部 transaction 后 enqueue 仍可能运行在外层事务中。

同时检查 adapter 抛错、`perform_later` 返回 `false` 和 callback 中止。立即入队可保留 job 实例检查 `enqueue_error`；延迟入队返回 job 不表示队列已接受。数据库提交后仍需按业务可靠性要求保留补偿依据。

Motor 的 pending 扫描需要“继续健康项 + 暴露首个/聚合失败”，不要将无异常等同于成功。测试应从 adapter 注入拒绝，而不只是 stub `perform_later` 抛错。

### B8 Migration

读取当前部署政策与 migration 历史。需要旧新共存时扩展、回填、验证后收缩；删除旧结构以旧消费者退出为条件，不固定为“下一个发布”。已共享执行的迁移用新迁移修正，未共享可重建场景遵循项目明确政策。

## 前端范式

### F1 请求归属

阅读 `hooks/request-state.ts` 与实际调用者。它能丢弃旧返回值，但不能撤销 request callback 内已发生的 reactive 写入。

以下是调用形状示意，`request/rows` 需替换为实际变量：

```ts
const response = await execute(() => request());
if (response === undefined) return;
rows.value = response.data;
```

不要在 `request` 内先写 rows。检查成功、错误、finally、关闭与身份切换；若下一步还有 await，提交前重新校验归属。若项目已有统一的 request → guard → commit，直接复用。

### F2 查询与分页

沿现有 `hooks/pagination.ts`、页面 filters 和 API 参数定位单一查询输入。筛选变化按项目交互重置页码，删除末页最后一项后修正分页。不要另建全局列表 store 或把 API envelope 换成示例形状。

### F3 表单编解码

UI 与 API 不同形时提取局部纯转换；保留缺失、null、false、日期和 ID 的契约。转换可能有损，验证 round-trip 的业务字段，不强制数学意义上的完全可逆。

### F4 编辑器生命周期

初始化条件是新编辑会话或对象切换，不是所有 props 刷新。选项列表更新不能覆盖草稿；提交失败保留输入和待上传文件。组件关闭/切换后，晚到请求不得写旧表单。

同一记录的附件操作可以合并附件元数据；更新 lock_version 前确认变化属于当前编辑会话且其他字段未被别人修改，不能无条件吸收外部新版本。回归同时覆盖草稿保护与编辑冲突。

可编辑嵌套 form 通常用 `reactive/ref`；`shallowRef` 只用于明确按整体替换的结构，不因对象大就替换。

### F5 权限投影

先读 `hooks/permission.ts`、user store 与该业务 capability 文件。`usePermission` 的实际接口可能用于路由判断，不能假设有 `can()`。权限键从后端目录取得，不能把 `users.reset_password` 之类示例键当作实际 `资源#动作` 契约。

页面可以形成语义化能力，但后端依旧验证凭证、资源和动作；前端隐藏不是安全证明。

### F6 HTTP 与实时对账

阅读 notification store 的 lifecycleVersion、connectionVersion、inboxVersion 与对应测试。身份、socket 和收件箱变化不是同一失效范围。HTTP 快照晚到不能抹掉已收到的消息或 mutation。

分页列表不是完整集合，不能从当前页推导全量 unread count。任意 ISO 时间戳也不保证可用字符串排序，优先协议 revision/cursor；没有时采用明确的事件代次与对账策略，承认持续事件流和分页外事件的限制。

## 验证范式

### T1 数据库并发

使用独立连接、已提交 fixture 和显式阶段信号。正确锁会阻止第二个线程进入临界区，因此不要在锁内放要求两个线程同时到达的 barrier，再依靠超时让测试继续。

可以让主线程持有共同锁，观察 worker 到达竞争入口及数据库阻塞，再释放锁、验证重读与最终不变量。超时令测试失败，失败清理释放阻塞并回收线程。数据库可观察状态的有限轮询不同于靠 sleep 猜顺序。

可参考 `spec/services/motor/devices/inventory_snapshot_concurrency_spec.rb` 的数据库阻塞观察方式；仍需核对当前测试和隔离环境，不把示例当已完成验证。

### T2 前端乱序与草稿

用 deferred Promise 分别制造旧请求在新请求 loading 时、成功后和失败后返回；覆盖 scope dispose、身份切换与 callback 内副作用。断言数据、loading、error，而非仅断言旧返回值为 undefined。

草稿用实际组件交互和 `setProps` 驱动：输入 → 刷新选项/同 ID 记录 → 验证保留；切换记录/明确放弃 → 验证重建。shallowMount 能证明部分状态行为，不能证明完整 UI、焦点或浏览器效果。
