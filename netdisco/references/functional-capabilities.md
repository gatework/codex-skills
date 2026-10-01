# Netdisco 功能能力与扩展决策

新增功能、自动化、集成、运维控制或项目本地定制时读取本参考资料。它把产品需求映射到现有 Netdisco 机制，避免新增平行的队列、策略层、API 或页面框架。

**目录**：选择最小扩展面 · 动作/队列/扇出 · Worker 与驱动扩展契约 · 钩子与事件自动化 · 配置/ACL/凭据/标签 · 自定义字段与通用报表 · 认证/API/多租户 · 生命周期与运维 · 安全执行与诊断

## 选择最小扩展面

| 需求 | 现有能力 | 扩展位置 |
|---|---|---|
| 归一化某个厂商的网络数据 | SNMP::Info 公共方法契约 | SNMP::Info 设备类或协议 mixin |
| 在动作中采集或存储数据 | 使用共享 `vars` stash 的分阶段 Worker | Perl Worker 或 Python worklet |
| 成功事件后执行命令或 webhook | 排队执行 `hook::exec` 或 `hook::http` | `hooks` 配置 |
| 增加设备字段或端口字段 | JSONB 自定义字段、动态 ResultSet 列、公共 UI 注册 | `custom_fields` 配置 |
| 通过 SNMP 对象填充设备自定义字段 | 自动生成 discover hook 和内联自定义字段动作 | 自定义字段的 `snmp_object` |
| 增加资产或报表查询 | 内置报表插件或配置式通用报表 | ResultSet/Virtual Result 或 `reports` 配置 |
| 增加标签、导航项、详情行、端口列、报表或管理任务 | Web 插件注册表与公共外壳 | `App::NetdiscoX::Web::Plugin::*` |
| 增加设备操作或替代采集器 | Worker 注册表和 driver priority | `App::NetdiscoX::Worker::Plugin::*` 或 Python worklet |
| 定时执行任务或遍历所有符合条件的设备 | Scheduler 与 walk/元动作 | `schedule` 和 `Virtual::WalkJobs` |
| 对接外部资产消费者 | 带认证的对象、搜索和报表 API | `/api/v1`，保持 tenant 和角色契约 |
| 观察部署健康状态 | 健康检查与 Prometheus 端点 | 现有配置和有界指标 |

现有配置能够表达需求时优先用配置；出现新的行为或数据所有权时使用插件。只有内置功能和外部扩展共同依赖某项不变量时，才修改核心。

## 动作、队列与扇出模型

`admin` 行同时是排队命令和历史记录。持久化状态包括 `queued`、`done`、`info` 和 `error`。运行中的任务仍是 `status = queued`，`backend` 和 `started` 已设置才表示任务已被认领或正在运行。除非 schema 及所有消费者一起迁移，否则不得新增或查询虚构的 `running` 状态。

队列行为有意区分用户任务和后台任务：

- 用户提交的行带 `username`/`userip`，不会去重；
- action、目标或 device key、port 和 subaction 相同的后台任务可以折叠，包括与过期或运行中任务重复的情况；
- 管理进程认领任务时写入 backend 和开始时间，再放入本地优先队列；poller 进程执行一个任务后回收；
- `defer` 清除认领信息并重新排队；其他最终状态写入完成时间；
- 普通 defer 会增加每个 backend、每台设备的计数，并可能抑制该设备的所有动作；`deferrable_actions` 可让元任务或维护任务不计入该计数；
- 后端启动时会降低已到上限的计数，允许再试一次，并排队执行 `primeskiplist` 重建动作拒绝列表；
- `DeviceSkip` 中设备为 `255.255.255.255` 的行是 backend marker，`deferrals` 保存 Worker slot 数量，不代表真实设备。

`discoverall`、`macwalk`、`arpwalk` 和 `nbtwalk` 是扇出动作，不直接轮询每台设备。系统先初始化 skiplist，再由 `Virtual::WalkJobs` 根据动作拒绝、重试年龄和最小轮询年龄选择设备并插入叶任务。带 `only` 或 `no` 的定时配置同样会排队一个 `scheduler` 元任务，并在 skiplist 中使用 `scheduled-<label>` 伪动作。`pingsweep` 等目标前缀动作把前缀保留为单个目标，普通动作则把前缀展开为主机。

## 任务工作器与驱动扩展契约

