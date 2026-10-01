# Ruby 代码范式与编码规范

适用于普通 Ruby 库、脚本以及 Rails 里的纯 Ruby 对象。语法特性是否可用取决于项目最低 Ruby 版本;格式(行宽、引号)沿用项目 RuboCop 配置。

目录:1 命名与文件 · 2 真值与缺失 · 3 方法设计 · 4 对象建模 · 5 块/Proc/迭代器 · 6 集合 · 7 异常 · 8 资源 · 9 字符串与正则 · 10 现代语法采用条件 · 11 并发基础 · 12 版本迁移常见坑

## 1 命名与文件

- UTF-8、两空格、LF、文件末尾换行。文件/变量/方法 `snake_case`;类与模块 `UpperCamelCase`;常量 `SCREAMING_SNAKE_CASE`。一个主要公开类型一个文件,路径镜像命名空间(`lib/billing/invoice.rb` → `Billing::Invoice`)。
- 类名说明领域概念,方法名说明查询或动作:`Invoice`、`PolicyParser`、`total`、`parse`、`deliver`。避免无信息量的 `Manager`、`Processor`、`data`、`info`。
- 变量带上形状和单位,按需而非机械:`user` / `users` / `users_by_id` / `timeout_seconds` / `max_bytes`。
- 谓词 `?` 返回布尔(`enabled?`,不用 `is_enabled?`);`!` 表示更危险或失败约定不同,不是"重要方法"标记。
- 公开方法服务调用者,其余 `private`。`private` 对 `def self.x` 无效,用 `private_class_method` 或 `class << self` 块内 `private`。
- 缩写遵循项目 inflector(`API`、`SSL`),移动 Rails 文件时不能仅凭字面大小写改名。

## 2 真值与缺失

Ruby 里只有 `nil` 和 `false` 为假;`0`、`""`、`[]` 都为真。**缺失、`nil`、`false`、非法是四件不同的事。**

```ruby
# 保留合法的 false / nil
enabled = options.fetch(:enabled, true)   # 传入 false 仍是 false
enabled = options[:enabled] || true        # ✗ false 被覆盖成 true

# 必需键用 fetch:缺失时立刻报错,而不是晚点在别处 NoMethodError
url = config.fetch(:url)

# 允许缺失的嵌套结构用 dig;必需字段不要用 dig 代替校验
city = payload.dig(:user, :address, :city)
```

记忆化(memoization)要看值是否可能为 `nil`/`false`:

```ruby
def exchange_rate                 # 值不会是 nil/false:可以用 ||=
  @exchange_rate ||= fetch_rate
end

def premium?                      # 值可能是 false:用 defined? 区分"尚未计算"
  return @premium if defined?(@premium)
  @premium = compute_premium
end
```

`||=` 不是线程同步;`@x ||= begin ... return ... end` 里的 `return` 会退出整个方法并跳过赋值。

`&.` 只用在业务上允许接收者为 `nil` 的位置;长链 `&.` 会掩盖"本不该缺失"的对象。它对 `false` 不起作用。

## 3 方法设计

**守卫子句降低嵌套,主流程保持平铺:**

```ruby
def discount_cents(order)
  return 0 unless order.paid?
  return 0 if order.items.empty?

  Rational(order.subtotal_cents * discount_bps_for(order.customer), 10_000).round   # 整数基点 + 有理数,金额不用浮点
end
```

**可选参数用关键字**(位置参数超过两个、或含布尔开关时尤其):

```ruby
def deliver(message, to:, retries: 3, urgent: false)
  # ...
end

deliver(msg, to: user, urgent: true)   # ✓ 读得懂
deliver(msg, user, 3, true)            # ✗ 谁是谁?
```

业务 API 列出需要的关键字,不要用 `**options` 吞掉拼写错误;完整透明转发用 `...`,需要修改参数时才显式写 `*args, **kwargs, &block`。

