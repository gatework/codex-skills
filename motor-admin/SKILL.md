---
name: motor-admin
description: 维护、扩展和审查 gatework/motor 的 Rails API 与 Vue/Arco 管理端。用于 Motor 的业务流程、身份权限、网络运维、界面、并发异步、兼容重构、测试与交付；以当前源码和项目契约为依据，不用于其他项目的通用 Rails/Vue 规范查询。
---

# Motor Admin 项目维护

把 Motor 当成已有业务与工程契约的产品。目标是最小而完整的正确变更：理解用户任务，保留身份、审计、数据与前端交互语义，以实际证据交付。

## 建立当前事实

确认目标仓库、ref 和工作树；可运行只读 `scripts/probe-project.sh <repo-root>` 获取索引，再读相关源码与测试。工具不可用时直接读文件，不默认要求某个 connector。

源码说明当前行为，需求和长期契约说明预期行为，测试说明已验证行为。发生冲突时追查原因，不以“代码现在如此”否定缺陷。版本、SHA、测试数量和审查发现属于快照，不是永久规范。

修改前读取 HEAD 与 `git status --short --branch -uall`，保留已有 modified/staged/untracked 工作。遵循会话中已有授权；不要重置、清理、stash 或覆盖未知改动。需要隔离验证时使用临时环境，提交或发布前重检基线；漂移只重核相关结论，不擅自覆盖。

## 按任务加载

只读当前任务需要的参考。小改动不启动全仓审计。

| 任务 | 参考 |
| --- | --- |
| 首次进入、跨层变更、契约冲突 | [项目地图](references/project-contract.md) |
| 设计、职责命名、抽象取舍 | [工程判断](references/engineering-mindset.md)、[Rails 约定](references/rails-doctrine.md) |
| 新业务动作与状态流 | [业务建模](references/business-modeling.md)、[领域流程](references/business-workflows.md) |
| Rails API、模型、查询、migration | [后端与数据库](references/backend-domain.md) |
| 登录、会话、API Token、MFA、代入 | [身份安全](references/auth-security.md)、[领域流程](references/business-workflows.md) |
| job、通知、外部同步、Cable | [异步与恢复](references/async-realtime-observability.md) |
| Vue 请求、表单、生命周期 | [前端交互](references/frontend-interaction.md) |
| 页面骨架、表格、Drawer、响应式 | [UI 模式](references/frontend-ui-patterns.md)、[布局样式](references/layout-and-style-system.md) |
| 视觉设计与打磨 | [Arco 原则](references/arco-design-foundations.md)、[体验细节](references/frontend-experience.md) |
| 编码、语法、重构、清理 | [编码规范](references/code-conventions.md)、[兼容与质量](references/engineering-quality.md) |
| 实现范式与项目调用形状核对 | [实现与反例](references/code-patterns.md) |
| 性能、容量 | [性能证据](references/performance-capacity.md) |
| 测试、审查、交付说明 | [验证矩阵](references/testing-delivery.md)、[工作流与输出](references/workflows-and-output.md) |
| Docker、CI、依赖升级、发布 | [发布工程](references/release-engineering.md)、当前项目部署文档与脚本 |

## 不能丢失的项目语义

- 后端决定凭证有效性、权限和资源范围；前端菜单/按钮是体验投影。沿当前 access context 分辨 credential、actor、subject、active role 与代入，不另造权限模型。
- API Token 有独立凭证边界，有效权限不能超过 token scope 与绑定角色当前权限的交集。代入保留真实 actor，遵循只读约束。
- 密码、禁用与权限等安全变化沿当前策略撤销凭证并收敛前端身份；审计标识与展示文案分开。
- `users.settings` 是偏好和通知渠道的加密聚合，复用 `Motor::UserSettings` 的锁、合并、容量与公开输出边界，不能整列覆盖其他职责的数据。
- 通知事件、派发意图、队列接受和渠道投递成功是不同事实。先查当前 schema、publisher 与 job，不假定存在独立 delivery 表或投递回执。
- 自动禁用和审计日志保留按项目要求保持通知证据、宽限期与到期重检；不把这项政策推广到所有删除动作。
- 外部资产快照失败不能成为空数据清理；远端配置执行未知不能伪装为未执行。检查完整性、执行归属、重试与恢复。
- HTTP 沿用项目 API 和错误契约；前端复用 `src/api/`、现有 shell/token、权限入口与 request composable。草稿、查询、服务端事实分别管理，旧响应不能覆盖新身份或新编辑会话。
- RailsAdmin/Sidekiq Web 不绕过领域、安全和审计；日志和错误在落地前脱敏。

## 选择最小方案

先使用框架原语，再复用项目已有职责，最后补缺失能力。独立生命周期可支持一次性 service/composable；共享抽象需要真实共同语义，不为“现代化”重写正确代码或另建 HTTP client、状态框架、主题系统。

新配置、公共层或依赖应说明真实场景、维护归属及迁移成本。重命名、移动和删除前区分内部符号、持久标识与外部契约，追查旧数据、任务、浏览器及外部消费者。

跨层任务沿实际链路检查：入口与授权 → 领域操作 → 持久化/异步 → API 输出 → 前端状态 → 用户结果。涉及锁、I/O、恢复或竞态时，明确失败后的状态与谁有权写结果。

## 验证与交付

先做能证明受影响行为的 focused check，再完成项目适用门禁；命令从当前 Makefile、package scripts 和 CI 获取。UI 需要浏览器证据，数据库并发需要实际数据库，发布需要已验证制品；不能以 typecheck、mock 或 HTTP 200 代替。

审查先给可靠 findings：位置、触发、坏结果、现有保护为何不足、最小修复与回归证据。优先级取决于影响、触发范围与可恢复性，不按关键词机械打分；风格建议与缺陷分开。没有可靠问题时说明审读范围。

交付说明改变了什么、为什么、运行过什么及未验证项。发现项目缺陷但任务仅授权修改 skill 时，记录证据，不顺手修业务代码。生产就绪与远端发布必须有相应运行证据，不能沿用历史结论。