`register_worker` 从包名推导 action 和可选 namespace。实际分派键由 action、phase、namespace 和数字 priority 组成。Loader 先按 namespace 排序，再在同一 namespace 内按 priority 从低到高执行；只有写同一 stash 位置的后执行 callback 才形成覆盖。`direct` 表示本地或无网络工作；SNMP、CLI、API、eAPI、NETCONF 和 RESTCONF 使用各自配置的优先级。

使用 `action::namespace` 执行聚焦的局部动作。check Worker 仍会运行，新设备所需的 early 身份 Worker 也可能运行。局部动作不保证关闭所有前置与清理阶段。

Python worklet 使用同一逻辑地址：`action.namespace.phase.driver.platform`。shim 把配置转换为 Worker 注册，为任务启动一个持久子进程，通过环境变量和临时上下文传递任务及配置元数据，把返回的 stash 合并到 Dancer `vars`，并将返回状态映射到 Perl 状态模型。stash 结构或状态行为发生变化时，要增加跨语言契约测试。

`macsuck` 和 `arpnip` 可以接收 direct/API/CLI 数据并把任务标为 offline。wrapper 随后按 main phase 与网络 driver 的 priority 区间跳过相应 Worker，但继续执行普通的 store、归档和 DNS 流程。可信的导入观测应复用这条链路，不能在 API 路由中直接写 `node` 或 `node_ip`。

## 钩子与事件自动化

discover、macsuck、arpnip 和 delete 在各自 hook callback 中检查 `best_status` 为 `done` 才排队。它忽略有 phase 的 check/user 状态，不等同最终 job 成功；详见 [netdisco-patterns.md](netdisco-patterns.md) §五。过滤条件复用标准 `only`/`no` ACL 语义。hook 数据先复制和序列化，再创建独立的 `hook::exec` 或 `hook::http` 任务，不在源事务中执行。

- Exec hook 支持标量命令或 argv 数组、Template Toolkit 展开、超时、`ND_EVENT` 和 `ND_DEVICE_IP`。
- HTTP hook 支持模板化 URL/body、method、header、bearer token 和毫秒级超时。
- `ignore_failure` 只改变 hook 任务的结果，不会让交付与发现或删除形成同一事务。
- delete hook 数据不包含 `snmp_comm`。hook 载荷不得加入凭据或未脱敏配置。

hook 只保证异步尝试，不保证严格一次交付。重复事件有影响时，外部接收方应实现幂等。

## 配置、ACL、凭据与标签

配置在启动时统一归一化：环境、数据库、tenant、旧别名、设备认证、schedule、report、自定义字段和插件都会转换为运行时形状。启动归一化保留在 `Configuration.pm`，job 参数转换在 `Util/Configuration.pm` 与 Job 构造边界；下游 Worker 消费约定形状。

动作可以通过 `port` 或 `subaction/extra` 使用 JSON、`key=value` 或 `{ "value": ..., "with": {...} }` 覆盖配置。不要在两个位置同时放覆盖项，该行为没有定义。`extra` 中的裸 hash 会被当作配置，因此 hash 业务载荷要包在 `value` 中。支持的凭据提示是 `device_auth_tag_hint`。

ACL 可作用于 IP、数据库行和 hash，支持 CIDR/IP、DNS 正则、`group:`、`tag:`、自定义字段、命名属性、取反及 `op:and`。两类防故障调用契约不能混淆：

- `acl_matches`/`check_acl_no` 表达“匹配则跳过”；输入或配置缺失会视为匹配，使拒绝守卫按 fail closed 处理；
- `acl_matches_only`/`check_acl_only` 表达“仅匹配才继续”；输入缺失会失败，配置为空列表则表示允许任意值。

凭据先按设备 `only`/`no` 过滤，再由每个 Worker 按 driver 和 action/namespace 过滤。读写模式相互独立。动态 tag 也是 ACL 结果：设备 tag 匹配设备，端口 tag 先匹配设备，再匹配端口数据。策略判断应复用 tag 和 ACL，不要在 Worker、API 和模板中重复厂商或 IP 判断。

## 自定义字段与配置式报表

设备和端口自定义字段存放在 JSONB 中，由 ResultSet modifier 投影为 `cf_<name>` 列，并注册到公共设备或端口 UI。单个 `cf_*` 队列插入属于特殊内联更新，会根据配置字段名校验，不创建普通 `admin` 任务。API 响应和审计预期必须保留这一区别。

