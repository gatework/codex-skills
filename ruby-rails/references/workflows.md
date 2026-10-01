# 实战：把规则连成业务路径

这里只组织决策与验收，关键实现引用单一来源。本文是示例契约，不代表已经在用户项目实现；交付结果必须来自当次运行。

## 一、取消订单并退款

**需求**：用户取消自己的订单；未付款只取消，已付款发起一次全额退款。

- 勘察项目的路由、授权、状态模型、队列、支付协议和恢复机制；沿用现有目录，不默认新增 service 或 outbox。
- 本例只有所有者能取消，允许 `pending/paid`，已发货或已取消拒绝；若项目角色规则更复杂，查找后调用动作 policy，不能把可见性当权限。
- [取消与退款实现](../scripts/examples/refunds.rb) 在行锁内保存取消、审计和退款快照；提交后派发。持久状态、网关前提及恢复见 [可靠性](reliability.md)。
- 页面区分“取消已接受、退款待处理”和“退款完成”；入队失败不能诱导用户重复发起另一笔退款。
- 验收包含他人订单拒绝且无副作用、未付款不退款、外层事务回滚、并发取消、入队拒绝/异常、重复执行、远端已生效但超时，以及晚到 worker 不覆盖确认结果。

本技能的集成夹具证明数据库/队列接口的局部行为；应用还需沿真实路由验证登录、对象/动作授权、参数形状和响应。不要把只有模型测试的结果写成请求验收。

## 二、修复被覆盖的 false

**契约**：缺失与 `nil` 默认开启，显式 `false` 保持关闭；其他值的合法性由输入边界负责。

<!-- example: settings -->
```ruby
class Settings
  def initialize(options)
    @options = options.dup.freeze
  end

  def notifications_enabled
    value = @options[:notifications]
    value.nil? ? true : value
  end
end
```

回归分别断言 `{}`、`notifications: nil`、`notifications: false` 和 `notifications: true`。旧实现 `options[:notifications] || true` 会破坏关闭；`fetch(:notifications, true)` 则不满足本例的 nil 默认契约。搜索同类写法时检查调用者，不机械批量替换。

## 三、评审业务写入

```ruby
order = Order.find(params[:id])
order.update(params.permit!)
OrderMailer.updated(order).deliver_now
```

按风险而非风格排序：

- 核对调用上下文的对象/动作授权；片段没有展示不等于整个应用没有授权，定位真实可越权路径后再报告。
- `permit!` 无字段边界；即使操作者可更新订单，也不能因此修改任意所有者、租户或金额字段。
- `update` 失败后仍发邮件；验证拒绝路径无外部效果。
- 同步邮件阻塞请求，且需要确认事务时机；按业务选择提交后派发与失败恢复。

输出位置、触发条件、影响和修复方向；缺少上下文时标注待核实，不把“我偏好另一层”升级为缺陷。

## 四、幂等创建

对“同一用户重复提交订单”，先决定：幂等键作用域、有效期、同键异载荷的响应、处理中是否可返回旧结果。数据库唯一索引只阻止同键多行，不能证明两个请求语义相同。

- 从已授权用户范围创建；键由入口显式解析，不让任意 `**attrs` 覆盖所有者或幂等键。
- 原子保存键与规范化业务载荷（或稳定摘要）；同键同载荷返回原结果，异载荷返回明确冲突。
- 优先核对框架 `create_or_find_by!` 与唯一索引的适用条件；自写创建/冲突恢复时，用 savepoint 隔离 PostgreSQL 唯一冲突，捕获发生在 savepoint 外，并只处理目标约束冲突。
- 存在唯一性 validation 时，重复可能先变成 `RecordInvalid`，不能只测 `RecordNotUnique` 分支；创建后被并发删除也是需要明确处理的失败。
- 用独立连接验证竞争；前端禁用按钮只是体验，不是业务幂等保证。