**命令/查询分离:** 查询返回值且无副作用;命令改变状态,失败要么抛异常要么返回约定好的结果。

```ruby
def total_cents = items.sum(&:cents)       # 查询(单表达式,3.0+)
def close!                                 # 命令:非法状态抛异常
  raise InvalidState, "already closed" if closed?
  update!(closed_at: Time.current)
end
```

**返回值稳定:** 不要在同一方法里无约定地混用记录、字符串错误与 `false`。已有的联合返回协议要保持并测试每个分支;普通"结果 / `nil` / 具体异常"够用时不要自建 Result 框架。末尾新增日志行会意外改变隐式返回值。

**抽象层次一致:** 一个方法里要么编排具名步骤,要么处理细节,不要混。但不要把连续简单的计算拆成一堆一行方法。

```ruby
def sync!(account)
  snapshot = fetch_snapshot(account)     # 编排:具名步骤
  validate_snapshot!(snapshot)
  apply_snapshot(account, snapshot)
end
```

**默认不修改传入参数**;确需原地修改时在命名和文档里写清所有权。

## 4 对象建模

**选型:**

| 需求 | 选择 |
| --- | --- |
| 有身份、可变状态、协作协议 | 普通类 |
| 不可变的小值(金额、坐标、范围),无 writer | `Data.define`(3.2+) |
| 轻量可变记录、位置访问 | `Struct`(`keyword_init: true` 更清晰) |
| 结构固定、仅作传递、无行为 | Hash(在边界内保持 key 风格统一) |
| 共享的小型能力 | 模块(mix-in) |
| 仅为命名空间/工具函数 | `module` + `module_function` 或 `def self.` |

`Data` 的成员若引用可变对象,并不递归不可变;`freeze` 也不递归。

**值对象**——相等性由值决定;重写 `==` 与 `eql?` 时必须保证 `hash` 一致,否则放进 Hash/Set 会出错:

<!-- example: money -->
```ruby
Money = Data.define(:cents, :currency) do
  include Comparable

  def initialize(cents:, currency:)
    raise ArgumentError, "integer cents required" unless cents.is_a?(Integer)
    raise ArgumentError, "currency required" unless currency.is_a?(String) && /\A[A-Z]{3}\z/.match?(currency)
    super(cents: cents, currency: currency.dup.freeze)
  end

  def <=>(other)
    return nil unless other.instance_of?(self.class) && currency == other.currency
    cents <=> other.cents
  end

  def +(other)
    raise ArgumentError, "incompatible money" unless other.instance_of?(self.class) && currency == other.currency
    with(cents: cents + other.cents)
  end
end
```

这里的三字母格式不是有效币种名录；支持币种由业务边界验证，`cents` 仅适用于固定两位小数的本例。多币种按各币种最小单位建模，汇率/税费采用 BigDecimal 或 Rational，明确逐行还是合计舍入及舍入方式，不经 Float 中转。展示也应避免先转浮点造成大金额精度损失。

`==` 与 `eql?` 不要求处处相同（例如 Ruby 的 `1 == 1.0`）；Hash/Set 要求 `eql?` 相等的对象具有相同 `hash`。本例 `Comparable#==` 走 `<=>`，`Data#eql?`/`hash` 走成员值语义；约束成员类型且拥有冻结副本后，分别测试比较与 Hash/Set 行为。不递归冻结调用者的对象。

**Enumerable 需要先有 `each`:**

```ruby
class Playlist
  include Enumerable

  def initialize(tracks)
    @tracks = tracks.dup.freeze
  end

  def each(&block)
    return enum_for(:each) { @tracks.size } unless block   # 无块返回 Enumerator

    @tracks.each(&block)
    self
  end
end

playlist.map(&:title)
playlist.min_by(&:duration)
playlist.each_slice(10).to_a
```

