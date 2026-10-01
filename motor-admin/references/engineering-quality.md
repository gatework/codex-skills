# 工程质量、兼容性与重构安全

处理命名重构、代码规范、跨层兼容、依赖/抽象评审、批量清理和长期可维护性时读取本文件。具体的命名与语言层规范见 [code-conventions.md](code-conventions.md)，抽象取舍的通用思考方式见 [engineering-mindset.md](engineering-mindset.md#抽象是否赚回成本)。

## 目录

- [先识别变更表面](#先识别变更表面)
- [命名与职责](#命名与职责)
- [兼容性优先于漂亮重构](#兼容性优先于漂亮重构)
- [错误与失败语义](#错误与失败语义)
- [抽象与依赖](#抽象与依赖)
- [删除与清理](#删除与清理)
- [模式完整性审查](#模式完整性审查)
- [文档与代码注释](#文档与代码注释)

## 先识别变更表面

重命名、移动、拆 service、调整 API 或“整理代码”前，先区分三类表面：

1. **内部实现**：只被同一进程当前代码引用，可在一个原子改动中同步修改；
2. **持久兼容表面**：数据库列/数据、permission key、job class 名、queue、cache key、event type、加密 purpose；
3. **外部契约表面**：HTTP route、JSON 字段/error code、env/config、GitHub release/image tag、前端路由/深链、第三方 webhook payload。

任何 rename/refactor 都先做影响面清单：

`route/action -> permission catalog -> persisted permission/token scope -> controller/service -> DB/schema/data -> serializer/API -> frontend type/caller -> queued job -> docs/release`

如果某一层会在部署后继续存活，不得按“全仓 grep 已改完”推断兼容完成。

## 命名与职责

优先按真实领域职责命名，而不是按实现细节或 UI 文案命名：

- 资源名称反映持久/业务实体，不跟随当前菜单标题；
- 有副作用的方法使用动作语义，查询/判定不要伪装成命令；
- `*_at` 仅用于真实时间点，counter/step/version 不伪装成 timestamp；
- 避免 `Manager`、`Helper`、`Utils`、过宽 `Context` 变成无主职责容器；
- 精确长名优于丢失信息的缩写；
- 同一概念只保留一套词汇，避免 `permission/scope/access` 在不同层表达同一事实。

不要为“更短”牺牲领域信息，也不要为了统一命名顺手改稳定公共契约。

## 兼容性优先于漂亮重构

按兼容窗口决定方案：

- DB destructive rename/drop：优先 expand -> dual-compatible -> migrate/backfill -> verify -> contract；
- route/JSON 字段：若存在外部调用者，先兼容读/写或版本化，再移除旧入口；
- permission key：controller/action rename 前核对 catalog、role permission 和 API token scope 的持久数据映射；
- Active Job/Sidekiq class rename：考虑队列中已序列化的旧 class 名；需要时只为 job 提供短期兼容常量，并明确移除条件；
- env/config rename：先定义 precedence 和过渡期，禁止两个长期同义配置无期限并存；
- cache/Redis key rename：先判断是否可重建，durable/security-sensitive state 不能靠 flush 迁移。

兼容 alias 必须有明确用途、监控/验证方式和退出条件；不要用永久 alias 掩盖迁移未完成。

## 错误与失败语义

- Rails expected business failure 使用稳定 code/status，不用 broad rescue 把 unknown failure 伪装成 422/200；
- 不使用 `rescue nil`、空 catch、吞异常后继续成功状态；
- Sidekiq expected failure 与 transient infra failure 分开，后者保留 retry 语义；
- 前端只捕获能恢复或能转换为用户状态的错误，不能 catch 后留下旧 loading/数据；
- 日志中的异常摘要先脱敏和截断，原始 credential/provider secret 不持久化。

错误处理的目标是保留正确失败方向，而不是减少报错数量。

## 抽象与依赖

新增抽象先判断职责收益；引入依赖再额外评估升级与运行成本。不要把以下判断当作全部必须满足的门槛：

- 多个调用方有真实共同语义，或一个明确独立生命周期；
- 能减少重复带来的 contract drift、状态耦合或理解成本；
- 新层减少状态来源，而不是只增加 forwarding wrapper；
- 类型、失败边界和测试入口更清晰；
- 可渐进迁移且回滚不破坏数据；
- 现有原语无法直接清楚表达时才增加公共层；封装复杂业务可以组合原语，不必证明原语完全无能。

新依赖必须说明 owner、升级面、security surface、bundle/runtime 成本和移除路径。不要为了一个 helper 引入新的状态库、HTTP client、UI library 或后台框架。

## 删除与清理

删除代码前搜索：

- direct caller/import；
- route/menu/permission key；
- serializer/API type；
- cron/schedule/job class；
- migration/data/backfill；
- i18n key；
- docs/example/env；
- release/deploy script。

“当前代码零引用”不足以证明 queued job、旧 DB data、外部调用者和 deploy automation 不再依赖它。

## 模式完整性审查

修复一个类别问题后提取 pattern signature，再扫 sibling：

- 同类 authorization omission；
- stale request commit；
- `read -> check -> write` race；
- secret logging；
- duplicated hardcoded theme/layout；
- unsafe destructive migration；
- job retry/idempotency gap。

同风险 sibling 未处理时不能把单点修复宣称为“这一类问题已解决”。

## 文档与代码注释

- 注释解释不明显的不变量、兼容窗口和失败方向，不复述代码；
- TODO 必须有 owner/issue/退出条件，否则优先解决或删除；
- docs 保存长期契约，review score、当前 SHA、测试数量和一次性 finding 留在 issue/PR/report；
- 修改 public/durable contract 时同一交付更新对应 docs、tests 和 rollout 说明。
