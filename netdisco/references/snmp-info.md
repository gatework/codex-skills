# SNMP::Info 业务实现与扩展模型

**目录**：业务定位 · 运行逻辑主线 · 四个声明式能力哈希 · 动态方法契约 · 读取/缓存/离线 · 跨索引空间归一化 · 层与协议组合 · 厂商扩展决策顺序 · 写操作与设备安全 · 防御式 Perl 规范 · 测试契约 · 常见错误 · 源码方法案例

源码路径相对 `$SI`；提交与定位入口见 [source-map.md](source-map.md)。以下区分当前实现、推荐扩展方式与需要回归保护的历史行为。

## 业务定位

SNMP::Info 不是 MIB 浏览器，也不只是 OID 到方法名的映射。它在 Net-SNMP 之上提供稳定、跨厂商的设备能力接口，把设备识别、协议表读取、索引空间转换、值归一化、缓存、写入和错误处理封装为可组合的 Perl 类。Netdisco 应消费 `interfaces`、`fw_mac`、`c_if`、`ip_index` 等公共方法，而不是直接依赖某厂商叶节点。

分析范围以 Perl 代码为界（模块名、叶节点标识符及其映射可查，MIB 正文见 [SKILL.md](../SKILL.md) 操作边界）。

## 运行逻辑主线

一次典型调用遵循：

`new -> init -> SNMP::Session -> device_type/specify -> can/AUTOLOAD -> get/walk -> raw cache -> munge -> 公共返回值`

写入走 setter 解析→缓存标记失效→session set→返回值/error，不经过读取的 munge 流水线。

1. `new` 接受 hashref 或键值参数，把 `Debug`、`AutoSpecify`、`BulkWalk`、`Offline`、`Cache`、`Session` 等框架参数与 `SNMP::Session` 参数分离。
2. 对象保存具体类的 `%MIBS/%GLOBALS/%FUNCS/%MUNGE` 引用；`init` 加载每个声明模块，并以代表性叶节点验证可用性。
3. 构造器创建会话或接收注入会话。即使会话创建失败也可能返回对象，因此调用方必须检查 `error`，不能只检查对象真值。
4. `AutoSpecify` 通过 `device_type` 识别具体类，再复用当前会话重建子类对象，避免第二次连接。
5. 方法调用优先命中真实 Perl 子程序；否则 `can/AUTOLOAD` 根据声明式哈希生成本次调用的读表、读标量或 setter closure。
6. 原始值先进入缓存，返回时再经 `%MUNGE` 归一化；这样 `_raw` 和离线快照仍能保留原始数据。

`update` 用原始参数叠加新的 community/context 等会话参数创建新 session，清空缓存，但不重新识别设备类。IPv6 目标由 `resolve_desthost` 转换为 Net-SNMP 所需形式。

## 四个声明式能力哈希

每个类显式组合以下包变量：

- `%MIBS`：模块名到代表性叶节点，用于加载验证。
- `%GLOBALS`：稳定的标量方法名到叶节点。
- `%FUNCS`：稳定的表方法名到叶节点；通常返回以 SNMP instance ID 为键的 hashref。
- `%MUNGE`：公共方法名到归一化 callback。

叶节点冲突时沿用项目的限定名编码；动态解析会把 `__` 恢复为 `::`、把下划线恢复为连字符。

关键组合规则：

- Perl `@ISA` 只决定真实方法查找，不会自动合并四个哈希；增加 mixin 时必须同时显式合并所需哈希。
- 哈希展开顺序决定同名声明最终由谁覆盖，`@ISA` 顺序决定真实子程序的 MRO。两者必须共同得到预期的胜出定义，不能靠偶然顺序工作。
- 真实 Perl 子程序优先于动态 `%GLOBALS/%FUNCS`，适合实现多表拼接、回退、索引转换或设备缺陷规避。
- 不要把动态 closure 安装进全局符号表；不同设备类可能把同一个公共方法映射到不同叶节点，永久缓存会造成跨类污染。

遇到覆盖来源不清时，使用 `SNMP::Info::MRO` 的 `all_methods`、`globals`、`funcs`、`munge`、`superclasses` 或 `print_*` 能力检查实际胜出定义。先查 MRO，再调整继承或哈希顺序。

## 动态方法契约

`_validate_autoload_method` 识别并剥离这些变体：

- 普通方法：优先使用缓存。
- `load_METHOD`：强制重新获取。
- `METHOD_raw`：绕过 `%MUNGE`，返回缓存中的原始值。
- `orig_METHOD`：绕过同名真实方法，使用当前对象的声明映射生成动态方法；不是重新选择父类哈希。`SUPER::METHOD` 优先沿真实继承查找，落入 AUTOLOAD 时改写成 `orig_METHOD`。
- `set_METHOD`：解析对象并检查可用的访问元数据。数值 OID 没有 access 元数据时可以跳过权限检查，因此 `can(set_...)` 不证明设备允许写入。

