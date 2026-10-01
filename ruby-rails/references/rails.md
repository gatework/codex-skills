# Rails 范式:各层落点与写法

示例使用 Ruby 3.3+、Rails 7.2–8.1 范围内的 API，特定 API 单独标注；这是兼容性说明，不是维护支持承诺。来源及实测版本见 [sources.md](sources.md)。具体 API 以项目锁定的版本为准;项目已有的目录与命名约定优先于本文。

目录:一、代码放哪 · 二、控制器 · 三、模型 · 四、Concern · 五、Query/表单/用例对象 · 六、查询与性能 · 七、事务与并发 · 八、迁移 · 九、后台任务 · 十、视图/路由/i18n · 十一、加载与配置 · 十二、API 输出 · 十三、Hotwire

## 一、代码放哪(落点决策)

| 你要写的东西 | 放这里 | 判断依据 |
| --- | --- | --- |
| 解析参数、认证授权、选择响应 | Controller | HTTP 边界职责 |
| 记录自身的不变量、关联、状态转换、派生数据 | Model(具名方法) | 与记录状态紧密相关 |
| 模型里"一项完整能力"(可取消、可归档、可审计) | Concern | 能独立说明宿主依赖;不要求多处复用 |
| 组合筛选/排序 | Query 对象或 model scope | 条件多且会增长时才抽对象 |
| 跨多个模型的一次业务流程 | 用例对象(`call`)放在领域命名空间 | 有独立责任、需要编排与事务边界 |
| 非持久对象的表单校验 | `ActiveModel::Model` | 复用 Rails 校验/错误机制,不建表 |
| 异步执行边界 | Job | 负责序列化、重试与执行边界；可复用业务逻辑放领域层，不为薄壳形式强拆一次性逻辑 |
| 展示格式化 | Helper / Presenter / 视图组件 | 不把 HTML 混入模型 |
| 外部服务协议 | 适配器对象(隔离 SDK/HTTP 细节) | 集中协议变化,便于替换与测试 |
| 授权规则 | 沿用项目方案(Pundit/CanCan/自写 policy) | 授权与参数白名单分开 |

**不要**为每个 action 建 service/repository/serializer 的空壳;不要建只转发同名 CRUD 的层。目录按命名空间生长:`app/models/orders/refund.rb` → `Orders::Refund`,无需新增顶层根目录。

## 二、控制器:薄而清晰

职责:参数 → 授权范围内的查找 → 调用领域方法 → 选择响应。业务判断留在模型/用例里。

```ruby
class CancellationsController < ApplicationController
  before_action :set_order

  def create
    @order.cancel!(reason: cancellation_params[:reason], actor_id: Current.user.id)
    redirect_to @order, notice: t(".success"), status: :see_other
  rescue Order::NotCancellable => error
    redirect_to @order, alert: error.message, status: :see_other
  end

  private
    def set_order
      @order = Current.user.orders.find(params[:order_id])   # 本例授权规则：所有者可取消 pending/paid 订单；缺失即 404
    end

    def cancellation_params
      params.expect(cancellation: [:reason])                  # 7.x 写 params.require(:cancellation).permit(:reason)
    end
end
```

规则:

- **查找从授权范围开始**:`current_user.orders.find(id)`、`Project.visible_to(user).find(id)`。范围只证明可见性，还要按项目 policy 验证动作权限；已有显式授权方案可沿用，不能仅凭全表查找就判定漏洞。批量、导出、任务、附件、Cable 同样确认对象与动作权限。
- **参数白名单**:用 `params.expect`(8.0+)或 `require/permit`,声明标量/数组/嵌套哈希;不要 `permit!`;普通业务入口不接受 `role`、`owner_id`、`tenant_id`；管理或转移操作若确需修改，须有独立动作/字段授权，并验证目标关联范围。允许列表不验证数值格式或业务权限。
- **失败路径要有出口**:`save` 返回 `false` 时重新渲染并带状态码(`status: :unprocessable_entity`);`save!` 异常交给 `rescue_from` 统一映射。
- **`GET` 不产生业务写入**;有 Cookie 会话的写请求保持 CSRF 防护(SPA 也一样)。
- 有独立生命周期的动作可以建成资源:`resources :orders do resource :cancellation, only: :create end`,单个 member action 同样可以清晰表达业务，沿用项目路由风格，不为 CRUD 外形拆控制器。
- 实例变量用于传给视图的数据即可;不要把控制器变成状态容器。