**转换协议:** 显式转换 `to_s`/`to_a`/`to_h`/`to_i` 可随意提供;隐式转换 `to_str`/`to_ary`/`to_hash` 表示"我本质上就是字符串/数组/哈希",会被核心方法自动调用,谨慎实现。`to_proc` 让对象能用 `&obj`。重写 `inspect` 时避免泄露密钥。

**组合优先于继承;继承时守住里氏替换**——子类要保持调用者依赖的参数、结果、异常与副作用契约,不能只因方法名相同就视为可替换。避免继承共享的 `@@` 类变量,用 `class_attribute` 或类级实例变量。

**访问器:** 只读用 `attr_reader`;只有允许调用者直接改状态时才开放 writer。有校验或状态转换的写入用具名方法,别让自动生成的 writer 绕过不变量。调用 writer 必须 `self.name = value`,否则只是新建局部变量。

## 5 块、Proc、lambda 与迭代器

```ruby
# 写一个接收块的方法:控制流程与资源,块提供变化点
def with_retry(attempts: 3, on: StandardError)   # 示意:未含退避与总时间预算,生产中要补上
  tries = 0
  begin
    tries += 1
    yield tries
  rescue *Array(on)                              # on 可以是单个类或数组
    retry if tries < attempts
    raise
  end
end

with_retry(on: Net::ReadTimeout) { |n| client.get(url) }   # 仅对幂等操作重试
```

- 自定义迭代方法无块时返回 `Enumerator`；要求业务块的资源/事务/重试方法应明确拒绝缺块，不机械返回惰性操作。
- 块是闭包,能看到定义处的局部变量;`def` 看不到(见 [metaprogramming.md](metaprogramming.md) 的作用域门)。
- **`return` 语义:** 普通 block/proc 里的 `return` 会从外围方法返回;lambda 里的 `return` 只从 lambda 返回。需要局部提前返回时用 `next` 或 lambda。
- `{}` 与 `do…end` 优先级不同:`puts [1,2].map { … }` 与 `puts [1,2].map do … end` 行为不同。多行 block 用 `do…end`,单行用 `{}`,不要为排版互换。
- `&:name` 适合短小无歧义的映射;复杂逻辑写成具名块参数。

## 6 集合

```ruby
names   = users.map(&:name)                          # 变换
adults  = users.select { |u| u.age >= 18 }           # 筛选
admin   = users.find(&:admin?)                       # 查找,返回元素或 nil
by_id   = users.index_by(&:id)                       # ActiveSupport;纯 Ruby 用 to_h { |u| [u.id, u] }
by_role = users.group_by(&:role)                     # 分组 → { role => [users] }
counts  = tags.tally                                 # 计数 → { "ruby" => 3 }
ok, bad = results.partition(&:success?)              # 二分
total   = items.sum(&:cents)                         # 求和(空集合为 0)
index   = items.each_with_object({}) { |i, h| h[i.sku] = i }
batches = ids.each_slice(500)                        # 分批
top     = scores.max_by(3) { |s| s.value }           # 取前 N
```

- **`map` 表示变换,`each` 表示副作用。** 不要用 `map` 做副作用后丢弃结果。
- `filter_map` 会同时丢弃 `nil` 和 `false`;只想去 `nil` 时用 `map…compact`。
- `compact!`/`uniq!` 无变化时返回 `nil`；`sort!` 返回数组自身。逐个核对 bang 方法的返回契约，不从 `!` 推导是否可串联。
- 不在遍历中改变集合结构。大集合用 `each_slice`、`lazy` 或(Rails)`find_each` 流式处理。
- 排序要稳定时加第二排序键:`sort_by { |u| [u.last_name, u.id] }`。
- `Array#include?` 用 `==`,`Set` 用 `eql?`/`hash`(`1` 与 `1.0` 结果可能不同)。需要去重且反复查询成员时用 `Set`;不要把 `Set` 的迭代顺序当业务保证。
- `Hash.new([])` 与 `Array.new(3, [])` 共享同一个默认对象,需要独立元素时用块:`Hash.new { |h, k| h[k] = [] }`。
- Hash 键在存储期间要保持 `hash`/`eql?` 稳定,别改动作为键的数组或对象。

