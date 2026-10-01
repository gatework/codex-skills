# 测试、持续集成与发布

## 核对事实源

在目标 ref 下分别检查两个仓库：

```sh
git status --short --branch -uall
git describe --tags --always --dirty
git log -1 --date=iso --format='%H%n%ad%n%s'
```

不能假定当前检出的提交就是最新发布版。需要核对 `Changes`、模块 `$VERSION`、`Build.PL`、`META.*`、工作流，以及 Netdisco 对 `SNMP::Info` 的最低版本要求。

## Netdisco 测试与 CI

先确认 Module::Build、Perl 依赖与 share 路径。CI 使用 backend 容器和其中的 `localenv`；本地已具备依赖时可直接执行，不为启动器问题修改依赖清单。分发初始化及门禁：

```sh
perl ./Build.PL
./Build test --test_files xt/
```

`xt/` 包含编译/POD 测试，以及 ACL、Worker 加载、MIB 加载安全、vendored 清单、登录与响应行为、转义、压缩、拓扑遍历、HTMX History 所有权、站点本地兼容、JavaScript 模板扫描、模块确定性排序和模板渲染快照等聚焦回归守卫。

前端工作流显式列出 `xt/js` 下的 Node 测试文件，避免文件改名或 glob 行为使实际执行集合悄悄改变。检查 TAP 测试数和跳过项，不只检查退出码。先直接运行变更相关测试，再运行 `.github/workflows/frontend-tests.yml` 中的每条明确命令。前端供应链 CI 还会对 `share/public` 运行 retire.js。CodeQL 扫描 JavaScript 和 Python，不扫描 Perl。

数据库或运行时变更还需在 PostgreSQL 上完成部署/升级，并验证相关路由或 Worker 流程。SNMP 行为需要快照、mock 或经授权的测试设备。分发门禁通过不能代替这些集成验证。

发布移除或替换浏览器 API 时，使用 `checksitelocal` 动作检查配置的模板路径，验证扩展兼容性。该检查只做诊断且只读；如果移除的依赖可能让站点本地模板静默失败，应增加源码规则和回归覆盖。

## Netdisco 版本与发布流水线

所研究源码（快照）使用 `2.NNNNNN` 形式的标签；以 `git tag` 与 `Changes` 为准。发布版本来自 `Changes` 最新区块。`App::Netdisco::Builder::ACTION_distmeta` 会重建 `MANIFEST`，对 `lib/App/Netdisco.pm` 运行 `perl-reversion`，刷新构建对象中的分发版本，再生成元数据。

打包会修改 MANIFEST、模块版本和生成元数据，应在隔离 checkout 中按当前 Builder/workflow 执行，并审查产物差异。Netdisco 的 `ACTION_distmeta` 自行重建清单；不要在用户脏工作区照抄 CI 的删除命令。完成构建初始化后：

```sh
./Build distmeta
./Build dist
```

标签触发后，CI 会在上传前确认 `App-Netdisco-${TAG}.tar.gz` 存在且 CPAN 上没有同名版本。CPAN 上传步骤允许失败后继续，因此必须检查上传步骤和 CPAN 实际产物，不能只根据工作流整体绿色判断发布成功。

GitHub 发布工作流会为标签创建 GitHub Release。构建工作流还通过 `netdisco-docker` 构建 amd64 和 arm64 的 Web、后端与 PostgreSQL 镜像，组装多架构索引，并把标签及 `latest-*` 别名发布到 Docker Hub 和 GHCR。标签还可以触发 demo 数据库重新部署及 demo 镜像构建。这些操作会修改外部状态，需要明确授权，并逐项验证产物。

发布 schema 变更时，通过 `netdisco-db-deploy` 测试数据库升级，确认应用 schema 整数和迁移链到达同一版本。发布说明还要覆盖站点本地插件、API 和前端兼容性。

## SNMP::Info 测试与 CI

分发门禁：

```sh
perl ./Build.PL
./Build test --test_files t/ --test_files xt/
```

聚焦测试示例：

```sh
prove xt/21_run.t :: Test::SNMP::Info::Layer3::H3C
```

测试框架构造 mock `SNMP::Session`，检查构造器和声明式哈希，验证 MIB 叶节点解析，执行缓存、离线和动态方法，并要求公共设备类方法具有对应测试覆盖。本地分发检查包含加载、文档/POD、前置依赖、拼写、Perl::Critic 严重度 5 和版本同步。部分可选检查在测试依赖缺失时会跳过，交付报告必须说明跳过项。`xt/21_run.t` 还显式排除若干模块；不能从文件存在推断执行覆盖。