## 三、模型:行为在这里,但有边界

取消订单的完整实现见 [可执行退款示例](../scripts/examples/refunds.rb)，由 [数据库测试](../scripts/postgres_test.rb) 直接加载，避免正文与测试维护两套实现。

本例只支持**一次全额退款**：授权入口传入操作者；`cancel!` 在行锁内重读并校验状态，原状态为 `paid` 才记录退款意图；取消状态、支付标识/金额/币种快照与审计一起提交。通过 Rails 7.2+ 的 `current_transaction.after_commit` 注册派发，跟随最外层事务提交，回滚时不派发。返回订单仅表示取消已接受，不能告诉用户“退款已完成”。外层事务中的调用者仍需等待自己的提交。

较旧版本沿用项目已验证的模型 `after_commit` 或事务通知机制，不用“把入队移到 `with_lock` 下一行”冒充提交后执行。状态、网关幂等与恢复契约见 [reliability.md](reliability.md)。

规则:

- **持久化结果必须处理**:`save`/`update` 返回 `false` 要处理;想要异常就用 `save!`/`update!`。不要把"方法返回了"当成"已持久化"。
- **应用校验给友好错误,数据库约束兜底所有写入入口**:唯一性校验必须对应唯一索引(scope、大小写、条件一致),并发冲突捕获 `ActiveRecord::RecordNotUnique`。
- **不要用 `presence` 校验布尔值**(`false` 会被判空):用 `inclusion: { in: [true, false] }` 并配 `null: false`。
- 枚举用显式整数映射;二态字段按业务设默认值和 `NOT NULL`,保留合法的"未知"状态。
- 关联删除策略(`dependent:`)与外键约束一并设计。
- 业务当前时间用 `Time.current`；按用户/业务时区求日历边界，再转换成查询区间。跨夏令时的一天不一定是 24 小时；时间点与日期分别建模，测试边界日。

**回调的取舍:**

| 可以 | 不建议 |
| --- | --- |
| `before_validation` 规整自身字段(或改用 `normalizes`) | 回调里发邮件、调外部 API、写其他聚合 |
| 维护本记录派生列、`touch` | 让"保存"隐式触发长链业务流程 |
| `after_create_commit` 做轻量、可失败的通知入队(有补偿) | 依赖 `after_commit` 保证队列一定收到 |

回调适合每个写入口都必须维护的局部不变量；显式方法适合用户可追踪的业务流程。关联审计可有意地与业务记录同事务写入，不能笼统禁止“写其他模型”。邮件或外部调用即使移到控制器，也必须确认外层事务与失败契约。

跳过回调/校验的 API(`update_all`、`delete_all`、`insert_all`、`upsert_all`、`update_column`、`increment!` 等)可以用,但要在代码或注释中说明跳过了什么、依赖什么数据库约束。

## 四、Concern:按"一项完整能力"拆

```ruby
# app/models/concerns/archivable.rb
module Archivable
  extend ActiveSupport::Concern

  included do
    scope :archived, -> { where.not(archived_at: nil) }
    scope :unarchived, -> { where(archived_at: nil) }
  end

  def archive!(at: Time.current)
    update!(archived_at: at)
  end

  def archived? = archived_at.present?
end
```

- 一个 Concern = 一项能力,名字是形容词或能力名(`Archivable`、`Subscribable`),文件与命名空间清晰。
- 在文件头注释或代码中写明**宿主依赖**(需要 `archived_at` 列)。
- 不要用 Concern 只为"把大文件切成几段"——依赖和回调顺序仍缠在一起,只是看不见了。
- 只用于单个类且能力完整时,可放在 `app/models/order/cancellable.rb` 的命名空间内(`Order::Cancellable`),不强求多个调用者。

## 五、Query、表单与用例对象

### Query 对象:接收已授权的 relation,返回可组合的 relation

