# 元编程:心智模型、取舍阶梯与模式

元编程 = 写"在运行时写代码/改变对象模型"的代码。Rails 大量依赖它(`has_many`、`enum`、`delegate`、Concern、回调),所以既要**会读**,也要**克制地写**。

目录:一、对象模型心智图 · 二、取舍阶梯 · 三、模式库 · 四、风险与守则 · 五、读懂 Rails 的"魔法" · 六、测试元编程

## 一、对象模型心智图

只需记住四条,就能推理绝大多数元编程行为:

1. **类也是对象。** 类是 `Class` 的实例,持有方法表和指向 superclass 的引用。模块是没有实例、不能被继承的"方法容器"。
2. **方法查找 = 向右一步,再向上。** 先到接收者的类(若有单例类则先看单例类),再沿 `ancestors` 链向上,直到 `BasicObject`。找不到就调用 `method_missing`。
3. **`ancestors` 顺序:** `prepend` 的模块 → 类自身 → `include` 的模块(后包含的在前)→ 父类 → …。`super` 沿这条链继续找。
4. **`self` 与"当前定义类"是两个上下文。** `def` 把方法定义到"当前定义类";`self` 决定隐式接收者和实例变量属于谁。

```ruby
module Loud;   def speak = super.upcase; end
module Polite; end
class Animal;  def speak = "hi"; end
class Dog < Animal
  prepend Loud
  include Polite
end

Dog.ancestors        # => [Loud, Dog, Polite, Animal, Object, ..., Kernel, BasicObject]
Dog.new.speak        # => "HI"   Loud 先于 Dog,super 指向 Dog → Animal
```

**单例类(singleton class)**:每个对象都可以有只属于自己的方法表。"类方法"其实是类对象的单例方法。

```ruby
class Foo
  puts self            # Foo(self 是 Foo,定义类也是 Foo)
  def bar; end         # 定义为 Foo 的实例方法

  class << self
    puts self          # #<Class:Foo>(进入 Foo 的单例类)
    def baz; end       # 定义为 Foo.baz
  end
end
```

**作用域门(scope gate):** `class`、`module`、`def` 三个关键字会开启新作用域,外部局部变量不可见。用**块**(`Class.new { }`、`define_method { }`、`class_eval { }`)则不开新门,闭包能看到外部变量(Flat Scope)。这是"动态生成方法要用 `define_method` 而不是 `def`"的根本原因。

```ruby
threshold = 10

Order.class_eval do                       # 块:不是作用域门
  define_method(:big?) { total > threshold }   # ✓ 闭包捕获 threshold
end

class Order
  def big?; total > threshold; end        # ✗ NameError:class 是作用域门
end
```

调试利器(遇到"这个方法从哪来的"时先用它们):

```ruby
obj.method(:name).owner            # 方法定义在哪个类/模块
obj.method(:name).source_location  # 文件与行号
Klass.ancestors                    # 查找顺序
Klass.instance_methods(false)      # 仅本类自己定义的
obj.singleton_methods
Klass.instance_method(:name).super_method
```

## 二、取舍阶梯

**永远从最低一级开始,只有明确不够才升级,并在代码或提交说明里写下原因。**

| 级 | 手段 | 适用 | 代价与守则 |
| --- | --- | --- | --- |
| 0 | 普通方法、`case` 显式分派 | 少量固定分支 | 最可搜索、最易调试;两三处分支不值得拼方法名 |
| 1 | `public_send` + **白名单** | 方法名由有限集合决定 | 名字必须来自受控集合;`send` 会绕过可见性,优先 `public_send` |
| 2 | `define_method` / `define_singleton_method` | 批量生成结构相同的方法 | 闭包可用;定义在加载期,不在请求期;命名可预测 |
| 3 | `method_missing` + `respond_to_missing?` | 方法集合真正开放(动态代理、外部 schema) | 必须配套 `respond_to_missing?`,未处理的调用交给 `super`;比普通调用慢,难调试 |
| 4 | `instance_eval` / `instance_exec` / `class_eval`(块形式) | 内部 DSL、扩展某个类 | 块内 `self` 改变,会丢失调用者的方法与实例变量;局部变量仍可见 |
| 5 | 字符串 `eval` / `class_eval "..."` | 生成期性能敏感且输入完全受控 | 必须传 `__FILE__, __LINE__+1`;绝不含外部输入;默认不用 |

