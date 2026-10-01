# RuboCop 与 CI 门禁

测试的写法与取舍见 [testing.md](testing.md)。

目录:一、RuboCop 与格式 · 二、CI 门禁

## 一、RuboCop 与格式

- 沿用 `Gemfile.lock` 里的 RuboCop 与插件、现有 `.rubocop.yml` 及继承规则。Rails Omakase 项目不叠加另一整套风格配置;先看有效规则再加局部差异。插件加载语法随 RuboCop 版本变化(`require` → `plugins`),不要盲改。
- 新项目没有任何约定时,可从 [`assets/rubocop.yml`](../assets/rubocop.yml) 起步,并显式设置 `AllCops/TargetRubyVersion` 为最低支持版本。已有 120 列、单引号等约定一律保留。
- `bundle exec rubocop --show-cops` 确认配置可读;只检查改动范围:`bundle exec rubocop path/to/changed_file.rb`。
- **不自动全仓 `-A`,不批量生成 TODO 隐藏新问题。** 自动修正即使标为 safe 也要看 diff 并跑相关测试。历史违规有基线时保持基线不扩大;工具升级与业务改动分开提交。
- 规则分层验证:

| 规则类型 | 放哪里验证 |
| --- | --- |
| 缩进、引号、行宽、常见命名 | RuboCop(单一配置) |
| 语法与依赖兼容 | 最低支持 Ruby 与目标运行时的 CI(`TargetRubyVersion` 只是静态配置) |
| `false/nil`、参数转发、返回值、可变对象、异常 | 行为回归测试 |
| 职责边界、领域命名、抽象是否必要 | 代码评审([review.md](review.md)) |

- 项目已有 Steep/Sorbet 才维护对应签名并跑其入口;不为风格修改引入第二套类型系统。不靠扩大 `untyped`、强行 cast 或关闭整文件检查让 CI 变绿。

## 二、CI 门禁

- 复用 `Rakefile`、`bin/ci` 或 `script/ci`,**读过实际命令再执行**;统一入口要真实传播失败(不要 `|| true`)。
- 本地与 CI 用同一个 Bundler/项目入口和提交的配置;CI 用锁文件安装,验证中途不悄悄升级依赖;CI 只检查,不自动改源码。
- 常见候选命令(执行前核对项目):

| 项目 | 需要证明 | 常见命令 |
| --- | --- | --- |
| 普通 gem | 支持版本语法、公开 API、真实安装包可用 | `bundle exec rake`;`gem build x.gemspec`;在隔离 `GEM_HOME` 安装并加载生成的包 |
| Rails | 行为、迁移后结构、eager load | `bin/rails db:prepare`(仅测试库)、`bin/rails zeitwerk:check`、`bin/rails test` 或 `bundle exec rspec` |
| 前端/系统 | 浏览器交互、构建与类型契约 | 项目已有的 system/build/typecheck 入口 |
| 安全 | 已知依赖风险、框架静态风险 | 项目已有的 bundler-audit / Brakeman;结果要处置而非只上传日志 |

- 版本矩阵至少覆盖声明的最低 Ruby 与当前目标版本,以及实际影响行为的平台;不为覆盖全世界扩大矩阵。
- 测试库与开发库不共享地址和库名;需要 Redis/队列等服务时在 CI 里真实提供。普通单测可用 test adapter,任务并发与真实队列保证需单独集成验证。
- GitHub Actions:最小 token permissions,不把秘密交给不可信 PR 代码;第三方 action 采用项目认可的固定版本策略;缓存按运行时、平台与锁文件区分,不代替依赖校验。
- required gate 显式依赖必要 job;失败、取消、意外跳过不能被当成成功;路径过滤也要保证 required check 有确定结果。
- 发布额外验证 gemspec 文件列表、构建产物、隔离安装加载与版本;Rails 发布核对迁移兼容窗口与恢复方案。**测试通过不等于授权发布。**
- 报告分别写:已通过、未执行、环境阻塞、仍有失败。只测局部就只声称局部通过。