```ruby
class Orders::Search
  class InvalidFilter < ArgumentError; end

  SORTS = {
    "recent" => { created_at: :desc, id: :desc },
    "total"  => { total_cents: :desc, id: :desc }
  }.freeze

  def initialize(scope, params)
    @scope  = scope          # 由调用者传入的已授权范围,内部不再从全表开始
    @params = params
  end

  def call
    relation = filter_status(@scope)
    relation.order(SORTS.fetch(@params[:sort].presence || "recent") { raise InvalidFilter, "sort" })
  end

  private

  def filter_status(relation)
    return relation if @params[:status].blank?
    raise InvalidFilter, "status" unless Order.statuses.key?(@params[:status])   # 枚举白名单
    relation.where(status: @params[:status])
  end
end

# 使用
orders = Orders::Search.new(Current.user.orders, params).call.includes(:items)   # 分页沿用项目方案
```

排序列、方向、可筛选字段分别受控(映射表);动态 SQL 片段不能靠值绑定解决。

### 表单对象:非持久输入 + 校验

整数属性会先调用宽松转换；`"12oops"` 可能成为 `12`，之后的数值校验无法恢复原始意图。先保留输入，再按边界协议解析。下面只接受正整数或纯十进制数字字符串；前导零允许，空白、符号、小数和其他类型拒绝。真实业务还需金额上限、账户授权与余额约束。

<!-- example: transfer_form -->
```ruby
class TransferForm
  include ActiveModel::Model

  attr_accessor :from_account_id, :to_account_id, :amount_cents
  attr_reader :parsed_attributes
  validate :parse_attributes

  private

  def parse_attributes
    @parsed_attributes = nil
    parsed = {}
    %i[from_account_id to_account_id amount_cents].each do |field|
      raw = public_send(field)
      value = if raw.is_a?(Integer)
        raw
      elsif raw.is_a?(String) && raw.bytesize <= 19 && /\A[0-9]+\z/.match?(raw)
        Integer(raw, 10)
      end
      if value && value > 0 && value <= 9_223_372_036_854_775_807
        parsed[field] = value
      else
        errors.add(field, :invalid)
      end
    end
    if parsed.key?(:from_account_id) && parsed[:from_account_id] == parsed[:to_account_id]
      errors.add(:to_account_id, :invalid)
    end
    @parsed_attributes = parsed.freeze if errors.empty?
  end
end
```

只有 `valid?` 返回真时消费 `parsed_attributes`；修改输入后须重新验证，不缓存旧校验结果。

### 用例对象:跨聚合的一次业务流程

以结账为例：用例持有购物车，事务内创建订单、预留库存并记录待扣款意图；提交后派发，恢复规则复用退款示例。库存不足应回滚整个工作单元，返回领域错误；提交后的派发失败不能伪装成“订单创建失败”。不要注入未使用的 `payment_gateway`，网关由实际执行扣款的协作者持有。

是否使用结果对象沿用项目协议，必须区分“订单已创建/待扣款”和“付款完成”。涉及多数据库时，一个 Active Record 事务不提供跨连接原子性。

规则:构造器只准备有效状态,不做难以重试的远程副作用;依赖有真实替换需求时才通过参数传入;沿用项目现有的入口动词(`call`/`perform`/具名动作),不为统一拼写改公共 API;对返回值契约保持一致。

## 六、查询与性能

- **从授权范围开始查找**;`find`(缺失报错)用于按主键必须存在;`find_by`(缺失 `nil`)用于允许不存在;`exists?` 只判断存在性。
- **值一律绑定**:`where(status: x)`、`where("total > ?", n)`;标识符(列名、排序方向)走白名单映射。
- **N+1**:先确认真的访问了关联,再选 `preload`(分开查)、`includes`(Rails 自选)、`eager_load`(JOIN,可对关联加条件)。高风险读路径可对单个 relation 用 `strict_loading` 暴露遗漏,不必为一次优化改全局。
- **投影**:`pluck`/`pick` 用于不需要模型行为的读取,注意空值与顺序;`select` 限列后不要再访问被排除的属性。
- **批处理**：`find_each` 默认按主键游标，relation 上的 `order` 可能被忽略；用 `error_on_ignore: true` 暴露误用。Rails 8.1 自定义 cursor 需包含唯一决胜键并使用稳定列；游标遍历不等于一致快照，导出需要的快照契约单独设计。
- **计数**:`count` 走数据库,`length` 加载后计数,`size` 视是否已加载而定——不要机械替换。
- **分页需要稳定排序**:排序键后追加 `id` 作为决胜列。
- `where.not` 与 `NULL`、多条件逻辑用代表性数据验证;新查询检查执行计划与索引(`explain`)。

