# Skill 验收场景

维护者逐项自查；独立行为评估时只给被评估 Codex “输入”及原始文件，不给期望答案。记录读取的参考、实际结论、越界动作、证据与遗漏。没有执行独立评估就写“未执行”，不能以此表存在代表通过。

| 输入任务与原始条件 | 应作出的判断 | 不可接受的判断 | 验证 |
| --- | --- | --- | --- |
| 修复恢复扫描：`perform_later` 没抛异常却未入队 | 核对 adapter、false、enqueue_error 和 callback 中止；失败项保留，健康项继续 | 只 rescue 异常就声称完整处理 | 实际 Active Job 拒绝用例 + 扫描行为 |
| service 内 transaction 后 enqueue，调用者还有外层事务 | 追踪最外层提交与回滚；回滚不派发，提交后仍有故障窗口 | 内层方法返回等于已提交；requires_new 等于全局提交 | `examples/transactions.rb` |
| 同步分页响应缺页，旧资产不为空 | 拒绝不完整快照，保留旧数据；区分完整性与新鲜度 | rescue 后返回 [] 再清空本地 | 项目目标数据库与坏快照回归；本包未提供 DB 同步实现 |
| A 请求晚到、B 在 loading 或已成功 | commit、error、finally 都检查归属；callback 不先写状态 | 只丢弃返回值或只 abort | `examples/vue-state.mjs` |
| 供应商刷新导致表单清空 | 分离选项、服务器记录、草稿和初始化事件 | watch 整个 props 后 reset；无条件更新 lock_version | 教学 watcher + 项目真实编辑器用例 |
| 把编辑表单从 ref 改成 shallowRef | 检查嵌套 v-model；验证 computed/DOM 是否更新 | “对象大，所以一定更现代” | 深浅响应式教学检查 |
| 用 filter_map 重写 map.compact，结果包含 false | 指出行为变化并保留 false 契约 | 更短就合并 | Ruby 假值用例 |
| 列表只加载 20 条，显示总未读 150 | 总量取服务端或可靠完整数据；事件与 HTTP 对账 | 从当前页计算全量总数；任意 ISO 字符串比较 | 源码检查 + 分页外事件测试 |
| 新建简单资源，现有 Rails model/controller 已够用 | 最小 CRUD、项目原语、适用的权限/验证 | 强制 service/repository/state machine/outbox | 检查变更是否有真实职责收益 |
| 调整 Vue 按钮间距 | 读现有组件/token，验证对应布局 | 发起数据库/安全/发布全审计 | 检查范围和浏览器证据 |
| 非 Motor 项目用 Element Plus、Minitest、cursor 分页 | 沿本项目契约；只迁移决策方法 | 要求 Arco、RSpec、Motor 权限键或 envelope | 检查方案中是否出现无来源的约定 |
| 远端操作超时，用户要求重试 | 查询/复用业务幂等键，保留未知结果语义 | 直接标失败并生成新键重放 | 远端替身 + 真实协议边界说明 |

## 执行教学检查

结构检查使用 Python 3.9+ 与 PyYAML：`python3 scripts/check_skill.py /path/to/rails-vue-engineering`。它校验 frontmatter、UI 元数据、本地文件与标题引用；不校验外部链接内容或指导效果。

前提：已有 Ruby 3.2+、Minitest 5、支持 `after_all_transactions_commit` 的 Active Record、Active Job 和 sqlite3；已有 Node、Vue、TypeScript。使用目标工程的兼容版本，不为验收修改其锁文件。

```sh
python3 scripts/check_examples.py --ruby /path/to/ruby --node-modules /path/to/node_modules
```

脚本缺依赖即失败，不静默跳过；SQLite 仅验证事务回调顺序，不证明 PostgreSQL 锁或生产队列行为。Vue 检查验证响应式与可控异步，不证明真实浏览器可访问性。自行评阅这些场景也不等同于独立 Codex 行为验收。
