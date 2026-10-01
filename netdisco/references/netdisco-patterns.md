# Netdisco 可复用代码范式与逻辑实现

本参考资料面向 Netdisco 核心或站点扩展的实现、审查与重构。下列“实现”描述研究基线，“建议”表达由此提炼的方法；两者不等同。源码路径相对 `$ND`，提交与关键符号见 [source-map.md](source-map.md)。实施前仍需核对目标 ref 的邻近代码、测试和配置。

**目录**：一 职责层 · 二 边界归一化 · 三 Worker 注册 · 四 阶段与 stash · 五 状态/取消/延迟 · 六 数据保护策略 · 七 身份/拓扑/历史 · 八 传输层 · 九 DBIC 与锁 · 十 Web/API · 十一 回归测试 · 十二 审查清单 · 十三 变更方法

## 一、先确定职责层，再选择扩展点

| 变化内容 | 首选归属 | 不应放置的位置 |
|---|---|---|
| 原始配置兼容、默认值、旧形状迁移 | `Configuration.pm` / 配置工具 | 每个 Worker 重复解析 |
| 凭据筛选、连接、重试、设备类探测 | Transport / Util | 业务 store 或模板 |
| 一次采集的阶段编排、共享观测值 | Worker 插件与 `vars` stash | 路由直接写库存表 |
| 实体关系、小型领域动作 | DBIx::Class Result | 模板 JavaScript |
| 可复用查询、排序、归档/删除 | ResultSet / Virtual Result | 多个路由复制 SQL |
| 页面、报表、API 暴露 | Web 插件注册与薄路由 | 新建平行页面外壳 |
| 站点特有自动化 | `App::NetdiscoX::*`、hook、配置报表 | 无必要地修改核心 |

先问“现有配置、ACL/tag、自定义字段、通用报表、schedule、hook 或插件是否足够”。只有不变量属于所有内置和外部扩展时，才修改核心。

## 二、在配置边界归一化，在作用域出口恢复

启动配置经 `Configuration.pm` 归一化；每次 job 的参数还经 `Backend/Job.pm::BUILDARGS` 与 `Util/Configuration.pm::parse_params_to_config` 处理。可将这一设计理解为边界转换，但它会修改配置，不是纯函数编译器：

```text
文件/环境/旧字段形状
        -> 兼容迁移和默认值
        -> tenant、DB、device_auth、schedule、report、ACL 的规范形状
        -> Worker/路由只消费规范结果
```

可复用规则：

- 旧名字、scalar/hash/list 多形态和默认补全只在配置边界处理；不要让下游长期承担兼容分支。
- 数据库 schema 在配置阶段按 tenant/外部数据库建立，并让 `netdisco` 指向默认 tenant；请求代码仍要显式使用 `schema(vars->{tenant})`。
- `device_auth` 在启动时合并旧凭据配置和新形状。Worker 只做设备 ACL、driver、action/namespace 的二次筛选。
- 动作参数允许 JSON、`key=value` 或 `{value, with}`。`port` 和 `subaction/extra` 同时携带覆盖时语义未定义；裸 hash 会被解释为配置，hash 业务载荷应包在 `value` 中。
- 临时修改 Dancer 配置、凭据或 SNMP community 时，用 `Scope::Guard` 恢复。异常、取消和提前返回都不能污染同一进程处理的下一任务。
- 建议：兼容分支集中在已有边界，记录保留理由；只有明确废弃时才制定移除计划，不因整理代码删除仍被支持的输入。

**案例与验证。** `xt/50-config-override.t` 覆盖裸 hash 被消费、`{value: ...}` 保留业务载荷及 `with` 覆盖。`parse_params_to_config` 会 `delete` 传入 hash 的 `value`，因此不是无副作用解析器；若调用者需要复用输入，先明确复制边界。凭据隔离参考 `Worker/Runner.pm::run` 和 `Worker/Plugin.pm::register_worker` 的 `dclone` + `guard`。验证正常返回、异常及提前返回后配置均恢复；不要仅在 callback 尾部手工复原。

