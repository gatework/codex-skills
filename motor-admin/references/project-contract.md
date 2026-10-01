# 项目契约与仓库地图

在首次进入仓库、跨层修改、代码审查或发现文档与实现不一致时读取本文件。

## 目录

- [事实优先级](#事实优先级)
- [文档职责](#文档职责)
- [后端责任地图](#后端责任地图)
- [前端责任地图](#前端责任地图)
- [跨层依赖矩阵](#跨层依赖矩阵)
- [文档与代码冲突](#文档与代码冲突)
- [审查快照规则](#审查快照规则)
- [兼容性表面清单](#兼容性表面清单)

## 事实优先级

按以下顺序判断当前项目事实：

1. 目标 ref 的当前源码；
2. `backend/db/schema.rb` 与相关 migration；
3. `backend/Gemfile.lock`、`frontend/pnpm-lock.yaml`、`frontend/package.json`、Dockerfile；
4. 目标行为对应的测试和当前 `.github/workflows/*`；
5. `docs/*.md` 中可长期维护的工程契约；
6. README、阶段性 review/progress 文档和历史说明。

版本号、测试数量、当前提交 SHA、一次性审查评分都属于运行时事实，不写成 skill 的永久规则。

## 文档职责

优先阅读与当前任务直接相关的文档，不需要每次全部加载：

| 文档 | 主要用途 |
| --- | --- |
| `docs/DEVELOPMENT_STANDARDS.md` | 工程总原则、事实源、Definition of Done、统一门禁 |
| `docs/CODE_STYLE.md` | 日常 Ruby/Vue 编码约束和本地验证入口 |
| `docs/BACKEND_GUIDE.md` | Rails 分层、身份权限、数据库、异步、Cable、安全、运维后台 |
| `docs/FRONTEND_GUIDE.md` | Vue/TS/Arco 页面、状态、权限、主题、i18n、响应式和测试 |
| `docs/API_CONVENTIONS.md` | JSON envelope、错误、状态码、分页、权限与幂等契约 |
| `docs/NOTIFICATIONS.md` | 通知、渠道、投递、事件与重试语义 |
| `docs/DEPLOYMENT_GUIDE.md` | 生产配置、服务依赖、迁移、备份与运行边界 |
| `docs/REVIEW_PROGRESS.md` | 某一时点的审查台账，只作线索，不作永恒真相 |

`scripts/probe-project.sh` 会报告上述文档是否存在；文档清单以脚本输出为准，缺失的文档不要凭记忆补全其内容。

## 后端责任地图

按职责查找代码，不按文件名猜实现：

- `backend/app/controllers/motor/`：HTTP 参数、身份/授权入口、资源定位、状态码、响应编排。
- `backend/app/models/`：持久化约束、关联、领域不变量、小型领域操作。
- `backend/app/services/`：跨模型事务、外部集成、复杂业务流程。
- `backend/app/serializers/`：稳定 API 输出结构。
- `backend/app/jobs/`：异步入口、重试、claim、投递状态。
- `backend/app/channels/`：Action Cable 认证和订阅隔离。
- `backend/app/mailers/`：邮件投递。
- `backend/config/`：路由、Sidekiq、Cable、环境和中间件配置。
- `backend/db/`：migration、schema 和数据库级约束。
- `backend/spec/`：行为证据和回归保护。

## 前端责任地图

- `frontend/src/api/`：HTTP 请求和请求/响应类型，不保存页面状态。
- `frontend/src/views/`：路由页和业务编排。
- `frontend/src/components/`：可复用 UI/交互单元。
- `frontend/src/hooks/`：可复用 composable、分页、请求状态、权限等。
- `frontend/src/store/modules/`：跨路由或会话级共享状态。
- `frontend/src/router/`：路由、菜单投影、守卫和 meta。
- `frontend/src/locale/`：用户可见语言资源。
- `frontend/src/assets/style/`：全局设计 token 和主题。
- `frontend/src/utils/`：与 Vue 生命周期无关的纯函数。

## 跨层依赖矩阵

修改下面任一项时，至少检查对应同一行的其他层：

| 变更 | 后端 | 数据库 | 前端 | 测试/文档 |
| --- | --- | --- | --- | --- |
| 新管理资源 | route/controller/serializer/permission | 表、约束、索引 | api/type/page/menu | request + UI + docs |
| 字段变更 | strong params/serializer | migration/schema | API type/form/table | request/type/build |
| 权限变更 | Permission/AuthContext | 角色关系 | router/menu/button | 越权与收敛测试 |
| 身份变更 | session/token/revocation | durable session state | store/router/tabs/subscription | JWT/API token 边界 |
| 异步投递 | service/job/provider | 当前 schema 中的派发意图或执行结果 | 状态反馈 | retry/idempotency |
| 用户偏好 | account API | encrypted settings | store/layout/token | 默认值/迁移/i18n |

## 文档与代码冲突

发现冲突时不要直接选一边：

1. 查目标行为相关测试、schema、lockfile 和最近实现；
2. 判断代码是否是经过验证的新设计；
3. 若代码无意偏离长期契约，修代码；
4. 若架构确实已演进，在同一变更中更新文档和验证命令；
5. 若暂不能收敛，明确记录风险和退出条件，不制造“文档已一致”的假象。

## 审查快照规则

`REVIEW_PROGRESS.md`、评分、问题清单等属于证据快照：

- 可作为定位热点和回归风险的索引；
- 必须回读当前源码才能复用结论；
- 不把已修问题继续当成当前 bug；
- 不把一次性问题照搬进长期 skill；
- 可提炼其中反复出现的失败模式为稳定规则。

## 兼容性表面清单

重构、rename、删除或拆模块时，除源码引用外还要检查部署后可能继续存在的表面：

| 表面 | 典型风险 |
| --- | --- |
| route/action | 前端/外部 caller 仍请求旧路径；permission key 随 controller/action 改名 |
| API JSON/error code | 前端 type、表单、自动化脚本仍消费旧字段/错误语义 |
| DB schema/data | 旧 web/worker、backfill、历史数据仍依赖旧列/值 |
| permission/token scope | persisted role permission/API token scope 变成 orphan key 或意外扩权 |
| Active Job/Sidekiq class | 队列中已序列化旧 class 名，deploy 后反序列化失败 |
| queue/schedule | scheduler 或运维监控继续监听旧 queue/job 名 |
| env/config | 部署平台仍注入旧变量；两个同义配置 precedence 不清 |
| event/cache/Redis key | durable/security-sensitive state 迁移遗漏，或旧 producer/new consumer 不兼容 |
| frontend route/i18n | bookmark/deep-link、menu、locale key 与 backend contract 漂移 |
| release/deploy artifact | build/test/publish 使用了不同 ref、不同 target 或不同 digest |

先判断哪些是纯内部符号，哪些需要兼容窗口。对需要兼容的表面写清迁移、双读/双写/alias、验证和移除条件，不把“一次全仓替换成功”当成兼容性证明。
