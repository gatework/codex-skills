# 前端交互与 Arco 页面实践

处理 Vue 3、TypeScript、Arco Design Vue、Pinia、Router、Axios、响应式、主题、i18n、页面重构和前端审查时读取本文件。

设计依据见 [Arco 设计基础](arco-design-foundations.md)：先用价值观和原则判断任务，再用本文件选择实现模式。请求/状态/表单/Drawer 的具体代码形状见 [code-patterns.md](code-patterns.md) 的 F1–F6。

## 目录

- [页面首先是业务编排，不是组件演示](#页面首先是业务编排不是组件演示)
- [状态放在哪里](#状态放在哪里)
- [API 层](#api-层)
- [Query State 单一来源](#query-state-单一来源)
- [Request State 按状态机处理](#request-state-按状态机处理)
- [Mutation Convergence](#mutation-convergence)
- [表单值与 API Payload](#表单值与-api-payload)
- [Drawer/Modal 生命周期](#drawermodal-生命周期)
- [权限能力集中化](#权限能力集中化)
- [身份变化后的收敛](#身份变化后的收敛)
- [Table 与响应式](#table-与响应式)
- [Arco 组件使用](#arco-组件使用)
- [配置面与持久化偏好](#配置面与持久化偏好)
- [主题与设计 Token](#主题与设计-token)
- [i18n、无障碍与文案](#i18n无障碍与文案)
- [大 SFC 拆分](#大-sfc-拆分)


## 页面首先是业务编排，不是组件演示

优先复用 Motor 当前页面骨架、共享组件、design token 和 API 模式。

典型管理页保持清晰层次：

1. `PageContainer` / 页面标题和用途；
2. 筛选与主操作；
3. 数据摘要；
4. table/list；
5. pagination；
6. create/edit/detail drawer；
7. destructive confirmation；
8. loading/error/empty/permission 状态。

页面只保留一个最重要 CTA，次要操作降级。

## 状态放在哪里

按顺序选择：

1. 页面/组件私有 `ref/reactive`；
2. 多组件或多个页面内复用的 composable；
3. 跨路由、会话级或需要长期共享的状态才进入 Pinia。

不要把每个列表都塞进全局 Store，也不要在 Store 保存可以由已有 state 计算出的重复数据。

## API 层

- HTTP 请求和类型放 `src/api/`；
- 页面不重复拼 Authorization、Accept-Language；
- 页面使用项目 `ApiResponse<T>`，不依赖 Axios 原始 response shape；
- 需要局部业务错误处理时使用现有 `skipGlobalErrorMessage` 等能力，避免同一错误 toast 两次；
- 业务分支优先稳定后端 `error.code`，`message` 用于用户展示，不用字符串匹配错误文案决定逻辑；
- 修改字段时同步后端 serializer、前端 API type、表单/表格和测试。

## Query State 单一来源

把远程列表请求的输入看作一个 query state：

```text
filters + search + sort + page + perPage
```

规则：

- 页面显示、URL（若项目采用）、请求参数从同一 state 推导；
- 筛选/搜索条件变化通常将 page 重置为 1；
- 删除当前页最后一条后使用项目已有 `pageAfterRemoval` 等规则修正页码；
- 不让 table 内部分页、页面 ref 和 API 参数各维护一份 current page；
- 快速连续改变 query 时只有最新请求可以提交数据状态。

## Request State 按状态机处理

至少区分：

- idle；
- loading；
- success；
- empty；
- error；
- mutating。

`loading=false` 不足以表达 error 与 empty。

### 最新请求语义

`latestExecution` 一类 guard 只在“提交响应”之前判断才有效。

错误形状：

```ts
await execute(async () => {
  const response = await api();
  rows.value = response.data;
});
```

即使 `execute` 最后丢弃旧返回值，callback 已经改写 state，旧请求仍可覆盖新请求。

正确方向：

```ts
const response = await execute(() => api());
if (!response) return;
rows.value = response.data;
```

或由共享 composable 明确接管“request -> latest check -> commit”。不要把有 reactive side effect 的 callback 误认为安全请求函数。

## Mutation Convergence

create/update/delete/status change 成功后必须定义页面如何回到权威状态：

- 服务端返回完整更新资源时可局部更新；
- 变更影响排序、过滤、计数、权限或派生字段时优先 refetch；
- 删除最后一条修正 page 后再拉取；
- mutation 失败保留用户输入和可重试上下文；
- 独立行操作使用独立 submitting/disabled，避免一个按钮让整张表不可用。

不要默认 optimistic update。只有回滚简单、冲突语义清晰、服务端拒绝概率低时使用。

## 表单值与 API Payload

页面表单模型应服务于 UI，不必强行与后端 payload 完全同形。

当 shape 不同时，使用局部纯函数表达：

```text
API -> decode -> FormModel -> encode -> API Payload
```

适合 codec 的情况：

- 日期/时间；
- 多选对象与 ID 数组；
- 可选空值；
- 标签/字典显示对象；
- 分组字段；
- server enum 与 UI option。

codec 应纯且可测试，明确哪些转换有损；不要求包含服务端默认值或隐藏秘密的转换完全可逆。不要在 drawer submit handler 临时拼十几个字段。

只有多个真实模块重复同一 schema/codec 机制后，才考虑更通用抽象。不要因为外部 Vue 管理后台提供 schema form，就在 Motor 引入大型表单引擎。

## Drawer/Modal 生命周期

Create/Edit/Detail 的状态至少明确：

```text
closed -> opening/loading -> ready -> submitting -> success/failed -> closed
```

规则：

- edit/detail 打开时避免显示上一条记录的残留；
- close 后按产品要求清理或保留该编辑会话；只在新会话/切换对象/明确放弃时初始化，不因选项列表或同 ID props 刷新覆盖草稿；
- 附件更新只合并其负责的元数据；吸收 lock_version 前确认来自当前编辑会话且其他字段未发生外部变更，不能绕过并发编辑冲突；
- 请求晚到时不得写入已关闭或已切换记录的表单；
- create/edit 可共享表单组件，但 mode/initial data/submit semantics 必须明确；
- 高风险操作不用普通 drawer 保存按钮伪装成无害更新。

## 权限能力集中化

借鉴成熟后台“统一 ability/access API”的机制：

- 页面/按钮优先调用项目既有 `usePermission` 或统一 helper；
- route meta 与 menu projection 引用相同后端 permission key；
- 不在十几个组件散落 `permission_names.includes(...)` 的不同变体；
- 复杂条件可在页面形成语义化 computed，例如 `canResetPassword`，但根权限仍来自统一能力层；
- 前端拒绝不替代后端授权。

## 身份变化后的收敛

role switch、impersonation start/stop、logout、用户失效后检查：

1. token/user/permission state；
2. 当前 route 是否仍允许；
3. tabs/cache 是否包含旧权限页面；
4. 当前页面数据是否需要刷新；
5. Cable/notification subscription 是否需要重建；
6. 已发起旧身份请求晚到时是否会污染新身份状态。

身份变化是一个状态迁移，不是单纯替换 token。

## Table 与响应式

- 默认先使用 Arco Table 原生能力；
- 列定义保持稳定，不在 render 周期中无意义重建；
- 自定义 cell slot 只处理展示，不藏复杂业务流程；
- 操作列控制宽度，常用操作直接显示，其余可进入 dropdown；
- 窄屏优先横向滚动、隐藏次要列或卡片化，不能把所有列压到不可读；
- 空状态、失败重试不依赖 table 自身“无数据”一个状态解决全部。

## Arco 组件使用

如果不确定 API，优先查当前 `@arco-design/web-vue` 官方文档或官方 skill/source，不从其他框架或其他语言绑定的记忆推断 Vue API。

保持：

- `<script setup lang="ts">`；
- Vue `v-model` / `v-model:*` 受控语义；
- Arco Vue 事件、slot、form/table/drawer 原生能力；
- 不引入第二套 UI 组件库解决一个已有 Arco 能力能解决的问题。

## 配置面与持久化偏好

Motor 已有较完整的全局 UI preference。新增 setting 前先区分“业务必要状态”和“可选外观偏好”。

新增全局 preference、localStorage key 或服务端 settings 字段前必须回答：

- 是否存在至少一个真实用户场景需要切换，而不是所有人都可接受同一默认值；
- 该设置是否与现有 density/layout/contentWidth/tab/theme 能力重复；
- 默认值、服务端同步、旧缓存迁移、reset、i18n 和版本兼容如何处理；
- identity switch/logout 后该状态是否需要重载或清理；
- 持久化是否必须进入 `users.settings`，若是必须走现有 account settings API 和 `Motor::UserSettings` 聚合语义。

能用正确默认值解决时，不增加新的长期配置面。页面局部 UI state 不因“用户可能想记住”就自动提升为持久化 preference。

## 主题与设计 Token

- 主色、背景、文字、边框、圆角、字体、间距使用 `--motor-*`；
- 页面只定义局部布局，不再造主题变量；
- 不固定覆盖 Arco 圆角/字体而绕过用户偏好；
- hover/active/focus/disabled 成套验证；
- 状态不用仅颜色表达；
- light/dark、暗色侧栏/顶栏都检查对比度。

## i18n、无障碍与文案

- 用户可见业务文案进入 `zh-CN` 和 `en-US`；
- locale key parity 保持一致；
- 时间/数字用 locale-aware 格式化；
- icon-only control 有可访问名称（如 `aria-label`）；tooltip 是否提供名称需核对实际组件，不能默认等价；
- keyboard 可以完成主要操作；
- focus ring 不移除；
- error/retry 告诉用户“发生什么、下一步做什么”，不展示 Axios object/status dump。

## 大 SFC 拆分

满足下列任一信号再拆：

- 有独立业务生命周期；
- 有独立 async state；
- 同一区块出现第二个调用方；
- drawer/form 可以独立测试；
- 一个文件同时承担 profile、安全、token、session、通知等多个领域。

拆分后页面仍负责 orchestration，不把业务流程散到无主组件中。
