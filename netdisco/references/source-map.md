# 研究基线与源码定位

**目录**：基线 · 证据读法 · 三条调用链 · 目录入口 · 易变事实 · 定位命令

## 研究基线

2026-09-30 对本地 checkout 静态研读；不是全库逐行审计，也不是远端最新版本或运行时验收。

| 根目录 | HEAD | 已有工作区修改 |
|---|---|---|
| `$SI`：研究时的 SNMP::Info checkout | `a3c0eddfb835f3f1ffbc688895d15dbabb08bfde` | `lib/SNMP/Info/Layer3/Nexus.pm` |
| `$ND`：研究时的 Netdisco checkout | `aded1c1b7315c1604cece21f692535ee07ea1adc` | `Changes`、`MANIFEST`、`lib/App/Netdisco/Util/Node.pm`、`lib/App/Netdisco/Worker/Plugin/Discover/Neighbors.pm`；未跟踪 `xt/56-neighbor-local-alias.t` |

`$SI` 和 `$ND` 只是下文的路径代号。实际任务使用用户指定的 checkout，不修改产品仓库来适配 skill。

本轮关键案例取自未修改的核心文件，特别是 QNAP、Info 核心、Job/Runner、Macsuck、Properties 和 Web 原语。涉及 Nexus 或邻居身份的新结论时，先比较本地 diff 与 HEAD，不能当作已发布行为。已提交也不代表与官方上游所有版本一致。

## 证据读法

- **实现事实**：用文件和符号定位，读调用者与消费者确认范围。
- **方法建议**：从实现提炼的可复用选择，例如新多驱动采集优先共享 store；不是要求历史模块全部迁移。
- **回归要求**：建议新增变更应覆盖的场景，不等于现有测试已覆盖或本轮已运行。
- **历史说明**：注释、POD、CLAUDE.md 和旧开发指南也可能落后。发现冲突记录事实；例如 SNMP::Info 的 CVS 发布说明、测试中的旧符号表注释，以及 Netdisco 的旧前端描述，均不能盖过当前代码。

## 三条代表调用链

路径以表中的根为前缀；符号名比固定行号更适合跨版本定位。

| 根 | 文件与符号 | 应理解的契约 | 测试或交叉证据 |
|---|---|---|---|
| `$SI` | `lib/SNMP/Info.pm`：`new`、`specify`、`can`、`AUTOLOAD` | 注入会话、动态方法与真实 override、对象级映射 | `xt/lib/My/Test/Class.pm`：`setup`、`constructor` |
| `$SI` | `lib/SNMP/Info.pm`：`_global`、`_load_attr`、`_cache`、`_munge`、`_make_setter` | 已尝试/值/范围、raw 与转换、请求前失效 | `xt/lib/Test/SNMP/Info.pm`、mock session；新增序列测试见 snmp-info |
| `$SI` | `lib/SNMP/Info/Layer7/QNAP.pm`：`_qnap_value`、`os_ver`、`e_swver` | 窄覆盖、有序回退、机箱与模块数据所有权 | `xt/lib/Test/SNMP/Info/Layer7/QNAP.pm` |
| `$SI` | `lib/SNMP/Info/LLDP.pm`：`lldp_if`；`lib/SNMP/Info/Layer3/Juniper.pm`：`i_vlan` | 复合 IID、bridge port、ifIndex 与 VLAN 键空间 | 对应 `xt/lib/Test/SNMP/Info/LLDP.pm`、`Layer3/Juniper.pm` |
| `$ND` | `lib/App/Netdisco/Util/Configuration.pm`：`parse_params_to_config`；`Backend/Job.pm`：`BUILDARGS` | job 参数转换、输入修改与配置副作用 | `xt/50-config-override.t` |
| `$ND` | `lib/App/Netdisco/Worker/Plugin.pm`：`register_worker`；`Worker/Loader.pm`：`load_workers`；`Worker/Runner.pm`：`run` | 注册、namespace 内排序、资格、异常与恢复 | `xt/30-backend-workers.t`、`xt/lib/App/NetdiscoX/Worker/Plugin/` |
| `$ND` | `lib/App/Netdisco/Backend/Job.pm`：`check_passed`、`best_status`、`finalise_status` | 放行、hook 判断与最终状态不同 | `Worker/Status.pm::level`、`Worker/Plugin/Macsuck/Hooks.pm` |
| `$ND` | `lib/App/Netdisco/Worker/Plugin/Macsuck/Nodes.pm`：各 phase、`store_node` | fwtable、时间戳、store 与 Node 历史 | 交叉读 `Macsuck/WirelessNodes.pm` 的 main 写库例外 |
| `$ND` | `lib/App/Netdisco/Worker/Plugin/Discover/Properties.pm`：field_protection、端口替换 | 可信旧值、人工字段与阶段事务边界 | `DB/ExplicitLocking.pm::txn_do_locked` |
| `$ND` | `lib/App/Netdisco/DB/Result/Device.pm::renumber`、`Util/Device.pm::renumber_device` | 聚合迁移与调用端事务、旧任务删除 | `Worker/Plugin/Renumber.pm`；数据库验证要求见 database |
| `$ND` | `lib/App/Netdisco/Web/GenericReport.pm`、`Web.pm` 模板/响应 hook | tenant、bind、results 键、HTML/CSV/API | `xt/44-results-token-escaping.t`、`xt/53-ports-csv-arity.t` |
| `$ND` | `lib/App/Netdisco/DB/Result.pm`、`DB/Result/Device.pm::serializable_columns` | 列而非关系序列化，凭据在公共边界剔除 | `xt/78-device-serializable-columns.t` |
| `$ND` | `share/public/javascripts/netdisco.js`、`netdisco-tables.js`、`netdisco-admin.js` | HTMX 与注册表各自拥有生命周期 | `xt/js/history-ownership.test.js`、`page-registry.test.js`、`tables-registry.test.js` |