## 三、任务工作器注册是数据，Runner 负责执行

`register_worker` 是 `Worker/Plugin.pm` 通过 Dancer `register` 暴露的 DSL，不是同名 `sub` 声明。它把包名和参数编译成以下分派键：

```text
action -> phase -> namespace -> priority -> callback
```

- 默认 phase 是 `user`，默认 namespace 是 `_base_`。
- Loader 先加载站点插件再加载核心，但最后按 phase、namespace、priority 构造确定性执行序列。
- Loader 先按 namespace 字符串排序，再在同一 namespace 内按数字 priority 从低到高执行。只有在实际执行顺序允许、且 callback 写同一位置时，后面的采集器才覆盖前面的数据；并非跨 namespace 的全局 driver 排序。
- Loader 根据 main Worker 的 priority 判断 transport_required（0 或 direct 的配置优先级代表可无 transport）；wrapper 也按 priority 区间判断网络资格。常规 driver 配置之外，显式 priority 覆盖必须一起测试。
- `action::namespace` 是局部执行地址，不等于绕过全部前置条件；check 仍运行，新设备还可能运行必要的 early 身份阶段。
- Worker wrapper 统一处理取消、离线网络 Worker 跳过、partial namespace、ACL、driver/action 凭据筛选和局部状态恢复。不要在每个插件复制这些守卫。

Runner 的 `run` 明确拒绝复用。每个 job 新建 Runner；transport 还有自己的缓存生命周期，不能据此假定全进程状态都已清空。

## 四、用阶段和共享暂存区表达采集主线

对需要多 driver 合并或离线导入的采集，优先采用“先观测、后存储”。`Macsuck/Nodes.pm` 是代表实现；阶段本身只约束执行顺序，不强制每阶段的数据职责：

```text
check     确认可运行性
early     初始化本轮时间戳、基础对象与共享 stash（以动作实现为准）
main      多个 driver 采集并合并/覆盖 stash
user      用户扩展阶段（best_status 忽略，最终状态可受其影响）
store     校验业务语义，事务性持久化，处理当前/历史状态
late      收尾或后继动作；成功条件由具体 callback 判断
```

用于新采集能力的设计建议：

- 对同一批观测的存储和归档传递同一时间戳，避免 freshness 偏差；不要宣称一个 job 的所有插件天然共用时间戳。
- 采集 callback 将观测写入约定 stash，返回值用于 Status，而非直接返回观测表。共享 store 使 SNMP、CLI、API、Python 与离线导入复用业务校验。
- stash key 是跨 Worker 接口，改变其形状等同于公共 API 变更；需要覆盖多 driver 合并和跨语言 worklet 的契约测试。
- store 在写库前再次验证 MAC、IP、VLAN、端口、DNS/身份等业务条件。transport 成功不等于数据可信。
- hook callback 显式检查 `best_status`；Runner 不会因为进入 late 就保证主目标成功。hook 成功判断与最终状态汇总并非同一个函数。

**现有例外。** `Macsuck/WirelessNodes.pm` 在 main 中直接 `txn_do` 写 NodeWireless，并创建自己的时间戳。不能据此把所有采集都做成 main 写库，也不能以推荐流水线为由顺手搬迁该实现。改造时先覆盖持久化、时间戳和状态契约。

`macsuck` 和 `arpnip` 的直接/API/CLI 输入会把任务标记为 offline，跳过联网 main Worker，但仍经过相同 store、DNS、活动/历史和时间戳逻辑。这是导入观测数据的首选范式。

## 五、精确定义状态、取消与延迟

Worker 状态不是普通日志级别：

| 状态 | 含义 | 典型用途 |
|---|---|---|
| `done` | 本 Worker 完成了有意义的目标 | 成功采集或持久化 |
| `info` | 有意跳过或仅说明情况 | 不适用、无变化 |
| `defer` | 当前不能执行，但以后重试可能成功 | 无凭据、暂时连接失败 |
| `error` | 本轮失败，需要人工或代码关注 | 不可恢复异常、数据契约破坏 |