## 7 异常

**领域错误可建立继承 `StandardError` 的异常族；参数错误可沿用 `ArgumentError`/`TypeError`，公开异常协议先看项目契约，不把所有失败包装成一个类：**

```ruby
module Billing
  class Error < StandardError; end
  class CardDeclined < Error
    attr_reader :code

    def initialize(message = "card declined", code: nil)
      super(message)
      @code = code
    end
  end
end
```

**只捕获能恢复、翻译或补充上下文的具体异常,并缩小 `begin` 的范围:**

```ruby
def fetch_profile(id)
  response = client.get("/profiles/#{id}")
  JSON.parse(response.body)
rescue Faraday::TimeoutError
  raise Billing::Error, "profile service timeout"     # 原异常自动成为新异常的 cause
rescue JSON::ParserError
  raise Billing::Error, "profile service returned invalid JSON"
end
```

规则:

- 不吞掉未知失败。通常捕获具体的 `StandardError` 子类；资源边界若必须在任何异常下清理，优先 `ensure`。既有代码用 `rescue Exception` 清理后立即裸 `raise` 时，先验证生命周期契约，不为风格缩窄覆盖范围。
- 预期的"未找到"与基础设施故障用不同契约。
- 重新抛出当前异常用裸 `raise`;在 `rescue` 里抛新异常会自动设置 `cause`,保留诊断因果。公开异常必须隔离敏感协议内容时，可以有意使用 `cause: nil`，同时在受控诊断通道保留必要证据；不破坏已有脱敏契约。
- 重试有次数和总预算上限,且仅针对可安全重试(幂等)的操作;写请求超时可能已生效,需要幂等键或回读确认。
- 不要在每一层重复记录同一个异常;在能处理的地方记录一次。
- 异常不用于普通分支;但对有竞态的 I/O(先 `exist?` 再读),直接操作并处理异常比检查更正确。

## 8 资源与副作用

```ruby
# 块形式自动关闭
File.open(path, "r:UTF-8") { |f| f.each_line { |line| handle(line) } }

# 自己提供资源 API:有块则保证释放
def self.open(path)
  io = new(path)
  return io unless block_given?

  begin
    yield io
  ensure
    io.close
  end
end
```

- `ensure` 中不要 `return`;操作失败与清理失败同时出现时,保留主错误,另行记录清理问题。
- 不关闭调用者拥有的资源;重复 `close` 应幂等;GC 不保证文件/连接及时关闭。
- 文件替换用"写临时文件 → flush/fsync → `rename`"的原子方式,避免 `exist?` 后再写的竞态。
- 计时用 `Process.clock_gettime(Process::CLOCK_MONOTONIC)`;日志时间用墙上时间。

## 9 字符串、符号与正则

- 整串校验用 `\A…\z`(`^`/`$` 是行锚点);固定文本查找不用正则;仅判断匹配用 `match?`;需要字段用具名捕获并处理未匹配:

```ruby
SLUG = /\A(?<year>\d{4})-(?<slug>[a-z0-9-]+)\z/
if (m = SLUG.match(text))
  publish(year: m[:year].to_i, slug: m[:slug])
else
  raise ArgumentError, "invalid slug: #{text.inspect}"
end
```

- 多行文本用 `<<~HEREDOC`,但协议要求的空白与插值行为要保留。
- `frozen_string_literal: true` 沿用项目约定;需要可变缓冲区时 `String.new`。`force_encoding` 只改标记不转码,`encode` 才转换。
- 字符串 key 与符号 key 在普通 Hash 里不同;边界统一一次并保持公开协议,不假设 Rails 的 indifferent access 存在于纯 Ruby。
- HTML 输出走框架转义,不要用字符串拼接充当安全输出。