`can` 必须先尊重真实 Perl 方法，再验证动态方法。新增公共 API 时应明确它是单叶声明，还是必须以真实子程序维护跨表业务不变量。

## 读取、缓存与离线语义

标量原始值保存在对象的下划线键中；表原始值保存在 `store`，并由下划线标记记录非 partial 调用已缓存；该标记本身不是无错误、完整采集的证明。

- 普通标量/表调用首次获取后复用缓存；`load_*` 刷新。
- 读取失败也会把标量标记为已尝试，避免同一对象不断重复失败请求。
- 表在 SNMP v2/v3 且允许时优先 BULKWALK，否则 GETNEXT；必须防止越出子树、重复 IID 循环、`ENDOFMIBVIEW` 和各种 no-such 响应。
- partial 参数表示获取某个 instance 前缀。partial 读取不得升级为“完整表已缓存”，否则后续调用会得到不完整业务数据。
- `%MUNGE` 在返回阶段执行。当前 `_munge` 的表分支跳过值为 `undef` 的键；标量分支在有 munger 时用真假值提前返回，`0`/空串也可能返回 `undef`。这是需保留或显式修复的行为差异，不应描述成统一的缺失契约。
- `cache()` 可导入/导出原始快照；动态读取在 `Offline` 下缺缓存时设置错误，不执行读取请求。partial 和 `load_*` 不走普通完整缓存命中；测试这两者与 Offline 的组合，不把 Offline 当作任意设备方法或 setter 的沙箱。
- `clear_cache` 同时清理标量下划线键和 `store`；切换会话上下文后必须清缓存。

快照测试需要覆盖“原始缓存 + 返回时 munge”，不能只比较最终展示值。

## 跨索引空间归一化

SNMP 业务表通常不共享键空间。模块化设计的核心工作之一，是把这些索引转成 Netdisco 能稳定消费的 `ifIndex`、IP、MAC、VLAN 或实体键：

- Bridge/Q-BRIDGE：FDB instance、dot1dBasePort、`ifIndex`、VLAN/FDB ID 互相转换。
- LLDP/CDP：协议本地端口号和复合远端键转为本地 `ifIndex`，再归一化 chassis ID、远端端口、管理地址和 capability。
- LAG：`ifStackTable` 或 IEEE 802.3ad port list 转为 `member ifIndex -> aggregate ifIndex`。
- Layer3：旧 `ipAddrTable` 与新 IP-MIB 复合索引统一成 IPv4 地址键；ARP/邻居表统一到接口和地址语义。
- Entity：从物理实体层级中选择 chassis/module 的型号、序列号、软件版本，而不是假设固定 IID 永远存在。

实现转换时先画出源键和目标键，验证中间映射是否存在，并跳过未定义值。不要把 bridge port、LLDP port number、VLAN FDB ID 或实体 IID 当作 `ifIndex`。

## 层、协议与公共能力组合

- `SNMP::Info`：系统、接口、IPv4 基础以及设备分类。
- `Layer1`：中继器/物理端口能力。
- `Layer2`：组合 Bridge、Entity、PoE、LLDP、DOCSIS HE、802.1X 等，并规范接口名称重复问题。
- `Layer3`：在二层能力上增加 IPv6、ARP、路由、OSPF、IS-IS、BGP、子接口和聚合关系；设备同时支持 L2/L3 时分类优先检查 Layer3。
- `Layer7`：对应用/安全/负载类设备提供最小通用身份和接口能力。

协议 mixin 提供独立原料，公共方法负责跨协议统一：

- `has_topo` 按 LLDP、CDP、SONMP、FDP、EDP、AMAP 检测当前能力。
- `c_if/c_ip/c_port/c_id/c_platform/c_cap` 合并所选协议数据，但不负责邻居去重；若需要来源或处理重复，调用协议专属方法。
- LLDP 本地端口优先用 port description 对齐 `ifDescr`，再尝试 `ifAlias`，最后保留原始端口键，让厂商类仍有覆盖空间。
- IPv6 会按可用数据在 IP-MIB、IPV6-MIB、Cisco IETF 表之间有序回退；回退顺序和“使用了哪个方法”属于行为契约，不应无测试地调整。

## 厂商扩展的决策顺序

新增或修复设备支持时按以下顺序做最小扩展：

1. 确定应落在哪个通用 Layer，先复用已有 protocol/capability mixin。
2. 能用公共叶节点直接表达的能力只增加四哈希声明。
3. 需要选择数据源、拼接多个表、转换索引或有序回退时，增加小而确定的真实方法。
4. 只有设备固件确实违背标准或返回有害数据时才做厂商覆盖，并在注释和测试中记录原因。
5. 新具体类无法被选择时才修改 `device_type`，同时验证相近设备不会被误分类。