`xt/10_remote_snmplabs.t` 仅在 `AUTHOR_TESTING` 启用时访问外部测试设备。离线验收先确认该变量未启用，不把远端测试跳过记为通过。

CI 会下载最新版 netdisco-mibs 用于测试，这只是运行时和测试依赖。完整本地测试需要 Net-SNMP Perl 模块和兼容的 MIB 目录。

## SNMP::Info 版本与发布流水线

所有模块使用相同的 `$VERSION`，`xt/00_local_versionsync.t` 强制检查一致性。发布时同步更新 `Changes`、每个模块版本、README/生成元数据和分发归档。所研究标签（快照）使用 `3.x` 十进制版本，研究值见 [source-map.md](source-map.md)；应读取当前标签规则，不能套用语义化版本假设。

测试成功后，CI 会重建 `MANIFEST`、元数据和 `SNMP-Info-*.tar.gz`。标签流程先检查 CPAN 是否已有同名产物，再使用 PAUSE 凭据上传。上传步骤允许失败后继续，并会发送 IRC 通知，因此仍需独立确认 CPAN 产物。另一个工作流负责创建 GitHub Release。

如果新能力依赖尚未发布的 MIB 定义，先发布匹配的 netdisco-mibs，再发布 SNMP::Info；Netdisco 确实调用新能力时再提高最低依赖并验证集成。数值 OID 或已发布定义不自动要求新 MIB 发布。

## 发布检查清单

执行获准的标签或发布前：

1. 确认工作树和目标提交，不夹带无关变更。
2. `Changes` 说明用户可观察变化及兼容影响。
3. 标签、模块版本、最低依赖、`META.*` 和归档名一致。
4. 聚焦测试与完整测试通过，跳过和失败均已分类。
5. 按风险验证数据库迁移、快照、浏览器行为或真实设备行为。
6. 生成后的 `MANIFEST` 包含运行资源及项目要求分发的测试/夹具，排除临时产物和密钥；检查解包后仍可执行声明的测试。
7. CPAN 重复检查和凭据已经准备好。
8. Netdisco 镜像架构、标签和后续 demo 部署已获得明确授权。
9. 发布后分别检查 GitHub Release、CPAN 产物、Docker Hub/GHCR manifest 和 demo。

`continue-on-error`、通知成功、标签创建或工作流总体结论，都不能证明每个 registry 已经接受产物。


## skill 自身的维护验收

仅在维护本 skill 时使用本节；普通产品改动按前述风险选择测试，不额外执行整套 skill 走查。

使用可用的 skill-creator `quick_validate.py` 检查 frontmatter，再检查 YAML 元数据、相对链接和引用的源码文件/符号。校验器通过只证明结构合法，不证明指导正确。逐项从入口选读，核对以下六个任务能否作出有证据的决策：

| 代表任务 | 应得到的决策 | 应拒绝的错误捷径 |
|---|---|---|
| 新增厂商设备 | 先选 Layer/能力组合，再用四哈希或窄方法；分类与相邻设备负例 | 复制父类或只改 Netdisco 展示 |
| LLDP/VLAN 索引错误 | 明确源/目标键、partial 方向、缺失和重复映射 | 数字键一律当 ifIndex |
| partial 后读取整表 | 区分 partial、非 partial 标记、raw、error 和 Offline；核对请求次数 | 空表等于成功、已缓存等于完整 |
| 增加 API 采集 driver | 对齐 stash、namespace/priority、store 与时间戳；区分三种状态判断 | 全局 priority 排序、error 自动停止、main 永远不写库 |
| 新增 tenant 报表 | 配置/插件选择、bind、schema、输出与 HTMX 生命周期一起维护 | 查询默认库、重新引入 jQuery、只测 HTML |
| 跨仓库发布 | 依赖确有需求时按 MIB→SI→ND 顺序；隔离打包、核对 step outcome 与产物 | 工作流绿色等于全部发布成功 |

再做两个边界反例：普通单文件修复不应加载全部资料；只读分析不应触发设备写入、打包或发布。走查结果报告为人工静态验收；除非实际做过独立执行，不称为 agent 行为测试或产品端到端验收。
