# 编码规范

编写或审查 Ruby/Rails、TypeScript/Vue、Less、SQL/migration、测试代码，或被问到“这个项目的写法/命名/风格应该怎样”时读取本文件。

## 目录

- [规范的优先级与边界](#规范的优先级与边界)
- [通用规范](#通用规范)
- [Ruby 与 Rails](#ruby-与-rails)
- [Migration 与 SQL](#migration-与-sql)
- [TypeScript 与 Vue](#typescript-与-vue)
- [Less 与样式](#less-与样式)
- [API 与 i18n](#api-与-i18n)
- [测试代码](#测试代码)
- [提交与 PR](#提交与-pr)
- [自查清单](#自查清单)

## 规范的优先级与边界

判断格式与工具支持时按以下来源核对；业务正确性、用户要求和公开契约不被格式配置覆盖：

1. 目标 ref 的工具配置：RuboCop、ESLint、Prettier、Stylelint、`tsconfig`、EditorConfig；
2. 项目 `docs/CODE_STYLE.md`、`docs/BACKEND_GUIDE.md`、`docs/FRONTEND_GUIDE.md`；
3. 同目录、同职责的既有代码；
4. 本文件。

工具允许某种写法不代表项目推荐它。例如 ESLint 未禁止 `any`，不能作为绕过类型建模的理由。源码中的旧写法也可能是待修缺陷，先核对调用契约。

本文件重点说明**工具不足以判定的部分**（命名、职责、失败语义、可读性、安全与兼容习惯），格式与语法细节交给格式化工具。凡涉及语言/框架版本的特性（如 Rails 8 的 `params.expect`、Vue 3.5 的 props 解构、`defineModel`），先读 `Gemfile.lock` / `pnpm-lock.yaml` 确认版本再用，不假设。

既有代码与本文件冲突时，不为“统一”而顺手改动大片已正确的代码；新代码遵循规范，旧代码在触及时按最小范围改进。

## 通用规范

**命名**

- 按领域职责命名，不按实现细节或菜单文案命名；同一概念全项目只用一套词汇（不要让 permission / scope / access 指同一件事）。
- 名称表达意图：查询/判定不伪装成命令，命令带动作语义；布尔值用 `can_` / `has_` / `is_`（Ruby 谓词方法用 `?`）。
- 单位与类型进名称：`timeout_seconds`、`retention_days`；`*_at` 只用于真实时间点，计数、步骤、版本不叫 `_at`。
- 精确长名优于丢失信息的缩写；避免 `Manager`、`Helper`、`Utils`、过宽的 `Context` 成为无主职责容器。

**函数与结构**

- 一个函数一个抽象层级；用 guard clause / early return 展平嵌套。
- 多个参数难以辨认或存在布尔开关时，考虑关键字参数/对象参数；保留公开调用契约，不按参数数量机械重构。
- 魔法数字命名为常量并说明来源；时间、容量、限流阈值放在有归属的地方，不散落在调用点。
- 只有真实调用方才建 helper；一次性逻辑留在使用处。

**注释**

- 解释“为什么”：不明显的不变量、兼容窗口、失败方向、被否决的方案；不复述代码。
- TODO 必须带 owner、issue 或退出条件，否则解决或删除。

**错误**

- 不 `rescue nil`、不空 `catch`、不吞异常后返回成功。
- 只捕获能恢复或能转换成明确状态的错误；捕获后保留原因（脱敏、截断）。
- 预期业务错误用稳定 `code`；未知错误保持未知，进入统一异常通知。

## Ruby 与 Rails

**Controller 与分层**

- Controller 只做 HTTP 编排：参数、认证授权入口、资源定位、调用流程、选 serializer、状态码。
- 授权沿用既有 access context 入口，不在 controller 里重新推导角色或权限。
- 成功响应保持 `{ data, meta }`；业务错误用 `code + message`。
- 分层职责与提取门槛见 [backend-domain.md](backend-domain.md)，不因行数机械拆 service。

**Active Record**

- 必需资源按 404 契约使用 `find` / `find_by!`，可选资源允许 `find_by`；只判断存在可用 `exists?`，只取 ID 可用 `pluck(:id)` / `ids`。已有加载集合要比较额外 SQL 成本，不机械替换。
- 大批量遍历考虑 `find_each` / `in_batches`，先核对排序、游标和并发写语义；serializer 需要的关联在 query 层 `includes` / `preload`。
- 排序必须稳定：`order(created_at: :desc, id: :desc)`；客户端排序字段走 allowlist。
- `update_all`、`delete_all`、`insert_all`、`upsert_all` 绕过 validation 和 callback，且 `update_all` 不更新 `updated_at`；只在语义确需时使用，并显式处理 `updated_at`，以及“受影响行数”这个返回值。
- 避免 `default_scope`（隐式改变所有查询）；避免在 `after_save` 等回调里做跨系统 I/O。
- 应用业务时间使用 `Time.current`；timeout/持续时间按需要使用单调时钟。SQL 值使用绑定参数，动态列名和方向用 allowlist，不字符串拼接用户输入。
- `enum` 值有明确允许集合和校验；简单状态转换可用条件 UPDATE，需要 validation/callback/审计时可用锁内领域操作，不能在无保护的先读后判中更新。
- `with_lock` 自带事务并重新加载，`lock!` 需要调用者维持事务；先处理脏对象。内部块结束未必是最外层提交，移出网络 I/O 时核对完整调用链。

**错误与文案**

- 用户可见文案走 Rails i18n，不在代码里硬编码中文或英文句子；`code` 不翻译。
- 自定义异常携带稳定 `code`；`rescue` 具体类，不 `rescue => e` 之后继续当成功。

**Job**

- 参数保持最小且可序列化，通常传 ID 后重读权威状态，必要的执行快照沿用加密边界；检查重复执行与远端幂等，不把“至少一次”理解成队列绝不丢失。
- 区分预期失败（写成状态）与临时失败（抛出让队列重试）；日志与错误摘要先脱敏再截断。

## Migration 与 SQL

- 已在共享环境执行过的 migration 不修改，新增修正 migration；迁移后核对 `db/schema.rb`。
- 危险变更按 expand → backfill → contract：先加兼容列/表/索引，分批回填，验证后再加 NOT NULL/CHECK 或删除旧结构。
- 大表在线创建索引使用 `algorithm: :concurrently`，同时 `disable_ddl_transaction!`（其限制与失败状态见 [performance-capacity.md](performance-capacity.md)）。
- 外键与 CHECK 约束在大表上可先 `validate: false` 添加，再单独 `validate_*`，缩短锁时间；具体能力以当前 Rails/PostgreSQL 版本文档为准。
- 关键不变量双层保护：model validation（用户可读错误）+ NOT NULL / UNIQUE / CHECK / FK / index（并发下的最后防线）。
- 命名沿用 `schema.rb` 现有风格（表、列、外键、索引），不引入第二套约定；如果项目使用 strong_migrations 之类的门禁，遵从而不是绕过。

## TypeScript 与 Vue

**TypeScript**

- 新增代码不要用 `any` 逃避建模；未知输入用 `unknown` 后收窄，必要的第三方互操作断言限制在可信边界。类型声明不验证远端 JSON；避免无依据的 `as` 与非空断言。
- 互斥且复杂的状态可用判别联合（`{ status: 'loading' } | { status: 'error'; error: ApiError }`），并按需要用 `never` 检查遗漏；并行请求/行操作的独立标志不必强行合并。
- 常量集合优先字符串字面量联合或 `as const` 对象；`satisfies` 用于既要校验形状又要保留字面量类型的场景。
- 类型导入用 `import type`；API 请求/响应类型放 `src/api/`，页面不重复定义同一后端字段。
- 时间、金额等语义值在 API 层统一处理，页面不各自 `new Date(...)` 解析。

**Vue（`<script setup lang="ts">`）**

- 组件名多词 PascalCase；composable 以 `use` 开头，返回值形状稳定，清理逻辑放在 `onScopeDispose` / `onUnmounted`。
- props/emits 使用类型声明；不直接修改 props；双向绑定沿用 `v-model` / `v-model:xxx` 语义（`defineModel` 视 Vue 版本采用）。
- `computed` 只做纯推导，无副作用；`watch` 只用于副作用，并考虑清理与旧请求；能用事件处理器表达的“用户动作 → 状态变化”，不用 watcher 间接触发。
- 需要多个 watcher 同步同一状态时，先检查是否可以把状态改为单一来源加推导。
- 普通 `reactive` 的 primitive 属性解构会失去跟踪，可用 getter / `toRefs`；Vue 3.5 props 解构另有编译语义。明确按整体替换的结构可用 `shallowRef`，嵌套可编辑表单通常需要深响应式，不能仅凭对象大小选择。
- 模板保持简单：复杂表达式提取为 `computed`；`v-for` 使用稳定业务 ID 作 `key`（不用会变化列表的 index）；不在同一元素同时使用 `v-if` 与 `v-for`。
- 异步回调在提交状态前检查“是否仍是最新请求 / 当前记录”（参见 [code-patterns.md](code-patterns.md)）。
- 用户可见文案走 i18n，不拼接句子；icon-only 控件有 `aria-label`。

**目录与职责**

- 请求与类型放 `src/api/`，路由页放 `views/`，可复用 UI 放 `components/`，可复用 composable 放 `hooks/`，跨路由共享状态才进 `store/modules/`，纯函数放 `utils/`（详见 [project-contract.md](project-contract.md)）。
- 状态从局部 → composable → Pinia 逐级提升，能推导的值不另存。

## Less 与样式

- 使用 scoped Less 与 `--motor-*` Token；页面只定义局部布局，不重新定义主题变量。
- 不写 `transition: all`；显式列出 `color`、`background-color`、`border-color`、`opacity`、`transform`。
- 覆盖 Arco 内部样式用最小范围的 `:deep()`，并在旁边注明原因；避免 `!important`，确需时写明理由。
- 不在页面里写死主色、圆角、字体、阴影；不建立平行的间距或字号刻度。
- `z-index` 使用已有层级约定；不发明“更大的数”解决层叠问题。
- 布局、滚动、响应式与状态区的具体配方见 [layout-and-style-system.md](layout-and-style-system.md)。

## API 与 i18n

- 沿用现有 `page` / `per_page`、`{ data, meta }`、`code + message` 约定；字段风格与现有 JSON 保持一致，格式转换集中在 `src/api/`，页面不散拼。
- 修改字段时同步：strong params、serializer、前端 API 类型、表单/表格、测试、文档。
- `zh-CN` 与 `en-US` 的 locale key 保持一一对应；数字、日期用 locale-aware 格式化；协议值、URL、IP、序列号按原值显示。
- 中英文之间、中文与数字之间留空格，中文全角标点旁不额外加空格；完整英文句子使用英文标点。

## 测试代码

- `describe` 写被测对象，`context` 写条件（“当…时”），`it` 写可观察行为的完整句子。
- 断言可观察行为，不断言“某私有方法被调用”；每个用例只证明一件事，`let` 只保留必要的数据。
- 数据用工厂和 trait 表达业务语义，不在用例里手写十几个字段。
- 并发与竞态使用显式阶段信号 / deferred Promise；不靠 sleep 猜顺序，不依赖 barrier 超时继续成功路径。有限轮询可观察数据库状态时，超时应失败；旧实现的对照在隔离副本验证。
- 时间相关逻辑注入或冻结时间，不依赖真实时钟。

## 提交与 PR

- 一次提交表达一个可解释的变更；提交信息说明“为什么”，格式遵循 `docs/DEVELOPMENT_STANDARDS.md` 与仓库历史，不自创。
- PR 说明保留的契约、DB/API/permission/config 变化、验证证据（命令与结果）、未验证项、rollout/rollback。
- 不把无关重构混进功能变更；提交前重新读取 HEAD 与工作树状态。

## 自查清单

交付前快速过一遍：

- 命名是否表达领域意图，同一概念是否只有一个词？
- 有没有函数同时做“决策”和“副作用”，可以分开吗？
- 每个 `rescue` / `catch` 之后，系统处于什么状态，是否伪装成成功？
- 有没有把展示文案当成程序分支或契约标识？
- 有没有绕过既有封装（access context、`UserSettings`、`PageContainer`、`src/api/`）？
- 注释是在解释“为什么”，还是在复述代码？
- 新增的抽象/配置/依赖，是否通过了 [engineering-mindset.md](engineering-mindset.md#抽象是否赚回成本) 的四个检验？
- 测试是否会在旧实现上失败？