典型设计模式：

- H3C 复用 Layer3 和 IEEE802dot3ad，选择 Entity/sysDescr 数据生成身份，忽略 loopback，并因设备的 FDB→VLAN 映射错误而明确返回空映射，让上层采用安全默认行为。
- Cisco 基类组合 CDP、VTP、BGP、QoS、Power、Config 等窄能力模块，只为 VLAN 子接口、community indexing 和 EIGRP 地址做业务归一化。
- Juniper 在旧 VLAN 表与 ELS 表之间回退，并把 bridge port/PVID/VLAN 索引映射回 `ifIndex`。
- Nexus 对固件交换 LLDP 字段、IPv4 表索引异常等已知偏差做版本化覆盖，输出仍保持通用契约。

不要复制整个父类来支持一个型号；不要为了“有值”选择不可靠表；空 hashref 可以是有意的安全降级。

## 写操作与设备安全

动态 `set_*` 和 `set_multi` 按各自解析路径选择声明属性或可解析对象；数值 OID 的支持和访问检查须分路径验证。标量默认 IID 为 `.0`；表写入必须明确 IID。成功与失败均应按现有 session/error 契约处理，尝试写入前应确认使用读写凭据。

- `_make_setter` 在发出请求前删除对应的下划线缓存标记，失败也保持失效；它不清空全部 `store`。`set_multi` 走 `_set`，需分别核对解析和缓存行为，不能假定与动态 setter 路径完全相同。
- `set_multi` 把多个 varbind 放入同一 SNMP 请求；任一赋值无效时设备应拒绝整组，不要在业务层声称已经部分成功。
- Bridge 的通用 VLAN 写方法默认报“不支持”；只有能验证 VLAN 存在、`ifIndex` 存在、禁止端口规则及 port-list 重建的设备类才实现。
- 测试真实设备写入前默认只生成计划，任何实际 set 都需要用户明确授权和可回滚方案。

## 防御式 Perl 规范

- 生产模块使用 `strict`、`warnings`、四空格、无 tab、约 78 列，以 `.perltidyrc` 为准。`xt/.perltidyrc` 与测试框架可有自己的约定，不对全仓一刀切。
- 声明显式 `@ISA`、`@EXPORT_OK`、`our ($VERSION, %MIBS, %GLOBALS, %FUNCS, %MUNGE)`，文件以真值结束。
- 对已约定“hashref 或 undef”的可选表可用 `|| {}`；不可信输入先校验类型，空表回退不能掩盖采集失败。对 `0` 合法的字段使用 `defined`；检查键是否出现则用 `exists`。
- 新增归一化 helper 宜小而确定；返回 `undef`、空表还是原始值，应由具体公共方法和消费者决定，不能全库统一替换。NetScaler 版本解析的缺失值为例外，见 `t/netscaler_os_ver.t`。
- 公共方法名必须沿用跨厂商词汇，原始厂商 accessor 可清楚标明为内部原料。
- 保持 POD 与实际继承、必需模块、GLOBALS、表方法、override、setter 一致；行为变更更新 `Changes`。
- 所有类的 `$VERSION` 按当前版本同步测试维护。`contrib/DEVELOP` 中 CVS/RCS 与 `-cvs` 说明已过时，不作为新版本操作步骤。

## 测试契约与扩展清单

测试体系以 `xt/lib/My/Test/Class.pm` 为基类，向 `SNMP::Session` 注入 mock，并以 `Data` 和原始 cache 模拟 SNMP 返回。设备类测试优先放在对应 `xt/lib/Test/SNMP/Info/...`；已有 `t/` 中的独立 Test::More 回归也应保留。`xt/21_run.t` 有排除模块列表，文件存在不等于默认执行。

按本次变更选择以下场景；新增设备类应覆盖构造、声明和分类，公共行为变化补对应用例：

1. 类可构造，四哈希已初始化，代表性叶节点可解析。
2. `%GLOBALS/%FUNCS` 的动态方法均可验证，`%MUNGE` 值均为 CODE。
3. `device_type` 能选择新类，并包含相邻分类的负向样例。
4. 每个新增真实 public 方法都有测试；测试基类会检查本地方法覆盖率。
5. 正常、缺失、`undef`、零值、重复名称、异常索引、fallback 和 partial/cache 行为。
6. setter 请求、IID、值、错误传播及缓存失效；不接触真实设备。

聚焦执行、分发门禁命令与发布顺序见 [ci-release.md](ci-release.md)（“SNMP::Info 测试与 CI”）。本地门禁依赖可用的 `netdisco-mibs` 安装来解析模块和叶节点。若新增叶节点依赖尚未发布的 netdisco-mibs，先发布该依赖，再发布 SNMP::Info。

