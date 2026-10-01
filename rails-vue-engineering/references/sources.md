# 来源与版本边界

遇到机制不确定时查这里，不需要每个任务重新阅读全部文档。链接是官方事实入口，不是升级到最新版本的指令。项目锁定版本与已安装源码优先用于解释该项目的实际机制。

| 决策 | 官方入口 | 核对点 |
| --- | --- | --- |
| Ruby 假值筛选 | [Enumerable](https://docs.ruby-lang.org/en/master/Enumerable.html#method-i-filter_map) | `filter_map` 与 `compact` 的假值差异；最低版本。 |
| 值对象 | [Data](https://docs.ruby-lang.org/en/master/Data.html) | 容器不可变不等于成员深不可变。 |
| 参数解析 | [Action Controller](https://guides.rubyonrails.org/action_controller_overview.html#strong-parameters) | `expect` 支持版本、输入形状、允许属性与授权的区别。 |
| 行锁 | [Rails 8.1 Pessimistic Locking](https://api.rubyonrails.org/v8.1/classes/ActiveRecord/Locking/Pessimistic.html) | `with_lock` 自带事务、重载与脏对象限制。 |
| 提交回调 | [Active Record Callbacks](https://guides.rubyonrails.org/active_record_callbacks.html#active-record-after-all-transactions-commit) | 外层事务、回滚、callback 与 I/O 失败。 |
| 入队与拒绝 | [Active Job Basics](https://guides.rubyonrails.org/active_job_basics.html) | adapter、after-commit 配置、`EnqueueError` 与 `false`。 |
| 查询与批处理 | [Query Interface](https://guides.rubyonrails.org/active_record_querying.html) | 排序、分页、批次、锁与预加载。 |
| 重试与幂等 | [Sidekiq Best Practices](https://github.com/sidekiq/sidekiq/wiki/Best-Practices) | JSON 参数、重复执行；额外核对部署的可靠性选项。 |
| 约束与锁范围 | [PostgreSQL Explicit Locking](https://www.postgresql.org/docs/current/explicit-locking.html) | 行锁、事务与会话 advisory lock 的生命周期。 |
| 深浅响应式 | [Vue Advanced Reactivity](https://vuejs.org/api/reactivity-advanced.html) | `shallowRef`、内部对象、scope cleanup。 |
| watcher | [Vue Watchers](https://vuejs.org/guide/essentials/watchers.html) | cleanup 注册时机、异步请求与旧结果。 |
| SFC 宏 | [Vue Script Setup](https://vuejs.org/api/sfc-script-setup.html) | Vue 3.5 props 解构、defineModel 默认值和父子同步。 |
| 类型收窄 | [TypeScript Narrowing](https://www.typescriptlang.org/docs/handbook/2/narrowing.html) | truthiness、判别联合、exhaustiveness；不提供运行时 JSON 验证。 |

本包的 Rails 示例要求支持其所用 API；`Data` 教学例要求 Ruby 3.2+。具体执行版本应记录在验收结果里，不能把一次通过推广为版本矩阵。

Motor 提供了提炼方法的案例，但本包没有 Motor 路径、权限键、响应 envelope、UI 库或数据库品牌的强制依赖。官方机制、工程建议、项目选择和一次性审读结论分别保存，不互相冒充。