汇总强度由 `Worker/Status.pm::level` 定义为 `error > done > defer > info`，但三个消费者各有规则：

| 消费者 | 实现契约 | 必测反例 |
|---|---|---|
| `Backend/Job.pm::check_passed` | 状态列表为空也通过；非空时至少一个 check/done 才通过 | 无 check 状态与 check/info 不等价；check/error 并非单独的停止开关 |
| `best_status` | 有 phase 时仅计 early/main/store/late；无 phase 状态也可参与 | user/error 不改变它的结果 |
| `finalise_status` | 接受六阶段及无 phase 状态，只剔除 check/done；最高等级胜出 | user/error 或 check/error 能使最终结果失败 |

同等级最终日志：done 取最新，其余取最早；没有可用结果时默认 error。用这些可观察差异验证状态变更，不凭最后一条日志猜结果。

- `cancel` 用于保护整条流水线，后续 wrapper 会停止执行。取消原因要落成清晰状态，不能只写调试日志。
- 只有未来重试有意义的失败才 `defer`。普通 defer 会增加设备/后端计数，并可能抑制其他设备动作。
- Worker 可无状态返回以静默旁路，但关键业务分支应产生可诊断状态。
- Runner 将 callback 异常转成 error 并由 guard 收尾；error 本身不等于 cancel，也不回滚之前提交的事务。保护整条流水线时显式返回 `$job->cancel(...)`，由 wrapper 跳过后续 callback。不要吞掉 transport 的真实错误。

**案例。** `Macsuck/Hooks.pm` 用 `best_status` 决定是否排 hook；若 main/done 后出现 user/error，hook 判断仍可能通过，但最终 job 为 error。这是当前两套汇总规则的区别，不能概括成“最终成功才有 hook”。

## 六、对不同数据使用不同保护策略

发现任务故意区分设备身份和大表采集失败：

- `device` 的关键字段如果新值明显损坏或缺失，可能取消 discovery，避免覆盖规范身份。
- `device_port` 在别名和 ignore ACL 处理后检测 name/up/up_admin 等灾难性退化。发生异常时保留该端口旧值、发出警告并继续，使其他可信表仍能更新。
- 端口表替换在显式锁下完成，同时保留用户自定义字段、节点历史等不属于本次采集所有权的数据。

由此得到通用准则：

1. 先声明本阶段“拥有”哪些字段。
2. 参考 `Discover/Properties.pm` 的配置式保护：关键身份失败可 cancel，端口字段整体退化可保留旧值。它不是任意部分缺失都能自动保全的通用机制；新表要单独定义完整性和替换条件。
3. 保护判断必须在规范化、ignore 过滤之后，否则会把合法过滤误判为数据丢失。
4. 不要假设取消会回滚此前已经提交的独立阶段事务。
5. 把异常降级写入用户可见状态/日志，并用退化快照覆盖回归测试。

## 七、身份、拓扑和历史是聚合，不是单行

- `get_device` 先解析管理地址，再解析别名；未知目标返回未持久化的 DBIx::Class 行。调用方可用统一接口处理新旧设备，但写库前必须检查是否已存储。
- 自动 canonical-IP 选择与显式 renumber 动作的前置条件不同；先读各自调用者，不把自动发现的 SNMP 探测条件套给所有改址入口。
- `Device->renumber` 是跨库存表、skiplist、远端链路、Node、Topology、队列清理和 JSONB router key 的聚合迁移，不能替换成主键更新。
- 人工拓扑先应用并受保护，自动 LLDP/CDP 等数据只能补充，不能覆盖管理员声明。
- 邻居身份回退需同时读 `Discover/Neighbors.pm` 与调用的 Util 方法，核对地址、名称、MAC 和 remote id 的优先级与歧义处理。这些路径有本地修改，见研究基线；新增规则不应从模糊匹配直接创建可信身份。
- 未知邻居入队要同时按 IP 和 remote id 控制重复；有稳定设备键时使用 `device_key` 参与队列去重。
- Node/ARP 采用“当前活动位置 + 历史记录”模型。移动时先使旧位置失活，再 upsert 新位置；不要删除审计历史。
- ARP 身份是 MAC、IP、VRF 组合。同一 IP 的旧活动行先失活；`seen_on_router_first` 每个路由只写首次时间，`seen_on_router_last` 每次更新。