## 常见错误

- 只加 `use`/`@ISA`，遗漏四哈希合并。
- 调整哈希顺序却没检查真实 MRO，或反之。
- 直接把协议索引当作 `ifIndex`。
- partial 获取后错误标记完整表缓存。
- setter 后保留陈旧缓存。
- 用空串、`unknown` 或 `0` 掩盖 `undef`；或把合法 VLAN 0 当缺失。
- 为单一固件问题复制大段父类逻辑。
- 只测“有值”路径，不测错误表、回退和相邻设备分类。


## 从源码提炼的实现方法

### 能力组合有两套覆盖规则

**适用问题。** 一个设备需要增加协议能力，或同名方法在不同平台返回不同数据。

**方法。** 先列出真实方法的 `@ISA` 查找顺序，再列出四哈希从左到右的覆盖顺序；它们应产生预期结果，但不要求机械使用同一顺序。用 `MRO.pm` 查来源，并验证实际调用。真实 override 与动态映射都可能是最终消费者看到的入口。

**案例。** `Layer7/QNAP.pm` 组合 Layer7 和 Entity，声明厂商原始标量，再以小方法实现 `model`、`os_ver` 和 `e_swver`。`Info.pm::can` 每次返回适合当前对象的 closure，避免全局符号表污染。

**反例与验证。** 只加 `@ISA` 不会引入四哈希；缓存同名 closure 到全局会串设备。让两个具有不同映射的设备对象交替调用同名能力，验证结果不互相污染，并分别检查真实方法与动态方法。

### 把索引转换当作连接不同表的业务逻辑

**适用问题。** 多张 SNMP 表看似都用数字键，但数字属于不同空间。

**案例。** `Layer3/Juniper.pm::i_vlan` 先把 public partial（ifIndex）反查为 bridge port，再取 PVID，最后经 `bp_index` 转回 ifIndex；使用 `defined` 保留合法 VLAN 0。`LLDP.pm::lldp_if` 保留远端复合 IID 作为结果键，把本地端口映射为结果值。

以 Juniper 路径为例，设计时明确：

```text
请求 ifIndex -> 反向 bp_index -> bridge port -> qb_i_vlan
返回 bridge port -> bp_index -> ifIndex；PVID -> v_index -> VLAN
```

**反例与验证。** 不能直接把 bridge port 当 ifIndex，也不能默认 `reverse %map` 一定一对一。新增转换先验证唯一性、缺失中间键、合法 0、partial 范围和最终键空间。现有 LLDP 反向 hash 在重复名称时可能丢映射，不能把它宣传为自动解决歧义的算法。既有 fixture 见 `xt/lib/Test/SNMP/Info/LLDP.pm::lldp_if`、`Layer3/Juniper.pm::i_vlan`。

### 缓存同时记录值、是否尝试与覆盖范围

**适用问题。** 重复读取、局部读取与离线重放需要复用同一公共 API。

**实现。** `_global` 用 `exists` 识别已尝试的标量，失败后也保存 undef；`_load_attr` 对非 partial 结果调用 `_cache`，partial 直接返回；`_munge` 在返回时转换，避免把展示值写回 raw cache。非 partial 不代表网络读取必然完整：循环或协议错误也须看 error 状态。

**验证序列。** mock 会话记录请求次数和 varbind：首次读取→重复读取→partial→完整读取→load→raw→setter 失败→再次读取。分别断言命中、重取、原始值和失效标记，不只断言“返回了数据”。Offline 测试还要确认没有读取请求。现有 mock 构造见 `xt/lib/My/Test/Class.pm::create_mock_session`；这些场景是测试设计要求，不代表已有完整覆盖。

### 有序回退要保留可信来源与消费者一致性

**案例。** QNAP 根据 sysObjectID 选择 QTS/QuTS 查询顺序；空白和尾部 NUL 经 `_qnap_value` 归一化，固件回退依次参考专用标量、严格匹配的 sysDescr、Entity。`e_swver` 只修正机箱版本，并复制结果 hash，避免改写共享原始表；直接读取原始 Entity 叶节点避免再次进入自身 override。

**方法。** 每一级来源写清适用范围和退出条件；失败后回退不等于任取一个有值字符串。沿调用者检查同一事实是否由不同 public 方法呈现，再决定在公共能力层统一，而非逐个修改报表。

**反例与验证。** 通用 Linux 内核描述不能当 QNAP 固件；缺少机箱版本不应改写模块版本或 raw cache。参考 `xt/lib/Test/SNMP/Info/Layer7/QNAP.pm` 的新旧 enterprise、空值、QuTS 前缀、sysDescr 负例及机箱/模块版本用例。修补一种设备时仍需验证相邻设备分类和父类回退。