带 `snmp_object` 的设备自定义字段会变为不可编辑的 JSON 列表数据，并自动生成 discover hook。该 hook 执行 `show`、归一化 JSON，再提交内联字段更新。它发生在 discovery 之后，不属于 discovery 数据库事务。

配置式通用报表支持：

- 带有序输出列和请求 bind 参数的 SQL 视图定义；
- 当前 tenant 或配置的外部 DBIC schema；
- 从一个定义注册 HTML、CSV 和生成式报表 API；
- IP、CIDR 和 MAC 值的可搜索渲染；
- 在受限 `Safe` compartment 中执行的可选站点本地 munger。

共享产品逻辑、复杂 join、分页或稳定 API 契约使用 Virtual Result/ResultSet。站点自有的只读展示使用配置式报表。请求值不得插值进报表 SQL，必须声明 bind 参数。

## 认证、API 与多租户

认证支持本地、LDAP、RADIUS、TACACS+、委托 remote-user，以及关闭认证或访客模式。API token 存储在用户行，记录签发时间，通常按 `api_token_lifetime` 过期；只有配置允许时才可永久有效，还可限制客户端 CIDR。token 登录接受 `Apikey` 或 `Bearer`，Basic 认证用于获取 token。

用户密码/provider 标志、token 生命周期和 `token_auth_only` 共同组成认证模式状态。服务账号创建流程必须按照对外契约完整初始化该状态；只签发 token 不会自动把用户行变成仅 token 账号。

角色按能力分配：

- `api` 用于只读对象、搜索、报表和统计；
- `api_admin` 用于队列、用户/token 或破坏性管理；
- `port_control` 只用于明确支持的端口和自定义字段操作，并在适用时叠加设备/端口 RBAC。

对象端点暴露设备、端口行及具名 DBIx 关系。导入 Node 或 ARP 观测时排队离线 `macsuck`/`arpnip`，不直接持久化。Swagger 元数据、路由、校验、tenant schema、角色、状态码和 JSON 结构属于同一个公共契约，必须一起修改。

tenant 路由会设置 `vars->{tenant}`，并改写生成链接、请求路径和 Swagger 路径。请求代码使用 `schema(vars->{tenant})`；后台代码使用 `schema('netdisco')` 时跟随配置的默认 tenant 别名。声称支持 tenant 前，必须测试非默认 tenant。

## 生命周期与运维能力

- `expire` 按独立的当前/归档窗口删除过期 Node/IP 历史，清除配置的孤立数据，在锁内过期任务和用户日志，对过期非伪设备排队删除，记录审计并刷新统计。
- `expirenodes` 默认归档，额外标志要求直接删除。
- 删除设备时可以把 Node 保留为非活动历史；delete hook 随后作为独立任务执行。
- renumber 在改变设备身份前更新别名、资产、端口、skiplist、远端链路、Node、拓扑、ACL 和 JSONB 中的 router-IP key，并删除指向旧 IP 的 Admin 记录。不得用只更新主键的实现替代。
- pseudo device 提供资产或拓扑占位及合成端口；是否存在离线快照会影响其允许动作。

可选健康检查和 Prometheus 路由绕过普通 session 认证，因此必须拥有独立控制。健康检查报告数据库可达性、backend 和 Worker marker 数量，但 HTTP 成功只取决于数据库可达。指标端点可要求源 IP ACL 和 bearer token，并输出每个 tenant 的统计、实时排队/运行/过期数量、资产分组、轮询过期、慢设备和 SNMP defer。扩展指标时保持 label 有界并正确转义，同时区分快照统计和实时表计数。

## 安全执行与诊断

`netdisco-do --dry-run` 会进入 Worker 点名模式：解析动作并列出适用 Worker，不执行 callback。它适合验证 plugin/phase/ACL/driver 选择。

`netdisco-do -R/--rollback` 会把默认数据库工作包在回滚事务中，但无法保证设备、HTTP hook、命令、其他 tenant、外部数据库或其他副作用不发生。不得把 rollback 当作在真实目标上测试写动作的授权。

`--enqueue` 会异步执行任务。前缀和文件可能展开为大量目标；未提供 `--force` 时，CLI 会拒绝超过 512 个解析后的主机。`--force` 只扩大目标范围，不代表动作安全。
