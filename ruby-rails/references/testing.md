# 测试

框架二选一服从项目:项目用 Minitest 就写 Minitest,用 RSpec 就写 RSpec。不因传递依赖里有 minitest 就认定项目用 Minitest,也不为"统一风格"迁移框架。

目录:一、测试哲学 · 二、用例写法 · 三、数据与替身 · 四、隔离与确定性 · 五、Rails 各层测什么 · 六、从边界证明不变量

RuboCop 与 CI 门禁见 [ci.md](ci.md)。

## 一、测试哲学

- 每个用例证明**一个可观察行为**:输入、动作、结果、副作用相邻。测公开行为与业务不变量,不照抄实现的每个分支或内部调用。
- 缺陷修复:先写"修复前失败、修复后通过"的回归,再做最小修复。无法复现时说明证据限度。
- 保持行为的重构:先用现有测试或少量特征测试固定契约,再动结构。
- 失败先判断是本次回归、既有失败还是环境问题;**不删断言、不吞异常、不靠重跑消除失败**。
- 测试失败信息要告诉人哪里错:用能报告期望值与实际值的断言,而不是只断言"没抛异常"。

## 二、用例写法

准备、动作、断言用空行分隔;测试名写结果,`context` 写触发条件。

**Minitest:**

```ruby
class OrderTest < ActiveSupport::TestCase
  test "已发货订单不能取消,且不留下审计记录" do
    order = orders(:shipped)

    assert_no_difference("order.audit_events.count") do
      assert_raises(Order::NotCancellable) do
        order.cancel!(reason: "changed mind", actor_id: users(:alice).id)
      end
    end

    assert_equal "shipped", order.reload.status
  end
end
```

**RSpec:**

```ruby
RSpec.describe Order do
  describe "#cancel!" do
    context "when the order is already shipped" do
      subject(:cancel) { order.cancel!(reason: "changed mind", actor_id: user.id) }

      let(:order) { create(:order, :shipped) }
      let(:user)  { create(:user) }

      it "raises and leaves no audit trail" do
        expect { expect { cancel }.to raise_error(Order::NotCancellable) }
          .not_to change { order.audit_events.count }
        expect(order.reload.status).to eq("shipped")
      end
    end
  end
end
```

- 一个行为可有多个互补断言(RSpec 可用 `aggregate_failures`);需要前置断言才能继续解析的数据,前置失败应终止该路径。
- 负向用例**同时**确认没有非法写入与外部副作用。
- 精确约束调用次数或顺序,只在它们本身属于契约时;不要把内部实现调用全写成 mock 期望。
- `let`(惰性)用于多例共享的准备,`let!` 用于必须先发生的准备;避免深层嵌套与多级重定义隐藏时序。

## 三、数据与替身

- 沿用项目的 fixtures 或 factories,创建**最小相关数据**;纯逻辑测试不碰数据库。
- 查询类测试同时造"应命中"与"不应命中"的记录,证明过滤真的生效。
- 不 stub 被测规则本身。隔离网络、时钟、文件系统等**外部边界**,用项目已有的接口(适配器、可注入依赖)。
- RSpec 优先 verifying doubles(`instance_double`);避免 `any_instance_of`、`receive_message_chain`,以及为了让测试通过而放宽生产 API。
- 离线测试不访问不稳定的第三方;模拟契约要有真实协议或固定样本作依据。适配器集成测试独立运行、标明环境前提,**不声称 mock 证明了生产联通**。
- 协议库可写小型可观察的 transport fake:按事件返回字节/EOF/超时,并记录 write/open/close 与收到的预算;再用受控本地进程/服务覆盖真实适配器。

## 四、隔离与确定性

- 避免 `before(:context)` 共享可变数据。修改 `ENV`、常量、locale、全局配置、时间、文件后必须恢复。
- 时间:Rails 用 `travel_to` / `freeze_time`(`ActiveSupport::Testing::TimeHelpers`,块形式自动恢复),不自动引入 Timecop。
- 随机顺序运行并保留 seed,失败用同一 seed 复现。**不要用重跑至绿代替修复状态泄漏。**
- 并行测试隔离数据库、Redis key、文件、端口与全局状态。
- 并发测试用 `Queue`/barrier 控制交错,用独立连接;等待有上限;线程内错误传回主测试;连接与线程在 `ensure` 中清理;不用固定 `sleep` 猜顺序。
- 时间预算类测试用可控时钟或受控进度流证明 deadline 不被重置,不靠长时间等待堆信心。

## 五、Rails 各层测什么

| 层 | 主要验证 |
| --- | --- |
| 模型/领域规则 | 合法、非法、边界输入;返回值与副作用;状态转换失败不留半成品;校验错误落在对应字段 |
| 唯一性/并发写 | 数据库唯一索引与约束,单独验证竞争,不只测应用层校验 |
| 请求(request/integration) | 走真实路由、认证授权、参数解析、持久化;状态码、响应契约、持久结果、权限范围 |
| 查询对象 | 授权范围内外的记录都存在,证明范围不被参数扩大 |
| Job | 入队断言 ≠ 执行成功:分别测入队参数、`perform` 的效果、重复执行、重试终止 |
| Mailer | 收件人、主题、必要内容,以及触发它的入口 |
| 系统测试 | 只覆盖跨组件的核心用户路径与错误恢复,别用它测所有分支 |
| 迁移 | 空库创建、旧库升级及部署兼容窗口；Zeitwerk 加载检查另行执行 |

request 测试示例(授权范围):

```ruby
class OrdersRequestTest < ActionDispatch::IntegrationTest
  test "看不到其他用户的订单" do
    sign_in_as users(:alice)                      # 按项目的登录辅助方法
    other = orders(:bob_order)

    get order_path(other)

    assert_response :not_found
  end

  test "筛选参数不能扩大数据范围" do
    sign_in_as users(:alice)

    get orders_path, params: { user_id: users(:bob).id }

    assert_response :success
    assert_equal [users(:alice).id], response.parsed_body["orders"].map { |o| o["user_id"] }.uniq
  end
end
```

## 六、从边界证明不变量

以下按改动选用,不要求每个小修改都覆盖:

- **授权查询**:同时造可见与不可见记录 → 用筛选参数试图扩大 → 从详情入口再验证。
- **批量校验**:错误路径带原始行索引与字段路径;失败后旧数据不变。
- **快照同步**:失败后旧数据、关联、缺失标记不变;成功重跑不重复创建对象。
- **共享 JSON 聚合**:分别更新两个子域,确认未涉及字段与密钥保留;承诺并发安全时用不同实例/连接验证交错写入。
- **任务领取**:领取失败、重复执行、旧响应晚到时,没有外部调用、结果覆盖或额外通知。
- **文件替换**:采集/写入失败后旧内容保留;权限正确;临时文件被清理。
- 能力查询(如 `supports?`)测试断言**零 I/O**。

读到这些测试只证明设计意图,**实际执行通过才是当前验收证据**。

技能自身的结构、示例和数据库测试入口见 [sources.md](sources.md)。数据库测试不使用包住整个用例的事务，以便验证真实提交与独立连接；所有测试只在临时实例运行。
