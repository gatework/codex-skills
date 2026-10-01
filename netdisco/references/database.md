# Netdisco 数据库与模型能力

**目录**：数据库结构机制 · 核心身份与资产表 · 端口表 · 节点与地址历史 · 拓扑/运维/认证/元数据 · 数据变更规则

> 下方表与字段清单是研究快照，用于快速建立心智模型，**不是**字段权威。改动前必须回读对应 `Result/*.pm`，不要凭本清单推断列名、可空性或关系。

## 数据库结构机制

`App::Netdisco::DB` 是 DBIx::Class schema，包含生成式 Result 类、自定义 ResultSet、显式锁和按版本升级的 PostgreSQL schema。升级脚本按顺序存放在 `share/schema_versions/App-Netdisco-DB-X-Y-PostgreSQL.sql`，当前 schema 整数以 `DB.pm` 为准（研究值集中在 [source-map.md](source-map.md)）。每次都要在目标 ref 重新读取 `DB.pm`、最新迁移和相关 Result 类。

数据库变更需要同步维护：

- 升级 SQL 和 schema 版本；
- Result 列类型、可空性、默认值、主键/唯一键和关系；
- ResultSet 查询、Virtual Result SQL、删除/归档行为、API 字段、模板、测试及部署/回滚预期。

有意识地使用 PostgreSQL 原生类型。`inet`、`macaddr`、数组、JSONB、时间戳、range/bit 转换及 SQL 视图/函数都属于业务模型。

## 核心身份与资产表

### `device`

主键：`ip`。

字段：`creation`、`dns`、`description`、`uptime`、`contact`、`name`、`location`、`layers`、`num_ports`、`mac`、`serial`、`chassis_id`、`model`、`ps1_type`、`ps2_type`、`ps1_status`、`ps2_status`、`fan`、`slots`、`vendor`、`os`、`os_ver`、`log`、`snmp_ver`、`snmp_comm`、`snmp_class`、`snmp_engineid`、`vtp_domain`、`vtp_mode`、`last_discover`、`last_macsuck`、`last_arpnip`、`is_pseudo`、`pae_is_enabled`、`custom_fields`（JSONB）、`tags`（文本数组）。

能力：别名及端口、模块、电源、VLAN、浏览器关系；按身份、IP、名称、字段、模糊条件、VLAN 和网络层搜索；平台/版本聚合；派生年龄、时间戳和计数；跨依赖表规范化改址；协同删除和归档。

### `device_ip`

主键：`(ip, alias)`。字段：`subnet`、`port`、`dns`、`creation`。`ip` 指向规范设备，`alias` 是接口地址。

### `device_module`

主键：`(ip, index)`。字段：`description`、`type`、`parent`、`name`、`class`、`pos`、`hw_ver`、`fw_ver`、`sw_ver`、`serial`、`model`、`fru`、`creation`、`last_discover`。

### `device_vlan`

主键：`(ip, vlan)`。字段：`description`、`creation`、`last_discover`。

### `device_power`

主键：`(ip, module)`。字段：`power`、`status`；ResultSet 派生聚合 PoE 统计。

## 端口表

### `device_port`

主键：`(port, ip)`。当前代码调用 `find` 时必须保持这个参数顺序。

字段：`creation`、`descr`、`up`、`up_admin`、`type`、`duplex`、`duplex_admin`、`speed`、`speed_admin`、`name`、`mac`、`mtu`、`stp`、`remote_ip`、`remote_port`、`remote_type`、`remote_id`、`has_subinterfaces`、`is_master`、`slave_of`、`manual_topo`、`is_uplink`、`vlan`、`pvid`、`lastchange`、`custom_fields`、`tags`。

能力：设备、native VLAN、聚合口、邻居和最近 Node 关系；Node 与 VLAN 集合；PoE、SSID、无线和属性扩展；网络端口自然排序；空闲端口判断；派生最后变化时间和远端资产；级联删除和归档规则。

### 端口扩展表

- `device_port_properties`，主键 `(port, ip)`：错误禁用原因、可发现/WAP/电话标志、远端厂商/型号/OS/序列号/DNS、原始速率、faststart、ifindex，以及 802.1X 配置、会话、MAB、EAPOL、认证器和客户端字段。
- `device_port_power`，主键 `(port, ip)`：`module`、`admin`、`status`、`class`、`power`。
- `device_port_vlan`，主键 `(ip, port, vlan, native)`：`egress_tag`、`creation`、`last_discover`、`vlantype`。
- `device_port_ssid`，主键 `(ip, bssid, port)`：`ssid`、`broadcast`。
- `device_port_wireless`，主键 `(port, ip)`：`channel`、`power`。
- `device_port_log`，主键 `id`：`ip`、`port`、`reason`、`log`、`username`、`userip`、`action`、`creation`。

## 节点与地址历史

### `node`

主键：`(mac, switch, port, vlan)`。字段：`active`、`oui`、`time_first`、`time_recent`、`time_last`。

该表记录交换机端口上的 MAC 观测并保留历史位置。关系连接设备/端口、IP、NetBIOS、无线数据和厂商。ResultSet 删除操作可以归档活动状态、保留 Node、只删除 Node，或协调清理相关数据。

### `node_ip`

主键：`(mac, ip, vrf)`。字段：`dns`、`active`、`time_first`、`time_last`、`seen_on_router_first`（JSONB）、`seen_on_router_last`（JSONB）。该表独立记录 MAC-IP-VRF 观测，并可推导最近路由器，不依赖端口观测。

### 节点辅助表

