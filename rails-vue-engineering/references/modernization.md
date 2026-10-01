# 现代化写法：先证明语义，再缩短表达

用于语法升级、命名与风格重构。版本支持、项目约定和公开契约先于个人喜好；工具自动修复也要审阅 diff。

## Ruby / Rails

| 触发 | 判断与推荐 | 边界与验证 |
| --- | --- | --- |
| `map.compact` → `filter_map` | 后者丢弃 `false` 和 `nil`，前者仅丢弃 `nil` | 只有 `false` 不属于合法结果时等价；测试 `false/nil/0/空串`。 |
| `x && x.foo` → `x&.foo` | `&.` 只短路 `nil`，不短路 `false` | 查 receiver 协议、调用次数、返回值，不能全仓替换。 |
| 使用 `||=` 缓存 | 仅适合假值需要重新计算的情况 | 合法 `false/nil` 缓存用存在性判断；测试第二次读取和副作用次数。 |
| `Data.define` 或 Struct 值对象 | 有稳定字段与值语义时采用目标版本支持的能力 | Data 不深冻内部 Array/Hash；明确复制/冻结边界，测试原输入被修改后结果是否受影响。 |
| 关键字省略、`...`、匿名转发、简写 block | 在最低支持版本可解析、减少重复且意图清楚时采用 | 保留 positional hash、keyword、block、private/public 与扩展 hook；用真实调用方式验证。 |
| guard clause、单行方法 | 平坦流程通常更易读 | 检查返回值、`ensure`、事务块 `return/break/next` 和 callback 中止语义，不以减少缩进证明等价。 |
| `present?` / `compact_blank` 归一化 | 用于业务确实把这些值视为空时 | `false` 是 blank；权限开关、外部配置和 patch 字段要分别处理缺失/空/false。 |
| `update_all` / `upsert_all` 批量优化 | 适合明确绕过对象生命周期的批量写 | 核对 validation、callback、审计、时间戳、锁版本及受影响行数，不能仅以速度替代语义。 |

命名表达职责：谓词用 `?`，抛错的校验遵循项目现有 `validate_*!` 等约定，bang 的失败/变更语义与同类 API 一致。不要为了统一动词重命名稳定 job 类、权限键或公开接口。

Rails 中业务时间按应用时区处理；持续时间与 timeout 需要单调时钟时不要机械改成墙上时钟。不要把时间工具当格式偏好。

## TypeScript / Vue

| 触发 | 判断与推荐 | 边界与验证 |
| --- | --- | --- |
| 外部 JSON 声明为接口 | 类型仅检查编译期代码；需可信边界解析 `unknown` | 泛型 `ApiResponse<T>`、`as T`、`satisfies` 都不验证远端 JSON。按风险与既有工具选择运行时校验，不强制引入 schema 库。 |
| `||` → `??` | 后者仅对 `null/undefined` 回退 | `0/false/''` 行为会改变；先明确期望再选写法。 |
| `satisfies`、`as const`、字面量联合 | 适合配置键约束和有限状态 | `as const` 不冻结运行时对象；有插件扩展的集合不能强制穷举。 |
| 判别联合与 `never` | 对真正互斥的分支暴露漏处理 | 不把并行的查询、提交、连接状态硬合成单一阶段；测试合法组合。 |
| `import type` | 在项目编译配置要求下区分类型和值 | 运行时类、enum、反射/装饰器可能需要值导入；运行构建确认。 |
| props 解构、`defineModel` | 先确认 Vue 与 SFC 编译器版本，以及受控状态协议 | `defineModel` 的默认值可能让父子状态不同步；测试父值未传、父更新、子输入与 emit。 |
| watcher cleanup | 生命周期内注册清理，取消订阅并使旧结果失效 | Vue 3.5 的 `onWatcherCleanup` 需在同步阶段调用；参数式 `onCleanup` 按目标版本语义使用。 |
| `reactive` → `shallowRef` | 按整体替换协议选择 | 嵌套字段 v-model 通常需要深层跟踪，见 [Vue](vue.md)。 |

严格类型的目标是暴露错误假设；局部与第三方互操作确需断言时，说明为何可信、把断言限制在边界，不用新增 `any` 掩盖未理解的数据。

## 实施步骤与证据

先找调用者和受支持版本，再选择少量有收益的改写。保持接口与行为时，将原实现和候选实现放入同一输入矩阵比较。观察值、异常、调用次数、顺序、对象身份和外部副作用，不只比较快照文本。

[Ruby 教学检查](../examples/ruby-semantics.rb) 覆盖假值与浅不可变；[TS 请求示例](../examples/latest-request.ts) 覆盖类型与异步状态。它们是最小反例，不是要求每个项目引入相同抽象。