决策捷径:

- 只是为了少写两行? → 不要元编程。
- 方法名/常量名来自用户输入? → 先白名单映射,不要 `constantize`/`send` 原始字符串。
- 要改别人的类? → `prepend` 一个模块,而不是重开类重定义(见"around alias vs prepend")。

## 三、模式库

### 3.1 动态方法(Dynamic Method)

```ruby
class Order < ApplicationRecord
  STATUSES = %w[pending paid shipped].freeze

  STATUSES.each do |status|
    define_method(:"#{status}?") { self.status == status }   # 块是闭包,能读 status
  end
end
```

在 Rails 里能用框架能力就不自己生成:`enum :status, {...}` 已生成谓词、scope 与 bang 方法。

### 3.2 类宏(Class Macro)+ Concern

类宏是"在类体里调用的方法",让声明式代码读起来像配置。Rails 中用 `ActiveSupport::Concern` 组织:

```ruby
module Auditable
  extend ActiveSupport::Concern

  included do
    class_attribute :audited_fields, instance_writer: false, default: [].freeze
    after_update :record_audit, if: :audited_change?
  end

  class_methods do
    def audited(*fields)
      self.audited_fields = fields.map(&:to_sym).freeze   # 子类赋值产生自己的值,不污染父类
    end
  end

  private

  def audited_change?
    audited_fields.any? { |field| saved_change_to_attribute?(field) }
  end

  def record_audit
    change_set = saved_changes.slice(*audited_fields.map(&:to_s))
    AuditLog.create!(auditable: self, change_set: change_set)   # 示意:按项目模型调整
  end
end

class Invoice < ApplicationRecord
  include Auditable
  audited :total_cents, :status
end
```

要点:类级配置用 `class_attribute`(而不是 `@@`),存不可变值;需要修改时赋新值而非原地改。Concern 通过 `included` / `class_methods` 声明依赖与类方法,解决"模块依赖模块"的 include 顺序问题。

### 3.3 幽灵方法与动态代理(Ghost Method / Dynamic Proxy)

```ruby
class Settings
  def initialize(data)
    @data = data.transform_keys(&:to_sym).freeze
  end

  def method_missing(name, *args, &block)
    return super unless args.empty? && block.nil? && @data.key?(name)
    @data.fetch(name)
  end

  def respond_to_missing?(name, include_private = false)
    @data.key?(name) || super
  end
end

settings = Settings.new("timeout" => 5)
settings.timeout                  # => 5
settings.respond_to?(:timeout)    # => true(有 respond_to_missing? 才诚实)
settings.retries                  # NoMethodError(交给 super,报错清晰)
```

替代方案往往更好:固定字段用 `Struct`/`Data`;要委托给另一个对象用 `Forwardable`、`SimpleDelegator` 或 Rails 的 `delegate :name, to: :account`;字段已知时在初始化期用 `define_singleton_method` 生成。

### 3.4 Around Alias vs Prepend

需要"包裹已有方法"时,不要 `alias_method :old, :call` 再重定义(易与其他包裹冲突、难以卸载)。用 `prepend`:

```ruby
module Instrumented
  def call(*args, **kwargs, &block)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    super
  ensure
    if started
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      Rails.logger.info("#{self.class}#call #{(elapsed * 1000).round(1)}ms")
    end
  end
end

Client.prepend(Instrumented)
```

`super` 转发当前位置的参数与块；`super()` 不传位置/关键字参数，但仍隐式转发收到的块；显式 `super(&nil)` 才抑制块。省略具名 `&block` 本身不意味着丢块。调用另一个普通方法时则需要 `&block`、匿名块转发或 `...`；Ruby 3 的关键字分离要单独验证，不能把末尾 Hash 当关键字参数。