- `node_nbt`，主键 `mac`：`ip`、`nbname`、`domain`、`server`、`nbuser`、`active` 和首次/末次时间。
- `node_wireless`，主键 `(mac, ssid)`：uptime、速率、信号、报文/字节指标和 `time_last`。
- `node_monitor`，主键 `mac`：`matchoui`、`active`、`why`、`cc`、`date`。

## 拓扑、运维、认证与元数据

- `topology`：人工 `(dev1, port1) <-> (dev2, port2)` 链路，每组端点唯一；人工拓扑优先于自动发现。
- `access_control_list`，主键 `id`：可复用的 `rules` 文本数组。`access_control_list_name` 以 `acl_name` 为主键并指定 `acl_type`。`access_control_list_map` 以 `id` 为主键，把名称映射到可选左右 ACL 行。保留命名列表和方向映射模型，不要把 ACL 规则摊平到 Worker 或路由。
- `admin`，主键 `job`：entered/started/finished、device/port/action/subaction、status、用户身份、log/debug、device key、backend。该表同时承担队列和历史记录。
- `device_skip`，主键 `(backend, device)`：动作集合、延迟次数和最后延迟时间；用于协调每个处理后端和设备的重复连接失败。
- `community`，主键 `ip`：写 community，以及相互独立的读写认证标签提示。
- `users`，主键 `username`：密码/token 生命周期、签发时间、最后使用时间、端口控制/RBAC、LDAP/RADIUS/TACACS/admin 标志、身份/备注、永久 token、允许 IP 和仅 token 认证设置。
- `sessions`，主键 `id`：创建时间和序列化 session 数据，包括 cookie key 行。
- `user_log`：username、IP、event 和 details 审计记录。
- `statistics`，主键 `day`：设备、链路、端口、Node、IP、电话、WAP 数量，以及 Netdisco、SNMP::Info、schema、Perl、Python 和 PostgreSQL 版本。
- `netmap_positions`，主键 `id`：设备和过滤维度及已保存位置。
- `device_browser`、`snmp_object`、`snmp_filter`、`product`：浏览数据和归一化 SNMP 对象元数据。
- `manufacturer`、`oui`、`enterprise`：MAC 厂商和 enterprise 查询数据。
- `subnets`，主键 `net`；`process` 和 `log` 支撑调度和运行日志。

Virtual Result 类实现当前/最近 Node、设备链路、VLAN/双工不匹配、利用率、慢速/孤立/未发现设备和可执行任务等报表或搜索视图。它们的 SQL 和 bind 顺序属于公共模型行为。

## 数据变更规则

本节集中记录模型层方法；实际契约以目标源码和调用者事务为准。

**分工**

- Result 保持生成式列、关系和小型实体行为；ResultSet 持有可复用筛选、派生列、排序、协调归档/删除和 Virtual 查询组合。
- 区分活动状态与历史语义，不用原始删除替代归档。删除端口/设备不是普通 DBIC delete：扩展表、Node 当前/历史、拓扑和审计要由领域删除方法协调。

**聚合与身份**

- 规范 IP 变化是单个领域操作。`Device->renumber` 在改变设备身份前更新别名、资产子表、skip 行、远端链路、Node 历史、拓扑、ACL 和 JSONB router key，并删除旧 IP 的 Admin 记录；只更新主键会破坏整个聚合。
- 保持复合主键参数顺序（如 `device_port` 是 `(port, ip)`）和 DBIx::Class 关系方向。
- 多表身份、队列和归档转换使用 `txn_do` 及显式行锁或表锁。

**查询正确性**

- SQL 值使用引用与 bind；PostgreSQL 表达式和 Virtual 视图使用 DBIC identifier 与显式 bind 数组。相关表达式依赖 bind 顺序，要测试实际生成或执行的查询，不能只审查 SQL 片段。
- 分页或 DBIC prefetch 折叠前建立确定性排序，并一次构造完整 `order_by`；后续链式 `order_by` 会**替换**已有排序，不会追加。

**运行时能力**

- schema 版本只是必要证据，不能证明数据库对象完整存在。PostgreSQL 函数属于运行时依赖时，应像端口排序代码检查 `port_sortkey()` 一样断言其存在；缺失时给出可执行的升级提示，不得静默改变语义。


## 源码案例：领域操作与事务边界分开核对

**改址。** `DB/Result/Device.pm::renumber` 表达跨表身份迁移，内部没有自行包住整个流程的 `txn_do`；`Util/Device.pm::renumber_device` 在调用端提供事务。新入口既要复用领域操作，也要确认使用对象所属 schema 及事务，不因方法名像一个原子动作就假定它天然原子。当前 Admin 记录是删除而非改址重排，Community 也有独立维护路径；应逐一核对，不能只做全库字符串替换。

**集合替换。** `Worker/Plugin/Discover/Properties.pm` 对端口执行字段保护，在 `DevicePort->txn_do_locked` 中保留 custom_fields、通过领域 delete 保留 Node，再 populate。可复用方法是先界定采集与人工字段的所有权，再选择事务内替换。锁只保护 callback；先前阶段已提交的数据和锁前读取是否过期，需要另外审查。

**验证。** 改址测试使用旧/新身份、冲突目标、两端拓扑和 JSONB router key，观察历史及旧任务处理；在迁移中途注入失败验证调用端回滚。集合替换测试覆盖人工字段、缺失采集字段、历史 Node 和并发写入。必须用 PostgreSQL 验证锁与 SQL 行为，纯 mock 不能证明竞争安全；这些是新增变更的验收要求，不代表当前测试已覆盖。
