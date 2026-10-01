# 后端、API 与数据库实践

处理 Rails API、PostgreSQL、CRUD、事务、migration、领域服务和数据一致性时读取本文件。

## 目录

- [分层先于抽象](#分层先于抽象)
- [API 契约](#api-契约)
- [列表与查询](#列表与查询)
- [数据不变量的双层保护](#数据不变量的双层保护)
- [并发原语选择](#并发原语选择)
- [集合整体替换](#集合整体替换)
- [全局不变量](#全局不变量)
- [事务与外部副作用](#事务与外部副作用)
- [Migration](#migration)
- [删除、禁用与历史](#删除禁用与历史)
- [RailsAdmin 运维面](#railsadmin-运维面)


## 分层先于抽象

默认职责：

- Controller：参数、认证授权边界、资源定位、调用流程、选择 serializer、返回状态码。
- Model：关联、validation、数据库映射、领域不变量和小型原子领域操作。
- Service：跨模型事务、复杂状态迁移、外部集成、可独立测试的业务编排。
- Query/Scope：复杂筛选、稳定排序、数据范围。
- Serializer：稳定 API 字段和响应结构。
- Job：异步执行、claim/retry、结果状态，不重新定义领域规则。

不要因为 controller 超过某个行数就机械创建 service。只有业务流程、事务边界、复用价值或可测试边界明确时再提取。

## API 契约

Motor 的成功响应保持：

```json
{
  "data": {},
  "meta": {}
}
```

新增可预期业务错误优先使用：

```json
{
  "code": "stable_machine_code",
  "message": "当前语言下可理解的错误说明"
}
```

需要字段级信息时可附加 `errors`，但不能改变 `code/message` 的语义。

规则：

- `code` 稳定、不可翻译，前端可以据此选择交互；
- `message` 由 Rails i18n 输出；
- 不让前端解析 Ruby exception 文本；
- 现有仅 `message` 的通用 Active Record 错误允许渐进迁移，不为“统一”一次性重写全部接口；
- 201 表示资源已创建，202 只表示异步任务已接受，不宣称远端副作用完成；
- 403 与 404 的选择不能泄漏不应公开的资源存在性。

## 列表与查询

- 分页统一读取项目现有 `page/per_page` 约定；
- `per_page` 必须有上限；
- 排序字段使用 allowlist，不直接将客户端参数传给 `order`；
- 默认排序必须稳定，必要时追加主键作为最终排序；
- 枚举筛选校验允许集合；
- 模糊搜索对大表考虑索引、前缀匹配或专用搜索能力，不默认堆 `%keyword%`；
- 防止 N+1，serializer 需要的关联在 query 层主动预加载；
- 数据范围由后端决定，不依赖前端传入“允许 ID 列表”。

## 数据不变量的双层保护

业务约束先问两个问题：

1. 用户怎样得到可理解的错误？
2. 两个事务并发时数据库如何阻止非法状态？

通常需要同时使用：

- model validation：面向业务反馈；
- NOT NULL、UNIQUE、CHECK、FK、index：保护持久化事实。

不要把 Ruby validation 当成并发锁，也不要用数据库异常代替全部业务提示。

## 并发原语选择

先定义“保护的是什么”，再选原语：

| 场景 | 优先考虑 |
| --- | --- |
| 单行 read-modify-write | `with_lock` / `lock!` / conditional update |
| 客户端编辑冲突 | optimistic locking / version 字段 |
| 只能存在一条 | UNIQUE + 捕获冲突 |
| 状态只能从 A 到 B | 简单转换用条件 UPDATE；需领域生命周期时锁内重检与更新 |
| 一个 aggregate 下的多记录整体替换 | 锁稳定 parent/anchor + transaction |
| 跨不同记录的全局不变量 | advisory lock 或专用 singleton/anchor row |
| 去重、唯一任务/事件 | 数据库唯一键或稳定 dedup key |

重要：`transaction` 本身不会把两个不同记录上的事务串行化。`with_lock` 已建立或加入事务，`lock!` 需要调用者维持事务；外层事务存在时，内部块结束不是提交或释放锁的证明。

## 集合整体替换

角色权限、用户角色、配置成员等“先删再插”的 replace 操作要显式定义并发语义：

1. 锁稳定 aggregate/parent；
2. 在同一事务内校验输入；
3. 计算 desired/current diff；
4. 只执行必要 insert/delete，避免无意义全删全建；
5. 数据库保留唯一约束作为最后防线；
6. 对同一 aggregate 的双连接并发更新写测试。

如果业务明确是 last-write-wins，也要通过同一个锁或版本控制让“最后”具有确定含义。

## 全局不变量

“至少一个有效管理员”“全局只有一个 active 配置”等约束不能只锁当前目标记录。

检查模式：

1. 两个 worker 能否锁不同记录；
2. 二者是否都能看到旧的 count/状态；
3. 二者是否都通过检查并写入；
4. 最终是否违反全局不变量。

需要所有竞争者争用同一个序列化点。

## 事务与外部副作用

- 不在持有数据库锁时做慢 HTTP、SMTP 或 provider I/O；
- 需要依赖“已提交数据”的 job/外部动作，要建立明确提交边界；
- Motor 已强调副作用显式化，优先 service 中的明确流程，不用隐藏 model callback 把跨系统行为藏起来；
- 若 enqueue 必须在 commit 后发生，使用 Rails/Active Job 已有 after-commit 能力或等价显式机制，并为回滚场景测试“任务不会看到不存在的状态”；
- DB commit 成功但外部副作用失败时，必须有可重试的 durable state，而不是靠 controller 再调用一次。

## Migration

按 expand/backfill/contract 思路处理危险迁移：

1. 先添加兼容字段/表/索引；
2. 大数据回填分批执行；
3. 新旧代码可短期共存时先部署兼容读写；
4. 验证数据后再加 NOT NULL/CHECK 或切换读取；
5. 最后删除旧字段/旧路径。

规则：

- 共享环境执行过的 migration 不修改，新增修正 migration；
- 大表避免一次性默认值回写、长事务和长时间独占锁；
- 生产索引策略要考虑在线创建能力；
- migration 后核对 `db/schema.rb`；
- schema、模型、serializer、前端类型和后台 job 的兼容窗口一起考虑。

## 删除、禁用与历史

优先区分：

- 删除业务实体；
- 禁用账号/配置；
- 撤销 credential；
- 归档通知；
- 清理无审计价值的子数据。

有审计、会话、token、投递历史价值的记录默认不级联硬删除。删除前检查 blockers，并通过 409 等稳定业务冲突告诉调用方。

## RailsAdmin 运维面

RailsAdmin 是运维入口，不是绕过 Motor 领域规则的后门：

- 敏感历史记录保持只读；
- 加密配置、JWT denylist、Active Storage 内部模型等不随意暴露；
- 账号、权限、通知状态的关键变更仍走领域服务或受约束操作；
- 后台登录与 Sidekiq Web 仍服从管理员启用状态。