## 八、传输层通过能力探测判断成功

SNMP reader/writer 对规范管理 IP 分别缓存，只缓存通过探测的句柄：

1. 优先尝试最近成功的凭据 tag。
2. 快速尝试 v3/v2 等候选。
3. 如允许，再使用保守超时和更多版本/设备类慢速探测。
4. 先尝试已知 class，再从基础类探测并重新分类、重建正常连接。

读取成功不是“session 能创建”，而是无错误并能获得 uptime 变体、layers/description 和设备 class。写连接还执行 location 的读、同值 set、reload、比较。实现新的 transport 时保持这种“验证所需能力再缓存”的语义。

- reader 与 writer 凭据、缓存和权限不能混用。
- pseudo/offline Snapshot 构造 SNMP::Info raw cache，继续走相同公共方法契约，不建立第二套库存逻辑。
- 捕获层应规范不同异常形状，但保留 timeout/crash 的真实原因。
- 即使使用调试日志，也应脱敏 community、口令和 token；不要复制源码中的潜在泄密路径作为调试范式。

## 九、DBIx::Class、锁和查询组合

模型层的通用规则（Result/ResultSet 分工、bind 顺序、确定性排序、schema 版本与运行时能力校验、聚合删除/改址）集中在 [database.md](database.md) 的“数据变更规则”，此处只保留与 Worker 流程相关的两条：

- 需要串行化集合替换时参考 `DB/ExplicitLocking.pm::txn_do_locked`；锁与事务只覆盖传入 callback，不能跨多个已提交阶段自动生效。按竞争关系选锁，不能把默认 ACCESS EXCLUSIVE 当成所有写入的要求。
- Virtual Result 表达带 bind 参数的 PostgreSQL 视图查询（如调度资格）；路由里不拼接请求 SQL。

## 十、Web/API 以注册元数据和输出形状为契约

- `Web.pm` 是组合根，集中处理 tenant 路径、API JSON 错误、cookie 策略、模板 helper 和脚本上下文转义。
- Web 插件注册 tab、report、admin task、detail row、port column、CSS/JS 和模板路径；公共 shell 负责排序和组装。不要让插件复制 navbar、sidebar 或 tab 外壳。
- search tab/report 注册可从同一元数据生成 Swagger 和 API forwarding route。route、Swagger、参数验证、模板/CSV/API 输出必须共同修改。
- tenant 路由先设置 `vars->{tenant}` 再 forward 到同一底层实现；请求内所有 schema 与 URI 生成都要保留 tenant。
- 模板上下文中某些契约由 key 是否存在决定，不只由值决定。共享报告里的 `results` 就是这种 shape signal；通用 hook 不得无意注入。
- CSV 输出临时关闭 AutoFilter 后必须恢复；脚本、HTML、URI 和 CSV 使用各自最终上下文的转义。
- Result 的 `TO_JSON` 只允许声明可序列化列，防止关系名覆盖字段或泄露对象内部。
- API 写操作应入队并通过 job/user log 表达异步结果；导入 Node/ARP 也走 offline Worker，而不是 route-owned persistence。

认证顺序同样是业务契约：API 请求销毁 cookie session，显式 token 可以覆盖 delegated user，Basic 用于签发 token，logout 同时使 token/session 失效。health/metrics 绕过普通 session，因此必须拥有独立 ACL/token 控制。

## 十一、回归测试优先覆盖框架边界

高价值测试不是只调用单个 helper，而是固定最容易漂移的组合边界：

