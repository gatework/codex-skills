# Motor 业务生命周期与跨层不变量

处理账户、凭证、角色、用户代入、用户设置、通知、审计、生命周期任务、数据保留、字典等需要跨 controller/model/service/job/frontend 的业务流程时读取本文件。设计**新的**业务动作或需要一套可复用的建模模板（动作卡、状态流、语义矩阵）时，另读 [business-modeling.md](business-modeling.md)。

## 目录

- [先画业务状态流](#先画业务状态流)
- [身份生命周期](#身份生命周期)
- [Authority 变化后的撤销与收敛](#authority-变化后的撤销与收敛)
- [用户与角色不变量](#用户与角色不变量)
- [用户设置是加密聚合](#用户设置是加密聚合)
- [通知事件与投递分层](#通知事件与投递分层)
- [安全性 destructive workflow](#安全性-destructive-workflow)
- [审计与历史保留](#审计与历史保留)
- [字典与稳定业务标识](#字典与稳定业务标识)
- [跨层业务变更检查](#跨层业务变更检查)

## 先画业务状态流

不要从页面按钮或单个 controller action 开始设计复杂业务。先回答：

1. 当前 authority/durable state 是什么；
2. 哪个 actor 可以发起；
3. 前置验证是什么；
4. 哪个状态转换必须原子；
5. 哪些 credential/session/projection 会失效；
6. 哪些外部副作用允许重试或重复；
7. 哪些审计证据必须保留；
8. 前端如何收敛到新状态。

对身份、安全和 destructive workflow，状态流比 CRUD 结构更重要。

## 身份生命周期

Motor 的自服务身份能力不是互不相关的端点，应按生命周期理解：

```text
registration settings
  -> email verification challenge
  -> registration
  -> captcha + password login
  -> optional MFA challenge
  -> UserSession + JWT
```

账户建立后还存在：

```text
contact verification -> contact change
password forgot -> reset verification -> password reset
MFA setup -> confirm -> recovery code lifecycle -> disable
session refresh / role switch / impersonation -> credential rotation
logout / revoke / disable -> credential invalidation
```

规则：

- 一次性 challenge 具有明确目标、过期、尝试次数和消费语义；
- challenge 成功不能被并发重复消费；
- 登录、MFA、reset、contact change 等不同流程不要共享含义模糊的 token；
- 公开/半公开身份端点需要独立 rate limit 和枚举泄露审查；
- 返回用户的错误应可操作，但不能泄露账号是否存在、secret 或内部异常。

## Authority 变化后的撤销与收敛

以下变化会改变用户可做什么：

- 密码变更/重置；
- 账户禁用/恢复；
- 角色切换；
- 角色权限变化；
- API Token 撤销或角色权限收缩；
- 用户代入开始/结束；
- MFA 安全状态变化。

对每种变化都检查四层：

1. **数据库 authority**：session/token/role/status 是否已更新；
2. **credential**：旧 JWT/API Token 是否仍可用，是否需要轮换/撤销；
3. **projection**：Redis online state、Cable subscription、tabs/cache 是否清理；
4. **UI**：当前 route、按钮、数据和 pending request 是否按新身份重算。

不要只“换 token”或只“刷新用户信息”。身份变化是系统状态迁移。

## 用户与角色不变量

### 用户

- `username` 是登录和审计的稳定标识，创建后不因显示名称变化而改变；
- disabled 与 deleted 不同。禁用需要拒绝全部认证方式并按现有策略撤销 credential；
- 有 logs、API tokens、sessions 等操作历史时，删除默认受阻，不能为了 CRUD 顺手 cascade；
- 自动生命周期动作必须保护最后一个有效管理员等全局安全条件；
- 用户写操作需要目标对象和角色范围的防提权校验，不能只校验 action permission。

### 角色

- 角色权限是当前 authority，不是 token 创建时永远冻结的副本；
- API Token 有效权限取 token scope 与角色当前权限交集；
- 角色仍被用户/API Token 关联时默认阻止破坏性删除；
- 权限集合整体替换必须定义并发语义，不能让两个并发编辑互相无声覆盖。

### 管理员

“至少保留一个可用管理员”属于跨记录全局不变量。锁目标用户本身不足以保护它，所有竞争者必须争用共同序列化点或使用等价原子策略。

## 用户设置是加密聚合

Motor 把 UI preferences 与 notification channels 放在同一 `users.settings` 加密字段中，并由 `Motor::UserSettings` 维护结构、锁、脱敏、容量和 secret merge。

因此：

- 不在 controller、job、脚本或前端同步逻辑中直接 `update!(settings: ...)` 覆盖整列；
- 偏好更新与通知渠道更新必须共享同一用户行锁，否则会发生 lost update；
- 更新渠道配置时保留未回显 secret，空字符串不能意外擦除已有密钥；
- 前端公开设置只获得允许的 preferences/目标摘要，不把 webhook URL、签名密钥、Authorization header 等回显；
- 系统必需渠道及账户邮箱渠道遵循现有生命周期，不把它们当普通自由 CRUD 数据；
- 修改 settings schema 时考虑版本、旧缓存/旧数据、体积限制和并发迁移。

如果业务复杂度未来超过单行聚合的可维护边界，先证明真实查询、并发或生命周期需求，再设计迁移到独立表；不要提前拆表，也不要因“JSON 不优雅”重构。

## 通知事件与投递分层

保持三层语义：

```text
business event
  -> durable notification
  -> durable dispatch intent
  -> queue
  -> provider / in-app projection
```

规则：

- 业务模块调用统一 dispatcher/notifier 发布事件，不直接调用邮件、飞书或 webhook adapter；
- `event_type` 是稳定业务标识，不用可翻译标题作为程序分支；
- 同一业务执行需要稳定 deduplication key；
- notification archive/read 与 delivery success/failure 是不同状态；
- 清空用户通知优先归档，不因此删除投递和审计证据；
- 当前 ref 的具体状态先查 schema、NotificationPublisher 与两个通知 job；派发意图/加密载荷不等于渠道成功记录，不能假定独立 delivery 模型；公开 API 不返回 secret；
- HTTP 首次加载与 Cable 消息可能重复，前端按稳定 notification ID 去重并允许 HTTP reconciliation。

Provider 的 claim/retry/at-least-once 细节读取 `async-realtime-observability.md`。

## 安全性 destructive workflow

账户自动禁用、审计日志清理等不是普通定时 CRUD。核心模式：

```text
eligibility
  -> prerequisite evidence
  -> notice succeeds
  -> persist notice/deadline
  -> grace period
  -> re-check safety invariant
  -> destructive action
```

必须保持：

- 第一次扫描不能同一轮既提醒又执行禁用/删除；
- 缺少必要通知对象或通知能力时 fail-closed，不继续 destructive action；
- 到达 deadline 后再次检查当前状态，不假设资格从提醒时起不变；
- destructive action 前重新保护最后管理员、当前活动、法定/审计保留等不变量；
- 批量清理分批执行，避免长事务和大锁；
- 审计中能解释“为什么现在执行”。

### 外部通知与数据库锁的冲突

安全流程常要求“通知成功后才开始宽限期”，但 SMTP/provider I/O 又不应长期占用数据库锁。

如果改造现有流程，不要简单把 I/O 移出锁后就认为完成。应显式解决：

- 两个 worker 同时发送通知；
- provider 成功但 deadline 未持久化；
- 部分管理员通知成功、后续发送失败；
- retry 导致重复提醒；
- worker crash 后如何判断是否可以继续。

高可靠方案优先把“notice intent / delivery / acknowledged prerequisite / deadline”建模为 durable state，再让独立阶段推进 destructive action。若当前业务接受重复提醒，也必须保持“不提前破坏”的安全方向并写测试。

## 审计与历史保留

Motor 同时存在 HTTP 操作日志、模型审计、会话/token 历史、notification 与当前实现实际保留的派发/任务证据面。

审计设计至少保留：

- request/job correlation ID；
- 真实 actor；
- target/subject；
- credential/impersonation 上下文；
- 稳定 action/event identifier；
- 时间、结果和必要的安全摘要。

原则：

- 用户代入时 actor 与当前 user 不能混为一人；
- 归档、撤销、禁用优先于抹除历史；
- 物理删除有独立 retention 规则与操作证据；
- RailsAdmin 不应成为修改只读审计历史的旁路；
- 可观测性先脱敏，不能为了排障保存完整 Authorization、Cookie、验证码、secret config 或 provider 响应。

## 字典与稳定业务标识

Motor dictionary 适合管理需要后台维护、但程序仍依赖稳定 code/key 的参考数据。

保持：

- dictionary `code`、entry `key` 是稳定机器标识；
- `label/description` 才是可翻译/可显示内容；
- value type 与数据库约束保持一致；
- 排序位置、enabled 状态和唯一性有明确契约；
- 不把 permission、security enum 等核心安全状态偷偷变成可自由编辑字典；
- API/前端展示字典值时保留未知值的安全降级，而不是让页面崩溃。

## 跨层业务变更检查

业务流程修改完成前逐项检查：

1. route/action 与 permission key 是否改变；
2. credential type 是否仍正确；
3. 数据库状态、约束、索引和并发策略是否完整；
4. 失败路径是否保持 fail-open/fail-closed 的正确方向；
5. session/token/projection 是否需要撤销或重建；
6. audit actor/target 是否仍准确；
7. 通知/外部 I/O 是否有 durable state、重试和重复语义；
8. 前端 route/store/tabs/Cable/pending request 是否收敛；
9. 两种语言、错误 code/message 和用户下一步是否明确；
10. focused test 是否能证明关键不变量，而不只是成功路径。
