# 工作流与输出模板

将仓库理解转成可执行实现、审查或 Codex 计划时读取本文件。

## 目录

- [工作流：新增 CRUD 管理模块](#工作流新增-crud-管理模块)
- [工作流：新增业务动作或状态流](#工作流新增业务动作或状态流)
- [工作流：新增或修改权限](#工作流新增或修改权限)
- [工作流：新增通知渠道或外部 provider](#工作流新增通知渠道或外部-provider)
- [工作流：身份或账户生命周期变更](#工作流身份或账户生命周期变更)
- [工作流：安全性 destructive workflow](#工作流安全性-destructive-workflow)
- [工作流：前端页面重构](#工作流前端页面重构)
- [工作流：并发 Bug](#工作流并发-bug)
- [工作流：代码审查](#工作流代码审查)
- [工作流：依赖或技术栈升级](#工作流依赖或技术栈升级)
- [工作流：部署与生产准备](#工作流部署与生产准备)
- [工作流：重命名与兼容性重构](#工作流重命名与兼容性重构)
- [工作流：性能与容量问题](#工作流性能与容量问题)
- [工作流：Release 与制品发布](#工作流release-与制品发布)
- [输出：代码审查](#输出代码审查)
- [输出：实现结果](#输出实现结果)
- [输出：Codex 可执行整改计划](#输出codex-可执行整改计划)


## 工作流：新增 CRUD 管理模块

1. 找一个领域和交互最接近的现有模块，不只找“长得像”的页面。
2. 定义实体不变量、唯一性、删除/禁用/历史策略。
3. 定义 route、permission key、credential type 和数据范围。
4. 定义 request/response/error/pagination contract。
5. 设计 migration、约束、索引和并发语义。
6. 实现 model/service/query/serializer/controller。
7. 写 request/model/service spec。
8. 实现前端 API type。
9. 实现 query state、table、drawer/form、mutation convergence。
10. 接入 route/menu/button permission projection。
11. 补 zh-CN/en-US、主题、响应式、a11y。
12. 运行 focused checks，再运行项目完整门禁和浏览器验收。

## 工作流：新增业务动作或状态流

1. 用 [business-modeling.md](business-modeling.md) 的动作卡写出发起者、前置条件、权威状态与转换、不变量、副作用、收敛、审计和失败方向；
2. 画状态图，标出每条边的守卫、原子点和非法转换如何被拒绝；
3. 回答权限四问（谁、对谁、凭证、范围）与防提权；
4. 判断是否影响 Motor 现有生命周期（读 [business-workflows.md](business-workflows.md)）；
5. 再进入“新增 CRUD 管理模块”或“身份或账户生命周期变更”流程实现；
6. 测试覆盖非法转换、并发、重复执行、旧身份请求晚到和失败方向。

## 工作流：新增或修改权限

1. 从后端 action 的业务语义开始，不从菜单开始。
2. 判断是否独立 permission key。
3. 判断 JWT/API Token credential types。
4. 检查 admin bypass 和 impersonation。
5. 检查角色可分配范围和防提权。
6. 同步 `/api/permissions`、前端 route/menu/action。
7. 覆盖未认证、无权限、API Token、管理员、角色变化后的行为。
8. 身份切换后验证当前 route/tabs/subscriptions 收敛。

## 工作流：新增通知渠道或外部 provider

1. 定义 provider config 的最小字段和加密边界。
2. 定义 validation、secret redaction 和 SSRF 边界。
3. 核对现有 notification、派发意图与队列边界；仅在业务要求时设计额外 durable delivery 状态，不把建议当作现有 schema。
4. 定义 claim、timeout、retry、expected failure。
5. 说明 at-least-once 和 provider idempotency 方案。
6. 外部 I/O 不持 DB lock。
7. 写 provider/service/job spec。
8. 实现 UI 配置、test action、error/retry 状态。
9. 更新 docs 和生产 env/网络要求。

## 工作流：身份或账户生命周期变更

1. 画出 challenge/credential/session/role 当前状态流，不从页面按钮开始。
2. 列 actor、target、credential type、permission 和防提权边界。
3. 定义状态转换的数据库 authority、原子消费和并发序列化点。
4. 明确哪些 JWT/session/API Token/Cable projection 必须撤销、轮换或重建。
5. 明确 audit 中的 actor/target/request context。
6. 同步 API error code/message、前端 user/permission/route/tabs/subscription 收敛。
7. 覆盖正常、过期、重复消费、并发、禁用、越权和旧身份请求晚到。
8. 若改变登录/恢复/安全流程，验证 rate limit、枚举泄露和双语言用户提示。

## 工作流：安全性 destructive workflow

用于账户自动禁用、日志/历史清理等必须先满足前置条件的任务。

1. 写出 eligibility 与“不允许提前执行”的安全不变量。
2. 定义 prerequisite evidence，例如必要通知成功、所有目标已确认、备份完成。
3. 将 notice/result/deadline 持久化，不把一次进程内成功当长期事实。
4. 让首次扫描只建立证据和宽限期，不同轮执行 destructive action。
5. deadline 到达时重新读取当前状态并重新检查最后管理员、活动状态、retention 等 guard。
6. 外部 I/O 与数据库锁分离，同时设计 provider 成功/DB 未提交、部分成功和重复提醒窗口。
7. destructive action 分批且可审计；失败方向保持 fail-closed。
8. 用可控时间、双 worker/双连接和 side-effect fake 写确定性测试。

## 工作流：前端页面重构

1. 先列当前页面的业务区块和独立 async lifecycle。
2. 标记 query state、mutation state、drawer/form state、identity-dependent state。
3. 先修 correctness 问题，再做结构拆分。
4. 提取纯 codec/helper。
5. 第二个真实调用方出现后再提取 shared composable/component。
6. 保持页面为 orchestration layer。
7. 不顺手引入第二套 schema form、request client 或权限体系。
8. 用 race tests + browser states 证明重构没有改变行为。

## 工作流：并发 Bug

1. 用一句话写出被破坏的不变量。
2. 写具体竞争序列：A 读什么，B 读什么，谁先写，最终为什么非法。
3. 找所有参与的锁、unique/check/FK、transaction boundary。
4. 选择最小共同序列化点或原子数据库条件。
5. 写确定性双连接/可控 barrier 测试。
6. 修复。
7. 搜索同形 read-check-write/replace/consume 代码。
8. 运行 focused + full relevant tests。

## 工作流：代码审查

1. 固定目标 ref/diff 和工作树范围。
2. 读取项目契约、schema、lockfile、相关 tests。
3. 按跨层链路检查业务实现。
4. 优先 correctness/security/data loss/privilege/concurrency。
5. 再看可维护性、性能、UI 完整性、生产交付。
6. 每个 finding 通过“触发条件 + 坏结果 + 不变量 + guard 不足”质量门。
7. 高风险 finding 重新读上下游，主动尝试推翻自己的结论。
8. 输出 findings first，不用评分代替问题。

## 工作流：依赖或技术栈升级

1. 读取 lockfile、Dockerfile、CI 当前版本。
2. 阅读官方 migration/changelog，不从 skill 记忆版本差异。
3. 判断 Ruby/Rails/PostgreSQL/Node/pnpm/Vue/Vite 等兼容组合。
4. 更新声明和锁文件。
5. 检查 Docker build/cache/volume 是否仍同步依赖。
6. 跑完整 test/lint/audit/build。
7. 更新 docs 中真正需要固定的最低/兼容边界，不复制锁文件全文。

## 工作流：部署与生产准备

1. 读取当前 `deploy/`、`docs/DEPLOYMENT_GUIDE.md`、Dockerfile、Compose、CI 和锁文件，不继承历史“已就绪”结论。
2. 区分开发编排、镜像可构建、配置可部署、代表性环境已验证四个层级。
3. 检查 Web/Worker 分离、non-root、secret 注入、数据库/Redis/文件持久化和资源边界。
4. 为 migration 定义 release job、旧新 schema 兼容窗口、备份与恢复路径。
5. 检查 Sidekiq/Cable/CORS/TLS/trusted proxy/health readiness 与前端 API/Cable 外部地址。
6. 检查日志、指标、告警、queue latency、备份恢复和 rollback 证据。
7. 运行当前仓库定义的 lint/test/audit/package/config checks。
8. 没有代表性环境 smoke/restore 证据时，只能报告“代码/配置层准备度”，不能声明 production-ready。

## 工作流：重命名与兼容性重构

1. 先读取当前 ref，列出 internal / durable / external surface；
2. 搜 route/action、permission key、DB schema/data、serializer/API、frontend caller、job class/queue、env/config、event/cache key；
3. 判断哪些可原子 rename，哪些需要 migration/alias/dual-compatible window；
4. 对 persisted permission/token/job/schema 写显式迁移或兼容策略；
5. 先补能证明旧行为/兼容窗口的 regression test；
6. 做最小 rename，不顺手扩大结构重构；
7. grep stale symbol + 运行 focused/full gate；
8. 说明兼容层何时可删除。

## 工作流：性能与容量问题

1. 记录真实慢路径、代表性数据规模和 baseline；
2. 判断瓶颈在 DB/query、network/payload、Vue render、Sidekiq、Redis 还是 provider；
3. 使用 query plan/profile/queue metrics 找根因，不从“感觉慢”直接改架构；
4. 先做最小负责层优化，并保留正确性测试；
5. 同条件复测 before/after；
6. 记录 index/memory/connection/bundle 等新增资源成本；
7. 没有代表性运行数据时降低结论措辞。

## 工作流：Release 与制品发布

1. 冻结 source ref、release lane 和当前 required checks；
2. full source gate；
3. 构建真正 production artifact，记录 digest；
4. 对 exact artifact 做 migration/runtime/browser smoke；
5. 运行 security/vulnerability 与适用的 SBOM/provenance；
6. 基于同一 digest promotion/publish，不重新 build；
7. 读回 registry/release artifact 验证 digest/manifest/attestation；
8. GitHub Release 最后创建/完成；
9. 记录 rollback digest、schema compatibility 和未验证项；
10. 未经授权不修改 branch protection、repository secret 或生产环境。

## 输出：代码审查

优先级依影响、触发范围和可恢复性判断：P0 为广泛且紧急的严重故障，P1 为应优先修复的关键缺陷，P2 为可排期的可靠性/正确性问题，P3 为低影响问题。不能仅按类别自动阻塞或判可合并，结合当前交付要求决定。见 [交付原则](../SKILL.md#验证与交付)。证据用 `[源码]` `[运行]` `[推断]` `[未验证]` 标注来源等级。

```text
结论：<可合并 / 需修复 / 阻塞>
范围：<ref/diff/模块>
证据：<源码/schema/tests/CI/运行时，各带等级标签>

P1 <标题>
- 路径：...
- 触发：...
- 结果：...
- 不变量：...
- 现有防护为何不足：...
- 最小修复：...
- 回归测试：...

优点：<只写与本次范围直接相关的强设计>
未验证：<浏览器/并发/生产等 gap>
```

如果没有可靠 finding，直接说“未发现需要阻塞的代码质量问题”，列清审查范围和残余风险，不制造问题。

## 输出：实现结果

```text
结果：<完成 / 部分完成 / 阻塞>
保留契约：<关键不变量>
变更：
- <file>: <职责和变化>

契约变化：
- DB: ...
- API: ...
- Permission: ...
- Config: ...

验证（每项带 [源码]/[运行]/[推断]/[未验证]）：
- <command/test>: <pass/fail>
- 浏览器：<状态/未验证>

Rollout/Rollback：...
剩余风险：...
```

## 输出：Codex 可执行整改计划

计划必须让另一个 agent 不需要重新做架构决策：

```text
# 目标
...

# 非目标
...

# 目标 ref 与事实源
...

# 必须保持的不变量
...

# 改动步骤
1. <file/path>
   - 做什么
   - 为什么
   - 不要做什么
   - 对 API/schema/permission 的影响

# 测试
- focused regression
- permission/security
- concurrency/race
- frontend state

# 验证命令
<从当前 Makefile/package/CI 读取>

# 手工验收
<UI/身份/异步/生产相关路径>

# Rollout / Rollback
...

# Definition of Done
...
```

禁止使用 `TODO`、`TBD`、“类似前面”或“后续再决定”等占位语。
