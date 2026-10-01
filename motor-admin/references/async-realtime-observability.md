# 异步、实时、Redis 与可观测性

处理 Sidekiq、通知投递、Action Cable、在线用户、Redis、请求日志、异常通知、保留策略时读取本文件。

## 目录

- [先分类状态](#先分类状态)
- [Sidekiq 的基础语义](#sidekiq-的基础语义)
- [Expected 与 Unexpected Failure](#expected-与-unexpected-failure)
- [Claim -> I/O -> Result](#claim---io---result)
- [远端成功后的崩溃窗口](#远端成功后的崩溃窗口)
- [入队与 Commit Boundary](#入队与-commit-boundary)
- [定时任务与去重](#定时任务与去重)
- [Action Cable](#action-cable)
- [前端实时去重](#前端实时去重)
- [Redis 隔离与失败模式](#redis-隔离与失败模式)
- [Request ID 与审计链](#request-id-与审计链)
- [异常通知](#异常通知)
- [可观测性信号与健康语义](#可观测性信号与健康语义)
- [保留与清理](#保留与清理)


## 先分类状态

设计失败行为前先判断状态属于哪类：

| 状态 | 权威来源 | 可否重建 |
| --- | --- | --- |
| 用户/角色/session/token | PostgreSQL | 否，durable |
| 通知与派发意图 | 当前 schema 中的 PostgreSQL 记录；先核对是否另有投递结果 | 否，durable |
| Sidekiq queue | Redis | 有条件，可重试 |
| 在线用户/最后活动投影 | Redis | 是 |
| 普通缓存 | Redis | 是 |
| rate-limit state | Redis | 可恢复但安全敏感 |
| Cable connection | 内存/Redis + DB session authority | 是 |

可重建 projection 失败时应降级；durable authority 失败时不能用旧缓存“继续授权”。

## Sidekiq 的基础语义

按 at-least-once 设计，不假设 exactly-once：

- job 参数传 ID 或必要的小 JSON/加密快照，不传活的模型对象或明文秘密；
- 执行时重新加载权威记录；
- 重复执行不制造重复业务结果；
- 将业务 idempotency 与 Sidekiq retry 分开设计；
- timeout、网络错误、进程崩溃都可能导致重复执行。

## Expected 与 Unexpected Failure

Expected business failure 例如“渠道被禁用”“目标已归档”“状态不再允许投递”：

- 写成可理解的业务状态；
- 必要时标记 skipped/cancelled/failed；
- 不用无限异常重试制造噪音。

Unexpected/transient failure 例如 provider timeout、临时 5xx、Redis/网络波动：

- 抛出异常让 Sidekiq retry；
- 保存安全、截断后的错误摘要；
- 不吞掉错误后把 delivery 标成成功。

## Claim -> I/O -> Result

需要认领和结果持久化的外部流程可采用短锁模式；先查实际模型，不把它当当前通知 job 的事实：

1. transaction/lock：确认可处理并 claim；
2. commit，释放数据库锁；
3. 调用 provider；
4. 新 transaction：写 delivered/failed/receipt；
5. 广播或后续通知。

不要持有 DB row lock 等待外部 HTTP。

## 远端成功后的崩溃窗口

最危险窗口：

`provider 已成功 -> worker 崩溃 -> DB 未写 delivered -> retry 再次发送`

不能用数据库事务消除远端副作用。

按能力选择：

- provider 支持 idempotency key：使用稳定 delivery/event ID；
- webhook 下游可去重：发送稳定 event/delivery id；
- provider 无去重：明确 at-least-once，审计允许识别重复；
- 对不可重复的高价值外部动作，必要时引入 provider receipt/query/reconciliation，而不是假装 exactly-once。

## 入队与 Commit Boundary

job 若依赖刚写入的 DB 状态，必须避免“事务未提交但 job 已开始”：

- 优先使用框架已有 enqueue-after-commit 语义或明确的 service 提交边界；
- rollback 时不应留下指向不存在记录的任务；
- 不用 model callback 隐藏复杂跨系统流程；
- 内部 transaction 结束不代表外层提交；测试外层 commit/rollback；
- 检查 Active Job 返回 false 与 enqueue_error，不只 rescue；延迟入队返回 job 不表示实际队列接受；
- 提交后仍有入队故障窗口，按可靠性需求保留 durable intent 与恢复扫描，不默认新建 delivery 表。

## 定时任务与去重

- 计划任务使用稳定 deduplication key；
- 同一个业务周期重复扫描不能重复生成相同通知/动作；
- “先提醒，宽限期后再执行”必须把提醒成功和 deadline 持久化，不能一次扫描同时提醒又禁用/删除；
- 全局安全条件，例如最后管理员、无可投递管理员时的 fail-closed，需要全局序列化和专门测试。

## Action Cable

- 长期 JWT/API Token 不进 URL；
- 客户端先通过 HTTP 获取短期 cable ticket；
- ticket 绑定 session/token version；
- Connection 建立时重新验证服务端会话；
- channel 订阅时再验证当前角色权限；
- session revocation/role switch/impersonation/logout 后旧订阅断开并按新身份重建；
- WebSocket 失败不阻断普通 HTTP 页面。

## 前端实时去重

HTTP initial load 和 Cable event 可能同时出现同一 notification：

- 使用稳定 notification/event ID 去重；
- 未读计数不能简单“每条 Cable +1”，也不能由分页列表推导全量总数；HTTP 旧快照不能覆盖期间新事件，使用协议版本或明确对账策略；
- reconnect 后允许通过 HTTP reconciliation 回到权威状态；
- 不把 client 内存计数当 durable truth。

## Redis 隔离与失败模式

不同用途最好使用独立 logical DB/instance/namespace，并明确故障影响：

- Sidekiq；
- Cable；
- cache；
- rate limit；
- online projection。

尤其不要让普通 cache flush 顺带清空关键 rate-limit state。在线 projection 不可用时允许功能降级，但不能影响 DB 授权判断。

## Request ID 与审计链

一次 HTTP 请求应能串联：

`request_id -> actor -> target -> credential context -> operation log -> error notification -> async follow-up`

记录：

- request ID；
- actor/target；
- 安全过滤后的参数；
- status/duration；
- 必要的资源标识；
- 错误类型和安全摘要。

不要记录 Authorization、Cookie、密码、验证码、token、secret URL 或完整敏感 provider 响应。

## 异常通知

- API 未捕获异常和 Sidekiq error handler 都可进入统一 ExceptionNotifier；
- 通知任务自身必须避免递归告警；
- 外部通知失败不应覆盖原异常证据；
- 日志队列不可用时核心请求仍有明确降级策略；
- 告警中保留 request/job context，但先脱敏和截断。


## 可观测性信号与健康语义

日志只能回答“发生了什么”，生产诊断还要确认能否看到趋势与饱和：

- HTTP：request rate、5xx/429/auth failure、latency；
- Rails/Puma：threads、queue/backlog、DB pool wait；
- Sidekiq：queue latency、retry/dead、job duration/failure；
- PostgreSQL：connections、slow query、lock/statement wait；
- Redis：latency、memory/eviction、connections；
- provider：success/failure/timeout/rate-limit；
- Cable：connect/reject/reconnect。

metric label 保持低基数；不要把 user id、request id、完整 URL、error message 等高基数/敏感值放进 labels。request/job id 适合日志或 trace correlation，不适合作为长期 metric dimension。

区分：

- liveness：进程是否需要重启；
- readiness：当前实例是否可以接流量；
- dependency degradation：某个外部渠道不可用是否应该让核心 API 整体不 ready。

告警优先用户影响和持续症状，不为每一次 retry/单个异常报警。release/deploy 时保留版本/digest marker，便于把错误率和 latency 变化关联到具体发行物。若项目当前没有 tracing/OTel，不因“可观测性最佳实践”强制引入；先复用已有日志、metrics 和平台能力。

## 保留与清理

删除日志/历史前定义：

- retention period；
- legal/audit 最小保留；
- 分批删除策略；
- 谁可配置；
- 清理失败是否 fail-closed；
- 是否需要提前通知管理员。

高风险清理不与首次提醒同一轮执行。