表中省略 `lib/App/Netdisco/` 的后续 Perl 路径继承同一前缀。测试记录的是可借用的机制，不暗示它覆盖本行全部契约。

## 按目录补充定位

Netdisco：

- 环境与配置：`lib/App/Netdisco/Environment.pm`、`Configuration.pm`、`share/config.yml`。
- 凭据与传输：`lib/App/Netdisco/Transport/`、`Util/SNMP.pm`、`Util/DeviceAuth.pm`、`Util/Snapshot.pm`。
- 队列与调度：`lib/App/Netdisco/JobQueue.pm`、`JobQueue/`、`Backend/Role/`、`DB/Result/Virtual/WalkJobs.pm`。
- 模型与迁移：`lib/App/Netdisco/DB/Result/`、`DB/ResultSet/`、`share/schema_versions/`；外部/通用 schema 在 `GenericDB/`。
- 插件与运维：`lib/App/Netdisco/Worker/Plugin/`、`Web/Plugin/`、`Web/Health.pm`、`Web/Metrics.pm`、`bin/`。
- UI 与测试：`share/views/`、`share/public/`、`xt/`、`xt/js/`、`xt/snapshots/`。

SNMP::Info：

- 能力与平台：`lib/SNMP/Info/{Layer1,Layer2,Layer3,Layer7}.pm`、各 Layer 子目录与顶层协议模块。
- 组合诊断：`lib/SNMP/Info/MRO.pm`。
- 风格与测试：`.perltidyrc`、`xt/.perltidyrc`、`xt/00_local_perlcritic.t`、`xt/21_run.t`、`t/`、`xt/lib/`。

两库发布均从 `Build.PL`、`Changes`、`META.*`、`MANIFEST` 与 `.github/workflows/` 入手。只查 netdisco-mibs 的依赖/发布元数据；MIB 正文范围由用户决定。

## 易变事实

以下值只属于上述基线；引用时在目标 checkout 复核，避免在多个文档维护第二份版本清单。

| 项目 | 本轮值或观察 | 事实源 |
|---|---|---|
| Netdisco schema | 整数 100 | `lib/App/Netdisco/DB.pm` 与迁移链 |
| 前端依赖 | Bootstrap 5.3.8、DataTables 3.0.3、HTMX 4.0.0；无 jQuery | `package.json`、layout 实际加载与移除守卫 |
| 前端运行器 | Node 22、显式列出测试文件 | `.github/workflows/frontend-tests.yml` |
| 版本与标签 | Netdisco 数字版本；SNMP::Info 当前模块为 3.977001 | `Changes`、模块 VERSION、标签和工作流过滤器 |
| CLI 扇出限制 | 非 force 时解析后最多 512 主机 | `bin/netdisco-do` |
| 发布结果 | 上传步骤允许失败后继续 | 两库发布 workflow 的 step outcome 和实际产物 |
| 邻居回退、CSS、字段与权限 | 不固化为跨版本常量 | 目标方法、CSS、Result 与路由测试 |

## 定位命令

在对应仓库根执行；shell 模式用单引号，防止 `$VERSION` 等被展开。

```sh
git status --short --branch -uall
git log -1 --format='%H %s'
rg --files -g AGENTS.md -g CLAUDE.md
```

Netdisco：

```sh
rg -n 'register_worker|load_workers|run_workers|best_status|finalise_status' lib/App/Netdisco
rg -n 'parse_params_to_config|field_protection|txn_do_locked|sub renumber' lib/App/Netdisco
rg -n 'register_report|serializable_columns|pane_chrome|HX-Push-Url|HX-Replace-Url' lib/App/Netdisco
rg -n 'ndPages|ndTables|ndRequest|ndToast|htmx.config' share/public/javascripts/netdisco*.js
rg -n 'schema_version|\$VERSION' lib/App/Netdisco/DB.pm
rg --files share/schema_versions xt/js
```

SNMP::Info：

```sh
rg -n '^(package|our |sub |%MIBS|%GLOBALS|%FUNCS|%MUNGE|@.*::ISA)' lib/SNMP
rg -n 'device_type|AutoSpecify|AUTOLOAD|_load_attr|_global|_munge|Offline|Cache' lib/SNMP/Info.pm
rg -n 'all_methods|globals|funcs|munge|superclasses|print_' lib/SNMP/Info/MRO.pm
rg -n 'bp_index|ifIndex|partial|SUPER::|orig_|load_|_raw|set_multi' lib/SNMP
rg --files xt/lib/Test/SNMP/Info t
```

零命中先放宽关键字或查目录，不能据此断言机制不存在。普通研读不用刷新远端；需要“最新版”结论时另行核验目标版本。
