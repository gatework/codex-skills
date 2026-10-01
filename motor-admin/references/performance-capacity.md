# 性能、容量与资源边界

处理慢查询、大表、高并发、Sidekiq 堆积、前端卡顿、bundle 体积或生产容量评估时读取本文件。默认先测量，不凭感觉优化。

## 目录

- [什么时候进入性能模式](#什么时候进入性能模式)
- [Rails 与 PostgreSQL](#rails-与-postgresql)
- [索引与 Migration](#索引与-migration)
- [连接池与 Sidekiq](#连接池与-sidekiq)
- [Redis 与外部服务](#redis-与外部服务)
- [Vue 与网络负载](#vue-与网络负载)
- [性能证据](#性能证据)

## 什么时候进入性能模式

出现以下证据再进入性能整改：

- 页面/接口真实慢、P95/P99 或队列 latency 异常；
- 大表列表/搜索/排序、N+1、重复 count；
- migration/backfill 可能长锁；
- 高 fan-out 通知/批量操作；
- 前端大列表、明显重渲染、首屏 bundle 过大；
- Puma/Sidekiq 并发调整会改变 DB/Redis/第三方连接压力。

没有数据时先建立可重复基线。不要发明毫秒、QPS、bundle KB 等阈值；预算来自当前产品目标和实际环境。

## Rails 与 PostgreSQL

慢查询审查优先看：

1. query shape 和返回行数；
2. N+1/preload；
3. filter/sort/pagination 是否命中合适索引；
4. 是否重复加载可推导数据或执行昂贵 count；
5. serializer/payload 是否读取不必要关联/字段；
6. 事务是否持锁过久。

使用 `EXPLAIN` 阅读 scan、join、sort、估算行数和索引选择。`EXPLAIN ANALYZE` 会真正执行语句；对写语句或生产数据只能在明确安全边界内使用，不把“分析性能”变成数据修改。

优化前后记录同一代表性输入、数据规模和计划/耗时，不用本地空数据库证明生产性能。

## 索引与 Migration

索引不是默认答案：

- 根据真实 filter/join/sort workload 设计，不为每列建索引；
- 新索引后确认 planner 能使用，并关注统计信息；
- 大表普通 `CREATE INDEX` 可能长时间阻塞写入，生产策略需结合当前 PostgreSQL 版本评估 concurrent build；
- `CREATE INDEX CONCURRENTLY` 有独立限制和失败状态，不能机械套用；
- backfill 分批、可恢复，避免单个大事务；
- constraint/index rollout 与旧新代码兼容窗口一起设计。

## 连接池与 Sidekiq

修改 `RAILS_MAX_THREADS`、Puma workers、`SIDEKIQ_CONCURRENCY` 前做连接预算：

`web 最大并发连接 + worker 最大并发连接 + migration/admin/cron 余量 <= PostgreSQL/Redis 安全容量`

同时检查：

- Active Record pool 与实际线程数；
- Sidekiq job 是否长时间占 DB connection 做外部 I/O；
- 批量 job 是否形成 thundering herd；
- scheduler/retry 是否在故障恢复时放大流量；
- provider rate limit/SMTP/Webhook 配额是否低于本地并发能力。

提升 worker concurrency 不是解决慢 provider 或慢 SQL 的默认方式。

## Redis 与外部服务

- cache、rate-limit、Cable、Sidekiq 的 latency/error/memory 分开观察；
- 避免高基数 key 无 TTL 或无限增长集合；
- projection 可降级，authorization/durable state 不从 stale Redis 恢复；
- 外部请求设置 timeout，批量 fan-out 有并发上限和重试退避；
- 重试 storm 时优先限制放大效应，不靠增加线程硬顶。

## Vue 与网络负载

前端性能先确认瓶颈属于 network、JS、render 还是 DOM：

- 使用生产 build 和浏览器/Vue DevTools profiling，不用 dev 模式体感定结论；
- 大列表只在真实需要时考虑 virtualization；
- lazy load/code split 用于非首屏能力，不为了“最佳实践”把每个小组件拆 chunk；
- 避免在 template/render path 重建大对象、重复昂贵 computed 或无意义 deep watch；
- 保持稳定 `key`、减少不必要 prop/响应式依赖；
- API payload 只返回页面需要的数据，分页/搜索优先服务端处理。

`v-memo`、manual memoization、虚拟列表等属于有测量证据后的工具，不是默认模板。

## 性能证据

报告至少说明：

- baseline 环境/数据规模；
- 触发路径和输入；
- 修改前指标/plan；
- 修改后同条件指标/plan；
- 正确性回归测试；
- 资源代价，例如额外 index/storage/memory/connections；
- 仍未验证的生产特性。

没有 before/after 证据时写“性能风险已降低的代码层推断”，不要写“性能已提升”。