<!-- example: forwarding -->
```ruby
class ForwardTarget
  def call(value, enabled:, &block)
    [value, enabled, block.call(value)]
  end
end

class ForwardChild < ForwardTarget
  def call(value, enabled:)
    super # 没有具名 &block，块仍然传给父类
  end
end

class ForwardProxy
  def initialize(target)
    @target = target
  end

  def call(...)
    @target.call(...)
  end
end
```

### 3.5 钩子(Hook Methods)

| 钩子 | 触发 | 典型用途 | 注意 |
| --- | --- | --- | --- |
| `included(base)` / `extended` / `prepended` | 模块被混入时 | 给宿主加类方法、注册 | Rails 里用 Concern 的 `included do` |
| `inherited(subclass)` | 类被继承 | 子类自动登记 | 只能看到**已加载**的类;开发环境 reload 会积累旧类 |
| `method_added` | 定义实例方法 | 装饰/记录 | 自身也会被自己的定义触发,注意递归 |
| `const_missing` | 常量未找到 | 旧式 autoload | Rails 用 Zeitwerk,不要自己重写 |

```ruby
class Plugin
  @registry = []
  class << self
    attr_reader :registry

    def inherited(subclass)
      super
      Plugin.registry << subclass       # 注意:只包含已加载的子类
    end
  end
end
```

需要"完整类型集合"(如 STI 全部子类)时,明确加载范围或使用受维护的类型声明,并验证冷启动与 reload 后的结果;不要为一次查询无条件 eager load 整个应用。

### 3.6 内部 DSL:`instance_eval` 与 Clean Room

```ruby
class RouteBuilder
  attr_reader :routes

  def self.build(&block)
    builder = new
    if block.arity == 1
      block.call(builder)              # 显式参数形式:保留调用者的 self 和方法
    else
      builder.instance_eval(&block)    # 隐式形式:块内 self 是 builder
    end
    builder.routes.freeze
  end

  def initialize
    @routes = []
  end

  def get(path, to:)
    @routes << [:get, path, to]
  end
end

RouteBuilder.build do
  get "/orders", to: "orders#index"
end
```

- `instance_eval` 会改变块内 `self`,调用者对象的方法和实例变量不再可见(局部变量仍在)。同时提供 `arity == 1` 形式让使用者选择。
- 减少 DSL 隐式可见方法时，可让 builder 继承 `BasicObject`；它不是沙箱，Ruby 代码仍可通过 `::Kernel` 等访问外部能力。不执行不可信 DSL 代码。
- 什么时候值得写 DSL:同一类声明在多处重复且稳定。DSL 内部仍写普通 Ruby 方法,不要把分支流程写进配置里,否则配置会逐渐变成解释器。

### 3.7 Refinements(精化)

```ruby
module StringExt
  refine String do
    def squish_all = gsub(/\s+/, " ").strip
  end
end

using StringExt          # 只在当前文件(或模块体)之后生效
"a   b".squish_all       # => "a b"
```

精化范围受限、对反射和 `send` 的可见性有限制,在 Rails 代码库里很少用。需要给核心类加行为时优先:普通函数/值对象包装 → 精化 → 极少数场景才 `prepend`。**避免全局 monkey patch。**

### 3.8 受控 `class_eval` 字符串(仅在热路径确有必要)

```ruby
ATTRIBUTES = %i[name email].freeze     # 常量,来源受控

ATTRIBUTES.each do |attr|
  class_eval <<~RUBY, __FILE__, __LINE__ + 1
    def #{attr}_present?
      !#{attr}.nil? && !#{attr}.empty?
    end
  RUBY
end
```

Rails 在生成热路径方法时也用这种写法,并传入文件与行号以保留可读的 backtrace。仅当输入完全来自代码常量时使用;普通业务代码用 `define_method`。

## 四、风险与守则