- 用本地测试 Worker 驱动真实 Loader/Runner，覆盖 phase、priority、覆盖/累加、device_auth、driverless 和 cancel。
- 采集测试覆盖正常、空表、部分缺失、灾难性退化和保留旧值，而不只覆盖成功快照。
- 数据库测试覆盖聚合 renumber/delete、锁内替换、活动/历史转换、确定性排序和关键 PostgreSQL 函数存在性。
- Web 测试同时验证路由、角色、tenant、HTTP 状态、content type、JSON shape、转义和模板渲染。
- 优先断言可观察行为；只有必须限制危险机制且运行测试难以稳定表达时，再加聚焦源码守卫。hash 顺序无业务含义时先规范化测试输入/比较，不因顺序波动普遍增加文本匹配测试。
- 模板快照要枚举所有模板。源码 checkout 中缺单个快照必须失败；打包分发中整体无快照目录可以跳过。
- Node 测试显式列出文件；不要使用可能零匹配仍返回成功的 glob。
- 发布上传步骤即使 `continue-on-error` 也不构成成功证据，必须从 CPAN、GitHub Release 和镜像 registry 分别验证产物。

## 十二、实现与审查清单

提交前逐项回答：

1. 变化属于配置、transport、Worker、模型、Web 还是站点插件？是否跨错层？
2. 输入在边界是否已规范化？是否存在第二套旧形状解析？
3. 本轮采集时间戳和 stash shape 是否一致？多个 driver 谁覆盖谁？
4. 成功、info、defer、error、cancel、timeout 和 offline 各自会发生什么？
5. 新数据不可信时，是停止身份更新，还是保留该表旧值并继续？
6. 写入是否涉及聚合迁移、历史归档、显式锁、tenant 或外部 schema？
7. 队列去重是否区分用户任务与后台任务？运行中状态是否仍按 `queued + backend + started` 判断？
8. API/模板是否保持角色、tenant、content type、key presence 和最终上下文转义？
9. 测试是否覆盖框架组合边界、失败路径及运行时数据库能力，而非只覆盖编译？
10. 是否遵循 [SKILL.md](../SKILL.md) 操作边界（MIB 正文、凭据泄露、真实设备写入、把 rollback/dry-run 当成安全保证）？


## 十三、把方法落实为一次可审查的变更

无需为每次小改动新建文档；在任务记录或 PR 中说清以下五件事即可：

| 决策 | 要回答的问题 | 源码示例 |
|---|---|---|
| 接口 | 输入来自谁，输出类型、键空间与消费者是谁？ | `Macsuck/Nodes.pm` 的 `fwtable` 为 VLAN→端口名→MAC 集合 |
| 所有权 | 谁生产、覆盖、保存、归档，谁拥有人工字段？ | `Discover/Properties.pm` 锁内替换端口并保留 custom_fields |
| 失败语义 | 缺数、失败、拒绝、取消分别留下什么状态与旧数据？ | Job 的三种状态消费者与字段保护分支 |
| 生命周期 | 临时配置、句柄、子进程何时恢复或释放？ | Runner 的凭据 guard 和 Python 清理 |
| 验证 | 哪个最小测试能观察这次决策，而不是重复实现？ | `xt/30-backend-workers.t` 用 fake 插件跑真实 Loader/Runner |

**多驱动案例。** 为现有 MAC 采集增加 API driver 时，先对齐 `fwtable` 的 VLAN、端口和 MAC 形状，再选择能与既有 producer 正确排序的 namespace/priority；复用 store，而不是从 API driver 直接写 Node。至少观察：API 缺少一张表时如何保留或拒绝数据、同键如何覆盖、offline 输入是否仍走 store、error 后是否继续、两个 driver 是否使用同一观测时间。已有排序机制不等于已有安全的合并策略。

**行为保持重构。** 将重复逻辑抽成 helper 前，确认 Perl 调用上下文、hashref 是否共享、是否修改传入参数、返回的是 Status 还是业务值、是否依赖 Dancer vars，以及异常是否穿过 guard。纯转换适合窄 helper；调度、授权与资源生命周期继续由已有框架边界拥有。