```ruby
Order.active.includes(:user, items: :product).find_each(batch_size: 500, error_on_ignore: true) do |order|
  # ...
end
```

## 七、事务与并发

- 事务保证的是**数据库内**原子性;不要在事务里发网络请求。提交后再触发外部效果。
- 约束保护所有写入口的不变量；原子条件更新或 `with_lock` 保护检查后修改；`lock_version` 检测陈旧编辑，三者可以组合。行锁不能代替唯一索引，唯一索引也不能保护任意状态转换。多行不变量需要一致加锁顺序或合适的隔离级别。
- 唯一性冲突以数据库唯一索引为准:

```ruby
begin
  Invitation.create!(email: email, team: team)
rescue ActiveRecord::RecordNotUnique
  Invitation.find_by!(email: email, team: team)   # 并发下已有一条,按业务处理
end
```

注意:若这段代码已处于**外层事务**中,PostgreSQL 在唯一冲突之后不允许该事务继续执行语句。用 `transaction(requires_new: true)`(savepoint)只包住创建那一步,并在它**外面**捕获异常:

```ruby
def self.create_once!(team:, email:)
  transaction(requires_new: true) { create!(team: team, email: email) }
rescue ActiveRecord::RecordNotUnique
  find_by!(team: team, email: email)
end
```

- 原子条件更新(领取任务的标准手法):

```ruby
claimed = Job.where(id: id, state: "pending").update_all(state: "running", claimed_at: Time.current)
return unless claimed == 1        # 只有一个执行者能拿到
```

- 多行加锁保持一致的顺序、临界区尽量短;整个被回滚的工作单元一起重试,避免事务外副作用被重复。

## 八、迁移

- 提交 `schema.rb` 或 `structure.sql` 的生成结果;新增迁移继承生成器给的版本基类(`ActiveRecord::Migration[x.y]`)。**不要改已共享执行过的迁移**。
- 分阶段扩展 → 回填 → 切换 → 收紧/移除：先让旧代码与新结构共存；回填按稳定游标分批、可重入，处理并发新增/修改；确认旧 web 和旧 worker 已退出兼容窗口后再删列或加严格约束。PostgreSQL 大表约束可先 `NOT VALID` 再验证，具体支持范围按约束类型核对。
- 迁移不依赖会随业务变化的当前模型,必要时在迁移里定义最小局部模型或用 SQL。
- 区分空库创建、旧库升级、结构回滚与数据恢复——结构可逆不等于删除的数据可恢复。

```ruby
class AddStatusIndexToOrders < ActiveRecord::Migration[8.1]   # 使用项目实际版本
  disable_ddl_transaction!                                     # PostgreSQL 并发建索引的前提

  def change
    add_index :orders, %i[user_id status], algorithm: :concurrently
  end
end
```

- 并发建索引失败可能留下无效索引；重跑前检查有效性和定义，`if_not_exists` 只按存在性跳过，不能证明已有索引正确。
- 不默认运行 `db:reset`、`db:drop`、`db:schema:load` 或生产迁移;涉及数据库的命令先确认环境。

## 九、后台任务

Job 负责异步执行、序列化、重试和失败归属；领域规则有复用需求时提取对象。关键业务示例与恢复协议统一见 [reliability.md](reliability.md)，不要另写一个仅凭 `cancelled? && refunded_at.nil?` 就退款的简版：未付款的订单也可能已取消。

- 原始 ID 与 GlobalID 均可使用；记录消失后忽略、报错或补偿由业务决定，涉及资金的任务不默认 `discard_on DeserializationError`。
- `perform_later` 的返回值、提交后延迟入队及后端持久性分别核对；返回 job 不证明任务执行。7.2+ 配置及默认值有版本差异，读取目标框架源码和适配器配置。
- 临时故障采用有界重试；退款恢复扫描还需遵循网关限流、退避和人工处理阈值，不能用扫描无限高速重试。永久拒绝保留失败状态，未知结果先确认。