**可发现性**——读者能否 `grep` 到方法定义?动态生成的方法在注释或 Concern 名里说明来源和名字模式(如"生成 `#{status}?`")。

**可调试性**——`method_missing` 会吞掉拼写错误;必须 `super` 兜底并写 `respond_to_missing?`。字符串 `eval` 不带文件行号会让 backtrace 指向 `(eval)`。

**安全**——`send`、`public_send`、`constantize`、`safe_constantize`、`eval`、`Kernel#open` 不得直接接外部字符串。用映射:

```ruby
EXPORTERS = { "csv" => CsvExporter, "json" => JsonExporter }.freeze
exporter = EXPORTERS.fetch(params[:format]) { raise ArgumentError, "unsupported format" }
```

**线程与重载**——类级可变状态(`@registry`、`@@x`)在多线程和开发环境 reload 下都会出问题。在请求期动态 `define_method` 会造成方法表膨胀与缓存失效,方法应在加载期生成。

**全局影响**——任何修改核心类或框架类的行为都要写清作用范围和加载顺序;能通过组合/委托表达时不要改核心类。

**性能**——动态分派和生成方法的成本受调用形状、运行时与 JIT 影响；不要给出固定快慢排序。只有目标负载测得瓶颈才改写，并保持行为等价。

**注释与文档**——每个元编程点写一句"为什么不能用普通代码"。找不到理由就降级。

## 五、读懂 Rails 的"魔法"

遇到不认识的方法,先用第一节的调试利器定位,再对照这些常见机制:

| 你看到的 | 背后机制 | 怎么验证 |
| --- | --- | --- |
| `has_many :items` 后出现 `items`、`items << item`、`items.build` | 宏在类的**匿名模块**里生成方法(如 `generated_association_methods`),因此可在类中覆盖并 `super` | `Order.ancestors` 看匿名模块;`Order.instance_method(:items).owner` |
| 列名对应的 `name`、`name=`、`name?` | 属性方法按需批量生成到 `generated_attribute_methods` | 覆盖 reader 时调用 `super` 取原值 |
| `enum :status, {…}` 的 `paid?`、`paid!`、`Order.paid` | 生成谓词、bang 方法与 scope(可能与已有方法冲突,Rails 会检查) | `Order.statuses`、`Order.paid.to_sql` |
| `delegate :name, to: :account` | 用受控字符串 `module_eval` 生成转发方法 | `Order.instance_method(:name).source_location` |
| `before_save :x`、`after_commit` | 回调链(`define_callbacks` / `set_callback`),按声明顺序执行,可用 `throw :abort` 中断 | `Order._save_callbacks` |
| `concerning` / `included do` | Concern 延迟到被 include 时才执行块并解决依赖 | 读 `ActiveSupport::Concern` 源码(短小) |
| `class_attribute` | 类级可继承配置,子类赋值不影响父类 | 在子类赋值后对比父子取值 |
| `scope :recent, -> { … }` | 生成类方法,并保证返回 relation(即使 lambda 返回 `nil`) | `Order.method(:recent).source_location` |

学习路径:用 `source_location` 直接打开 Rails gem 的对应文件读(`bundle show activerecord` 找到位置)。读源码比读博客更可靠,因为行为以你项目锁定的版本为准。

## 六、测试元编程

- 测试**生成的行为**而不是生成过程:宏声明后,对象是否响应、行为是否正确、错误输入是否被拒绝。
- 对 `method_missing`:断言 `respond_to?` 与 `method(:x)` 也成立,以及未知方法确实抛 `NoMethodError`。
- 对钩子和注册表:验证冷启动与 reload 后的集合,不要只在已加载的测试进程里断言。
- 对类宏的继承:子类修改配置后父类不受影响。

```ruby
test "子类修改审计字段不影响父类" do
  child = Class.new(Invoice) { audited :notes }
  assert_equal %i[total_cents status], Invoice.audited_fields
  assert_equal %i[notes], child.audited_fields
end
```
