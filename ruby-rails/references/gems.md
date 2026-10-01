# gem、Rake 任务与命令行脚本

适用于:写一个 gem、给 Rails 应用写 Rake 任务、写独立的 Ruby 脚本。语法与工具行为以项目锁定的版本为准;项目既有的目录与发布流程优先于本文。

目录:一、gem 的公开契约 · 二、目录与加载 · 三、gemspec 与版本 · 四、依赖 · 五、发布前验证 · 六、Rake 任务与命令行脚本

## 一、gem 的公开契约

- **公开契约包括文档化的常量、方法、行为、异常及承诺的扩展钩子**;其余标 `private` 或在文档里声明"内部"。改动公开 API 前先列出调用者与已发布的行为。
- 只占**一个**顶层命名空间;不修改核心类和全局状态(见 [metaprogramming.md](metaprogramming.md) 的"全局影响");`require` 可以加载文件和定义常量，但不隐式启动业务 I/O、联网或修改无关全局配置。
- 领域异常可有自己的异常族，参数错误可保留标准异常，公开协议保持兼容(见 [ruby.md](ruby.md) 第 7 节)。
- 配置用构造参数或 `configure` 块;全局可变配置要线程安全,并提供在测试里重置的办法。不要把 `ENV` 的读取散落在各处。
- 弃用先提示、后删除。默认情况下 `deprecated` 类警告不显示,库自己的弃用提示要保证用户看得到:

```ruby
def old_name(*args, **kwargs, &block)
  warn "MyGem#old_name 已弃用,请改用 #new_name(将在 2.0 移除)", uplevel: 1   # uplevel 指向调用者位置
  new_name(*args, **kwargs, &block)
end
```

## 二、目录与加载

```
my_gem/
├── my_gem.gemspec
├── Gemfile
├── Rakefile
├── CHANGELOG.md
├── lib/
│   ├── my_gem.rb              # 入口:只负责加载与公开入口方法
│   └── my_gem/
│       ├── version.rb         # MyGem::VERSION
│       └── client.rb          # MyGem::Client
└── test/  或  spec/
```

- 路径镜像命名空间(`lib/my_gem/client.rb` → `MyGem::Client`)。加载方式沿用项目:`require_relative`,或 Zeitwerk 的 `Zeitwerk::Loader.for_gem`(需要 `loader.setup`,并在测试里验证 `eager_load`)。
- 依赖 Rails 的部分(Railtie、Engine、生成器)放在独立文件,只在 `defined?(Rails)` 时加载;核心逻辑不依赖 Rails,才能被普通 Ruby 项目使用和测试。

## 三、gemspec 与版本

```ruby
require_relative "lib/my_gem/version"

Gem::Specification.new do |spec|
  spec.name                  = "my_gem"
  spec.version               = MyGem::VERSION
  spec.summary               = "一句话说明用途"
  spec.license               = "MIT"
  spec.required_ruby_version = ">= 3.3"                      # 写项目真正测试过的最低版本
  spec.files                 = Dir["lib/**/*", "LICENSE.txt", "README.md"]
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.add_dependency "faraday", ">= 2.0", "< 3"
end
```

- `required_ruby_version` 是对使用者的承诺,最低版本须有验证依据；提高最低版本属于兼容性变更，EOL 本身不授权删除现有支持（维护状态见 [sources.md](sources.md)）。
- 文件列表**显式**且发布前核对,不要把测试夹具、凭据、构建产物打进包。
- 版本遵循 SemVer:补丁 = 修复;次版本 = 向后兼容的新增;主版本 = 破坏公开契约。`CHANGELOG.md` 记录用户可见的变化与弃用。

## 四、依赖

- 运行时依赖尽量少,用区间约束(`">= 2.0", "< 3"`),不锁死到补丁版本;开发依赖沿用项目惯例(`gemspec` + `Gemfile`)。
- 库的 `Gemfile.lock` 是否提交在社区有分歧;需要 CI 可复现时提交,并同时用"新解析的依赖"跑一遍矩阵。
- 新 Ruby 陆续把部分标准库移出 default gems(如 `ostruct`、`benchmark`):代码或老依赖用到时,在 gemspec/Gemfile 显式声明,或改用替代;先看目标 Ruby 的发行说明。

## 五、发布前验证

测试通过不等于可以发布。至少确认:

```bash
gem build my_gem.gemspec                                    # 能构建,警告已处理
gem specification my_gem-1.2.0.gem files                    # 文件列表符合预期
task_gem_dir="$(mktemp -d)"
GEM_HOME="$task_gem_dir" GEM_PATH="$task_gem_dir" gem install ./my_gem-1.2.0.gem --no-document
GEM_HOME="$task_gem_dir" GEM_PATH="$task_gem_dir" ruby -e 'require "my_gem"; puts MyGem::VERSION'
```

- 隔离安装在项目 Bundler 环境之外执行，避免 `BUNDLE_GEMFILE`/`RUBYOPT` 重新加载工作区；离线验证需先准备依赖，不回退到全局 gems。
- 版本矩阵覆盖声明的最低 Ruby 与当前目标 Ruby(见 [ci.md](ci.md) 第二节)。
- **发布前核对目标与用户授权；未获授权不执行 `gem push`**:版本号一旦发布不可复用;撤回(yank)不等于回到从未发布。

## 六、Rake 任务与命令行脚本

**Rake 任务负责操作入口**：解析参数 → 调用业务方法 → 输出执行结果。可复用或复杂逻辑提取后更易测试；简单一次性任务不必强建类。测试任务本身时注意 Rake 的执行状态与 `reenable`，不能把“已执行而被跳过”当作再次成功。

```ruby
# lib/tasks/orders.rake
namespace :orders do
  desc "回填 orders.normalized_email(DRY_RUN=1 只统计不写入)"
  task backfill_email: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    stats = Orders::EmailBackfill.new(batch_size: 500, dry_run: dry_run).call
    puts "处理 #{stats.processed} 条,更新 #{stats.updated} 条#{' (dry-run)' if dry_run}"
  end
end
```

- 破坏性或大批量任务默认提供 `DRY_RUN`,并说明可重复执行(幂等)、如何中断与恢复;大表分批(见 [rails.md](rails.md) 第八节与 [reliability.md](reliability.md))。
- 一次性数据修复不要塞进迁移;放 `lib/tasks` 或 `script/`,记录执行方式、影响范围与回滚办法。
- 需要 Rails 环境才写 `: :environment`,否则任务启动更快、更易测试。

**独立脚本:**

- 参数用 `OptionParser`;对用户可见的输出与错误分流:正常结果写 stdout,诊断写 `$stderr`。
- 退出码有意义:成功 `0`,失败非 `0`(`exit 1` / `abort`);不要在失败时仍以 `0` 退出。
- 处理 `Interrupt`(Ctrl-C),清理临时文件与半成品输出。
- 不在脚本里硬编码路径、密钥和环境地址;破坏性操作先确认目标环境。
- 一次性脚本可以不套用分层与完整测试,但仍遵守边界解析与破坏性操作的安全底线(见 [philosophy.md](philosophy.md) 第四节)。