## 10 现代语法采用条件

以下都有稳定语言支持,但**先核对项目最低 Ruby 版本**;老代码不为此统一改写。

| 表达 | 适合 | 保留的边界 |
| --- | --- | --- |
| `def ready? = state == :ready`(3.0+) | 单表达式查询/委托 | 多步骤、副作用、复杂分支用普通方法体 |
| `{ name:, email: }` / `call(name:)`(3.1+) | 局部变量名恰好是字段名 | 保持无歧义;调用保留括号 |
| `def relay(...)` / `target(...)`(2.7+) | 透明转发位置、关键字、块 | 需要校验或改参数时显式命名 |
| `case … in …`(3.0+) | 嵌套数据的分支与解构 | Hash 模式默认允许多余 key;未匹配抛 `NoMatchingPatternError`,需明确处理 |
| `Data.define`(3.2+) | 不可变小值对象 | 成员仍可能可变 |
| `Hash#except`、`Array#sum`、`filter_map`、`each_with_object` | 日常数据处理 | 注意 `filter_map` 丢弃 `false` |
| `it`(块参数,3.4+) | 极短的块 | 嵌套或多参数用具名变量 |

模式匹配示例:

```ruby
case event
in { type: "order.paid", order_id: Integer => id }
  mark_paid(id)
in { type: "order.cancelled", order_id: Integer => id, reason: String => reason }
  mark_cancelled(id, reason)
in { type: String => type }
  raise UnknownEvent, type
end
```

## 11 并发基础

- CRuby 的 GVL 不保证业务原子性;共享读改写需要 `Mutex`、数据库锁或队列。
- 线程中的异常默认只打印;用 `Thread#join`(会重新抛出该线程的异常)或显式收集结果,让主流程观察到失败。
- 限制并发度,并考虑输入队列背压与结果内存;并发完成顺序与对外结果顺序分别定义,必要时按输入索引归位。

```ruby
queue = Queue.new
items.each { |item| queue << item }
queue.close                                    # 关闭后队列取空时 pop 返回 nil(元素本身不能是 nil/false)

workers = Array.new(4) do
  Thread.new do
    results = []
    while (item = queue.pop)
      results << process(item)
    end
    results
  end
end
all = workers.flat_map(&:value)                # value 会 join,线程内异常在此重新抛出
```

- 不要把租户/请求/用户状态放进进程共享的类变量或全局变量。
- Rails 里新增线程调用框架代码时,考虑 `Rails.application.executor.wrap` 与数据库连接所有权;普通工作优先沿用现有任务队列。

## 12 版本迁移常见坑

升级或跨版本维护时先读**目标版本的发行说明**,并用 `-W:deprecated`(CI 里可设 `RUBYOPT=-W:deprecated`)提前暴露弃用。以下是常遇到的几类:

- **3.4:字符串字面量是"chilled string"。** 没有 `frozen_string_literal` 魔法注释时,原地修改字面量在开启弃用警告的情况下会提示。需要可变缓冲区用 `String.new` 或 `+""`。
- **3.4:`Hash#inspect` 输出格式变了**(如 `{name: "x", "k" => 1}`)。测试里不要比较 `inspect`/`to_s` 的字符串,改为断言结构。
- **3.4:错误信息的引号风格变了。** 不要用错误消息文本做逻辑判断或精确断言,断言异常类与关键字段。
- **标准库打包随版本变化**：例如 Ruby 3.4 的 `bigdecimal`、Ruby 4.0 的 `ostruct`/`benchmark` 从 default gems 转为 bundled gems；Bundler 环境用到它们时需声明实际依赖，以目标版本发行说明为准。
- **工具链跟着动:** RuboCop 插件加载语法从 `require:` 改为 `plugins:`(1.72+);老版本 RuboCop、nokogiri 等可能不支持新 Ruby,升级锁文件时分开提交并单独验证。