## 十、视图、路由与 i18n

- 模板负责展示;partial 用显式 locals 表达输入:`<%= render "orders/row", order: order %>`。复杂展示逻辑进 helper 或项目已有的 presenter。
- 同一模板内复用片段用 `capture`;`content_for` 保留给页面与布局间的具名内容槽,不要用它偷偷向任意 partial 传数据。
- HTML 输出保留模板转义;不对未信任值 `raw`/`html_safe`。
- 路由 RESTful:资源用名词,避免无必要的深层嵌套，可用 `shallow: true`；资源和 member action 按业务语义与既有约定选择。
- 文案走 i18n,使用惰性查找 `t(".title")`;错误信息用 `errors.add(:field, :invalid)` 让 locale 决定文案。

```ruby
resources :orders, only: %i[index show create] do
  resource :cancellation, only: :create      # POST /orders/:order_id/cancellation
end
```

## 十一、加载与配置

- Zeitwerk 命名:`app/models/orders/refund.rb` ↔ `Orders::Refund`;`app/*` 子目录本身是根,不构成命名空间(不是 `Models::Orders::Refund`)。
- 改目录或缩写后运行 `bin/rails zeitwerk:check`;`lib` 的加载方式先读配置(7.1+ 可用 `config.autoload_lib(ignore: %w[assets tasks])`)。
- `subclasses`/`descendants` 只反映已加载的类,别当完整插件目录;需要随重载更新的注册放在幂等的 `to_prepare` 中,避免非重载全局表持有可重载类。
- 密钥用 credentials/环境注入;过滤日志参数;不提交 master key。
- `Current`(`ActiveSupport::CurrentAttributes`)只放请求级上下文(用户、租户),在边界读取后**显式传入领域对象和任务**;领域深处隐式读取 `Current` 会造成隐藏依赖。

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :user
end
```

## 十二、API 输出

- 序列化不是授权:列表返回必要摘要,大文本与诊断详情走授权后的详情路径。
- 领域类型到 JSON 集中在展示边界,明确时间(ISO 8601)、枚举与标识符的表示;不要用任意 `to_s` 兜底把未知类型变成貌似有效的值。
- 错误响应保留字段路径和稳定错误码,便于客户端定位:

```json
{ "errors": [ { "path": "items[2].quantity", "code": "greater_than", "message": "必须大于 0" } ] }
```

- 批量输入先校验形状、行数与字段,再做昂贵读取或副作用;错误保留原始行索引;一次批量计算使用同一个版本/时间基准,并设置整个请求的累计展开预算。
- 同一个 JSON 列承载多个子域时,复用统一的写入口并在锁内读改写,避免陈旧副本覆盖其他节点;明确"未提供 / 空值 / 替换 / 删除"对含密钥配置的不同含义。

## 十三、Hotwire(Turbo 与 Stimulus)

- **先有可用的服务端渲染,再用 Turbo 增强。** 表单失败时重新渲染并返回 `422`(`status: :unprocessable_entity`);对非 GET 请求(如 `DELETE`)成功后重定向用 `303`(`redirect_to ..., status: :see_other`),否则浏览器可能用原方法跟随重定向。
- **Frame 与 Stream 的响应和整页一样要授权。** 从授权范围查找;Frame 只决定渲染范围,不是权限边界。
- **广播会把渲染结果发给所有订阅者**(`broadcasts_to`、`broadcast_*_later_to`):订阅本身要授权,signed stream name 不代替对象级授权;广播内容不得包含订阅者无权看到的字段;`_later_` 表示异步，不自动保证提交时机；从提交后钩子触发或核对任务的延迟入队配置，再异步广播(与本文"外部效果在提交之后"同一原则)。
- DOM id 用 `dom_id(record)` 生成,不手拼;同一条记录在列表与详情里的 id 规则保持一致。
- **Stimulus controller 只管交互状态与 DOM**:用 values/targets/actions 声明依赖;不放业务规则,不在 JS 里复制服务端的授权判断。
- 验证:request 测试断言 `turbo_stream` 响应的格式与状态码(`post path, as: :turbo_stream`);系统测试只覆盖关键交互,不测所有分支。
