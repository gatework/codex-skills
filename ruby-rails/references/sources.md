# 来源、版本与技能验证

## 证据如何使用

这份技能从既有 `ruby` 技能提炼而来。本轮按实际 Ruby/Rails 行为修正示例，不把历史验收作为当前版本的证明。语言/API 行为、框架设计取向与本地业务经验是不同层次的证据：官方文档说明机制，源码和目标版本测试确认具体行为；抽象、分层和路由选择仍需项目判断。

下表为 2026-09-29–30 本轮核验的主要依据。在线滚动文档可能更新，落地时以项目锁文件与对应版本源码为准。

| 决策/事实 | 来源与适用边界 | 本技能验证 |
| --- | --- | --- |
| bang 方法返回值并不统一 | [Ruby 4.0 Array](https://docs.ruby-lang.org/en/4.0/Array.html#method-i-sort-21) | `sort!` / `compact!` / `uniq!` 实测 |
| Data 成员不会递归冻结；值语义与比较协议不同 | [Ruby 4.0 Data](https://docs.ruby-lang.org/en/4.0/Data.html) | 金额类型、成员所有权、Hash/Set、比较测试 |
| 位置参数、关键字、块是独立转发契约 | [Ruby 方法调用](https://docs.ruby-lang.org/en/4.0/syntax/calling_methods_rdoc.html) | 直接父类调用与代理转发测试 |
| 整数类型转换不等于严格输入校验 | [ActiveModel Integer](https://api.rubyonrails.org/classes/ActiveModel/Type/Integer.html) | Rails 8.1.3.1 原始示例复现；严格解析负向测试 |
| 外层事务、savepoint、提交后回调 | [事务 API](https://api.rubyonrails.org/classes/ActiveRecord/Transactions/ClassMethods.html)、[Rails 7.2 发布说明](https://guides.rubyonrails.org/v7.2/7_2_release_notes.html) | 7.2 引入事务对象回调；8.1.3.1 + PostgreSQL 实测提交/回滚 |
| 入队、执行、效果与数据库事务分别成立 | [Active Job](https://guides.rubyonrails.org/active_job_basics.html#transactional-integrity-on-jobs) | 8.1.3.1 test adapter、拒绝/异常适配器；未验证生产后端 |
| 标准库分发方式有版本边界 | [Ruby 3.4 发布说明](https://www.ruby-lang.org/en/news/2024/12/25/ruby-3-4-0-released/)、[Ruby 4.0 发布说明](https://www.ruby-lang.org/en/news/2025/12/25/ruby-4-0-0-released/) | 核对 default/bundled 变化，不把本地安装情况当版本事实 |
| JSON 3 与本轮 Rails 版本存在调用不兼容 | 本机 ActiveSupport 8.1.3.1 `json/decoding.rb` 调用 `JSON.parse(json, options)`；JSON 3.0.2 `json/common.rb` 接受关键字 | 首轮 JSONB 用例复现 `ArgumentError`；测试环境限定 JSON 2，不修改框架 |

Ruby/Rails **维护状态与 API 是否可用分开判断**。支持期限只从 [Ruby 维护分支](https://www.ruby-lang.org/en/downloads/branches/) 和 [Rails 维护政策](https://rubyonrails.org/maintenance) 查询，不在多份参考里复制“当前版本”结论。发现 EOL 时说明风险，升级另立任务，不擅自提高用户项目最低版本。

## 补充参考与取舍

- 框架机制：[Rails Guides](https://guides.rubyonrails.org/)、[Rails Security](https://guides.rubyonrails.org/security.html)、[Rails Doctrine](https://rubyonrails.org/doctrine)。Doctrine 表达取向，不证明某种目录或类形状是唯一正确答案。
- 工具与打包：[RubyGems Guides](https://guides.rubygems.org/)、[Bundler](https://bundler.io/docs.html)、[RuboCop](https://docs.rubocop.org/rubocop/)。使用项目锁定版本的配置语法。
- 风格背景：[Ruby Style Guide](https://github.com/rubocop/ruby-style-guide)、[Rails Style Guide](https://github.com/rubocop/rails-style-guide)、[RSpec Style Guide](https://github.com/rubocop/rspec-style-guide)。引号、行宽、类方法形状不覆盖项目约定；历史 API 不机械继承。
- 《Programming Ruby》《Metaprogramming Ruby》仅作为原技能的概念背景，本轮没有逐章核对原书，不声称原书研读、页码或原文证据。
- 本地业务经验仅保留可解释不变量，不引入私有源码，不将订单/网络同步等单一领域的策略推广为所有项目要求。

## 可重复验证

在 `ruby-rails` 目录执行。结构检查只需 Ruby 标准库；行为测试使用独立 [Gemfile](../scripts/Gemfile) 与 [锁文件](../scripts/Gemfile.lock)，不会改变全局 gems 的默认激活版本。安装依赖时优先使用已有环境或专用 Bundler 路径，不修改其他项目锁文件。当前锁文件针对 arm64 macOS；其他平台需显式解析自己的平台依赖后再验证，不能声称此锁文件已证明跨平台兼容。

```bash
ruby scripts/check_skill.rb
BUNDLE_GEMFILE=scripts/Gemfile bundle check
BUNDLE_GEMFILE=scripts/Gemfile bundle exec ruby scripts/contracts_test.rb
BUNDLE_GEMFILE=scripts/Gemfile PG_BIN=/path/to/postgresql/bin bundle exec ruby scripts/run_postgres.rb
```

- [结构检查](../scripts/check_skill.rb)：frontmatter、内部文件链接、资源引用、代码围栏及脚本语法；不靠匹配固定中文措辞判断质量，也不证明外链内容正确。
- [契约测试](../scripts/contracts_test.rb)：使用 [示例加载器](../scripts/example_loader.rb) 直接执行文档中标记的 Ruby 代码，不维护另一份测试实现。
- [数据库启动器](../scripts/run_postgres.rb)：依赖本机 `initdb/pg_ctl/createdb`，启动临时 PostgreSQL，关闭 TCP，仅允许私有目录的 Unix socket；用完停止并清理；若停止失败则保留数据目录供排查，不读取业务 `DATABASE_URL`。
- [数据库测试](../scripts/postgres_test.rb)：直接加载 [退款示例](../scripts/examples/refunds.rb) 和文档中的领取代码；独立连接、barrier 和有界等待验证并发。不用事务包住整个测试来伪装真实提交。
- `skill-creator` 的 `quick_validate.py` 是可选外部格式复核，需 Python + PyYAML；它不属于本技能运行依赖。缺依赖时使用临时 venv，不修改全局 Python。

夹具固定 Rails 8.1.3.1，并因已复现的 JSON 解码不兼容使用 JSON 2.x。这是验收环境约束，不是所有 Ruby 库都应限制 JSON 版本的建议。更新 Rails/JSON 后应重新验证并移除不再必要的约束。

## 验证边界

2026-09-30 本地验收快照：arm64 macOS，Ruby 4.0.7、Rails 组件 8.1.3.1、JSON 2.21.2、PostgreSQL 18.6，使用本目录锁文件。

| 检查 | 实际结果 |
| --- | --- |
| `check_skill.rb` / 外部 `quick_validate.py` | 通过；后者在临时 Python venv 中安装 PyYAML 6.0.3 |
| `contracts_test.rb` | 8 例 / 98 断言，0 失败、错误或跳过 |
| `run_postgres.rb` → `postgres_test.rb` | 23 例 / 84 断言，0 失败、错误或跳过；临时实例已停止清理 |
| 临时副本的负向验证 | 检查器拒绝坏链接、未闭合围栏；重新引入 `value || true` 后，false 回归测试按预期失败 |

首轮无 Bundler 隔离时，JSON 3 的位置参数不兼容使 JSONB 用例失败；锁定兼容测试依赖后重跑通过，没有删断言或修改框架。上表不是未来运行的保证；复验以当次输出为准。只有标记并被测试加载的示例具有行为验证证据，其余片段是按需替换模型、关联与辅助方法的教学示意。

PostgreSQL 测试证明真实数据库约束、提交/回滚和受控并发；网关是明确协议的替身，队列是 test adapter/失败适配器。它们不证明真实支付、生产队列、HTTP 登录授权、浏览器、迁移升级路径、性能容量或完整 Ruby/Rails 版本矩阵。参考文档中建议覆盖某种场景不代表这里已经执行过该场景。

## 归属与许可

沿用原技能的许可声明：本文档按 CC BY-SA 4.0 提供，不暗示原作者认可。Ruby/Rails/RSpec 社区风格指南采用 CC BY 3.0；Rails Guides 采用 CC BY-SA 4.0。书籍、官方网页及各项目源码权利归各自作者；来源链接用于归属和核验，本轮不复制大段原文。配置样例与测试代码为本技能新增或维护的配套资源。
