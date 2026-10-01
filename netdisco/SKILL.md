---
name: netdisco
description: 开发、理解、重构、审查和交付 Netdisco 与 SNMP::Info：设备能力与厂商适配、Perl 范式、采集 Worker、数据模型、Dancer Web/API、测试及运维发布。用于这两个项目及其站点插件，以目标源码的契约指导实现；不用于通用 SNMP 咨询或 MIB 文件正文分析。
---

# Netdisco

把设备差异封装成稳定能力，把观测数据变成可信库存，把扩展接入已有运行机制。先辨明契约和所有权，再选择最小改动层。

以用户指定 checkout 的源码、测试、配置、POD 和工作流为事实源；遵循适用的仓库指引。下文 `$ND` 为 Netdisco 根目录，`$SI` 为 SNMP::Info 根目录。[研究基线与源码地图](references/source-map.md) 区分已提交实现、本地修改和易变事实。旧注释或本文与可执行代码不一致时，说明差异，不能据此悄悄改变产品行为。

## 先选择职责与资料

| 问题 | 首选落点与选读资料 |
|---|---|
| 某厂商数据异常、新设备或协议能力 | SNMP::Info 公共方法、协议组合、设备覆盖：[snmp-info](references/snmp-info.md) |
| 新采集器、配置兼容、Worker 状态、临时上下文 | Transport / Configuration / Worker：[architecture](references/architecture.md)、[netdisco-patterns](references/netdisco-patterns.md) |
| 新功能或站点定制，应使用哪种扩展 | 先配置、报表、自定义字段或 hook，再 Worker/Web 插件：[functional-capabilities](references/functional-capabilities.md) |
| 身份、历史、查询、事务或 schema 迁移 | Result / ResultSet / SQL 迁移：[database](references/database.md) |
| 路由、权限、tenant、页面和多格式输出 | Dancer v1、Web 插件、Template Toolkit 与当前前端原语：[web-ui](references/web-ui.md) |
| 测试、打包、依赖升级或发布 | 按目标工作流选门禁：[ci-release](references/ci-release.md) |
| 系统研读、跨层变更或源码定位 | 从一条实际调用链开始：[source-map](references/source-map.md) |

只加载任务所需资料。不要把协议索引修复放进路由，把站点定制做成平行应用，或为小功能读取整套参考资料。

## 编程决策

- **先追消费者，再改生产者。** 写清返回类型、键空间、缺失含义、排序和副作用；SNMP::Info 的表键、Worker stash、DBIC 查询列、模板数据键都是接口。
- **声明差异，复用机制。** 单叶能力用四哈希，多表关联用小方法，厂商例外用窄覆盖；Worker/Web 用注册接口，不复制执行器或页面外壳。
- **边界统一，内部明确。** 兼容输入在已有配置边界归一化；不要用 `||`、空表或占位值抹平合法零值、失败与真实空结果。
- **先确认可信度，再替换旧数据。** 声明采集拥有的字段、完整性证据和失败策略；集合替换须保留人工数据与历史。事务、取消和作用域恢复分别解决不同问题。
- **推荐结构不等于全库事实。** main→stash→store 是多驱动采集的优先结构；既有 main 写库等例外须按消费者与事务边界处理，不做顺手迁移。
- **在可观测边界验证。** 检查实际胜出的能力、最终 job 状态、持久化结果和渲染输出；源码守卫只证明它明确约束的结构。

具体方法、源码案例、反例和验证场景放在对应参考资料中；不要把一次设备故障或本地补丁升级为全项目规则。

## 执行方式

1. **建立基线。** 只在任务涉及的实际仓库根检查 `git status --short --branch -uall`、`git log -1`、适用的 `AGENTS.md` / `CLAUDE.md`；跨库变更才检查两库。保留已有修改。skill 目录可能不是 Git 仓库。
2. **定位契约。** 读调用者、实现、邻近测试和相关 `Changes`。沿设备能力→传输→Worker→模型→输出追到受影响边界，记录扩展方式和兼容要求。
3. **实施最小变更。** 新能力优先复用协议/插件/查询原语；状态、数据形状或公共方法变化同步维护测试、POD、必要的 `Changes` 与分发清单。
4. **按风险验证。** 先聚焦行为测试，再采用 [ci-release](references/ci-release.md) 的相关门禁。数据库、浏览器、真实设备和外部发布分别验收，不以编译或 mock 代替。

研究基线中的两个仓库使用 Module::Build。Netdisco 以 `xt/` 为主要回归目录，前端使用 Node 内置测试运行器；当时的 `package.json` 是 vendored 清单，不是 npm 构建入口。先从目标 ref 确认构建入口、依赖和环境，再执行测试；命令详见测试参考资料。

## Perl 风格与兼容边界

- SNMP::Info 通常使用四空格、78 列、显式继承和包级能力哈希；以 `.perltidyrc`、当前 POD 和测试为准。`contrib/DEVELOP` 的 CVS 版本流程属于历史材料。
- Netdisco 通常使用两空格、Dancer 导入、Moo/Moo::Role、`namespace::clean`、Try::Tiny 和 DBIx::Class。遵循目标模块的导入方式；是否启用 strict/warnings 要考虑框架导入，不以缺少显式两行判错。
- 保留标量/列表上下文、`exists`/`defined`/真假值、hashref 别名、返回状态和扩展钩子语义；不跨仓库批量套用格式或“现代化”写法。
- 注释解释约束与原因，POD 说明公共行为；命名沿用设备能力、领域动作和现有 phase/namespace 词汇。

## 操作边界

- 默认不读、不改 MIB 文件正文；代码中的模块名、叶节点和数值 OID 可分析。用户明确扩大范围时遵循其范围。
- 不把凭据写入日志、hook 数据、错误响应或报告。未经授权不写真实设备、不打发布标签、不上传 CPAN/镜像、不部署。
- 部署配置放 Netdisco home 的 `environments/deployment.yml`；修改默认键及其语义时才改 `share/config.yml`。前端第三方依赖走完整 vendoring 流程，不直接修补压缩产物。
- `--dry-run` 只点名 Worker；`--rollback` 只覆盖特定数据库事务，都不是端到端副作用隔离。细节见功能参考资料。

## 交付

说明行为变化、主要文件、实际测试结果、跳过项和未验证边界。审查时按严重度给出位置、被破坏的契约、失败场景与最小修复，区分运行验证和静态推断。源码未显示完整性、原子性或成功条件时，不替实现作保证。
