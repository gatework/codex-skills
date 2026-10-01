# 架构与业务主线

## 系统边界

Netdisco 是以 PostgreSQL 为数据底座的网络资产与运维系统。它通过 SNMP、CLI、API 和 Python worklet 采集设备、端口、邻居、转发表、ARP/ND、无线、实体、VLAN 与电源数据，对外提供搜索、报表、对象 API、拓扑、资产和运维控制能力，并通过数据库任务队列执行定时或交互式任务。

SNMP::Info 位于下一层，负责数据归一化。它把厂商 MIB 叶节点及设备差异转换成稳定的标量和表方法，例如 `name`、`model`、`interfaces`、`i_up`、`i_vlan`、`c_ip` 和 `c_port`。

## 运行时组件

| 组件 | 职责 |
|---|---|
| Web 进程 | Dancer 路由、认证、API、Template Toolkit 页面和插件组装 |
| 后端管理进程 | 轮询数据库队列、认领任务、管理本地优先队列与工作进程 |
| 工作进程 | 为单个任务建立 Runner，执行 Worker 阶段并写回最终状态 |
| 调度器 | 解析 cron 配置，创建元任务或设备叶任务 |
| PostgreSQL | 资产、历史、认证、队列、跳过状态、统计与 tenant schema |
| SNMP::Info | 设备识别、公共数据方法、索引归一化、缓存和写操作 |

## 任务工作器执行模型

Worker 按 `action`、`phase`、`namespace` 和 `priority` 注册。执行顺序如下：

1. `check`：判断目标和动作是否可执行。
2. `early`：建立公共时间戳、设备身份和共享上下文。
3. `main`：由 transport/driver 采集或执行主要动作。
4. `user`：用户扩展阶段；被 best_status 忽略，但可参与最终状态汇总。
5. `store`：校验并持久化共享 stash 中的数据。
6. `late`：执行收尾或后继动作；是否成功由具体 callback 检查。

阶段顺序以 `Worker/Runner.pm` 中的阶段数组为准；研究基线为 `check → early → main → user → store → late`，改动前用 [source-map.md](source-map.md) 的复核命令确认当前 ref。

namespace 支持 `action::child`。内部 Worker 会合并到高优先级内部 namespace。系统按设备 ACL、driver、action 和可选认证标签提示筛选凭据，并通过作用域守卫恢复临时状态。离线跳过由 wrapper 的 main phase 与 priority 区间判断，新增 driver 要验证其资格，不能把 offline 视为网络沙箱。

状态优先级为 `error > done > defer > info`。`best_status` 与 `finalise_status` 对阶段的过滤不同，check 放行也不是“没有错误”判断，详见 [netdisco-patterns.md](netdisco-patterns.md) §五。`defer` 用于当前无法连接或没有权限的情况，通常会把队列记录恢复为 `queued`；任务完成后会重置相关连接延迟计数。cancel 由 wrapper 阻止后续 callback；单个 error 本身不会自动取消。Runner 即使遇到异常也会生成最终状态，并执行动作级或全局超时控制。

持久化队列没有独立的 `running` 状态。任务被认领后仍保持 `queued`，通过 `backend` 和 `started` 判断是否正在运行。用户提交的任务有意保留重复记录，后台重复任务可以折叠。walk 动作和带 ACL 的定时任务属于元任务，它们通过 `Virtual::WalkJobs` 选择符合条件的设备，再创建叶任务。

Macsuck/Nodes 的共享 stash→store 是推荐采集结构，非全部插件的强制事实。WirelessNodes 在 main 中直接持久化；时间戳、事务范围和成功条件都要按具体动作核对。

## 主要业务流程

### 设备发现

- 校验目标格式与发现策略，并建立本轮共用时间戳。
- 通过 SNMP transport 建立连接，由 SNMP::Info 归一化设备基础属性。
- 解析 DNS、规范身份、别名/子网、设备类、引擎 ID、硬件身份、标签和受保护字段。
- 在事务中创建或更新设备；按配置拒绝重复或无效身份。
- 采集端口、VLAN、实体/模块、PoE、无线、端口属性和拓扑。
- 人工拓扑优先于自动发现的邻居数据。
- 通过 SNMP::Info 的 `c_*` 方法归一化 LLDP、CDP 等协议结果；拒绝不可用的本地/回环地址、歧义端口、重复邻居、排除的设备类型和不可信邻居数据。
- 对允许发现的未知邻居排队，同一 IP 或远端身份只排一次。
- 归档或删除过期记录，随后处理 hook。

### MAC 地址采集

通过 SNMP、CLI 或 direct/API driver 采集转发表中的 MAC 位置。系统校验 VLAN 和 MAC，把接口标识映射为稳定端口名，在事务中更新 `node` 观测记录并归档过期位置。同一 MAC 可以在不同交换机、端口或 VLAN 上保留合法历史记录。

### ARP/IP 邻居采集

采集路由器 ARP 和 IPv6 邻居信息，维护 MAC-IP-VRF 观测、JSONB 中各路由器的首次/末次证据、当前/历史状态及 DNS。即使后续搜索会关联这些数据，它仍与交换机端口上的 Node 活动状态相互独立。

### 端口与设备控制

Web 操作需要 `admin` 或 `port_control` 权限，并按配置校验设备级角色 ACL。路由先写入 `device_port_log`，再排队执行 `portcontrol`、`portname`、`vlan`、`power`、`location` 或 `contact` 等动作。写 transport 使用独立凭据，并通过读取后回写验证能力。页面接受请求不代表设备写入完成，最终结果以用户任务日志为准。

### 资产、拓扑和报表

设备、端口、实体、VLAN 和 PoE 表保存当前资产；Node 和 IP 表保存观测历史。`device_port.remote_*` 记录选定的自动发现或人工链路，`topology` 保存人工双向端口约束，Virtual Result 类实现报表视图。搜索和报表复用 ResultSet 方法，可输出 HTML、CSV 或 JSON/API。

### 自动化与运维

discover、macsuck、arpnip 和 delete 成功后，可以按过滤条件排队执行 Exec 或 HTTP hook。自定义字段把 JSONB 投影到设备/端口页面和查询中；基于 SNMP 的设备自定义字段由自动生成的 discover hook 异步填充。配置式通用报表使用绑定参数查询当前 tenant 或外部 DBIC schema，并同时提供 HTML、CSV 和 API 输出。可选的健康检查和 Prometheus 端点暴露数据库、后端、Worker、资产、队列、轮询时效与延迟信号。

## 跨模块不变量

- 设备主身份是规范化的 `device.ip`，别名保存在 `device_ip`。
- 多租户通过 `vars->{tenant}` 选择 DBIC schema；tenant 感知的请求代码不得未经确认就写死 `netdisco`。
- 读写认证提示相互独立，默认不得记录密钥。
- 离线快照应在无网络环境下复用同一套 SNMP::Info 方法契约。
- 人工拓扑必须优先于学习得到的拓扑。
- 队列和模型的协同更新要使用事务与显式锁。
- 设备发现、driver 选择和控制授权统一使用 ACL 工具，不在前端重复实现策略。
- 站点本地插件和外部插件是正式扩展边界。版本升级需要保持核心与插件兼容，或提供迁移诊断和回归覆盖。
