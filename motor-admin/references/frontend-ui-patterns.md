# Motor 管理端页面与工作区模式

处理 Arco Design Vue 页面样式、页面骨架、CRUD 工作区、筛选与表格、tree-table、Drawer、响应式和视觉一致性时读取本文件。Vben Admin 与 Arco Design Pro Vue 只作为 Vue 管理端机制参考，最终实现必须服从 Motor 当前代码和 Arco 原语。

设计依据见 [Arco 设计基础](arco-design-foundations.md)。本文件负责页面骨架与工作区的**取舍判断**；滚动、间距、状态区与响应式的具体样式配方见 [layout-and-style-system.md](layout-and-style-system.md)。

## 目录

- [参考顺序](#参考顺序)
- [先判断 Motor 已经有什么](#先判断-motor-已经有什么)
- [高价值机制](#高价值机制)
- [稳定页面骨架](#稳定页面骨架)
- [连续数据工作区](#连续数据工作区)
- [滚动所有权与可用高度](#滚动所有权与可用高度)
- [筛选与查询节奏](#筛选与查询节奏)
- [操作层级](#操作层级)
- [表格能力按需要增加](#表格能力按需要增加)
- [Tree + Table](#tree--table)
- [Drawer 与长表单](#drawer-与长表单)
- [视觉克制](#视觉克制)
- [响应式](#响应式)
- [明确不搬的东西](#明确不搬的东西)
- [页面审查清单](#页面审查清单)

## 参考顺序

实现层只沿同栈链路参考：

1. Motor 当前页面、共享组件和 design token；
2. Arco Design Vue 官方组件语义；
3. Arco Design Pro Vue 的 Arco 页面组织；
4. Vben Admin 的 Vue 管理端交互机制；
5. 其他成熟 Vue 3 项目。

外部项目用于回答“这个后台交互为什么更稳定”，不是用于复制组件封装和依赖。

## 先判断 Motor 已经有什么

改页面前先搜索现有能力。Motor 已有全局 layout/preferences、`PageContainer`、Arco Table/Drawer、移动端策略、权限 helper、pagination/request state 等时，不因为竞品也有同名能力再造一份。

尤其避免重复新增：

- 页面独立 density setting；
- 表格独立 fullscreen/zoom，若全局内容全屏已满足；
- 第二个 Page shell；
- 第二套 token/radius/font preference；
- Vben 式 schema form/grid adapter；
- 新 UI library。

## 高价值机制

默认值得借鉴的是机制，不是皮肤：

**P1，通常适用**
- 稳定 page header/workspace/footer 骨架；
- 单一主滚动所有权；
- 筛选、摘要、toolbar、table/list 连续成一个数据工作区；
- 一个主 CTA，次要动作降级，行操作压缩；
- loading/error/empty 不让页面结构大幅跳变；
- 用 spacing、typography、border、background step 建层级，少用装饰 card/shadow。

**P2，有真实场景才采用**
- 折叠高级筛选；
- 可占满剩余高度的 table workspace；
- tree + table 双栏；
- 列显隐/顺序配置；
- sticky drawer/form footer。

**P3，默认拒绝**
- 外部 Grid/schema/adapter/preferences 体系；
- 为统一外观包装全部 Arco 组件；
- utility CSS 或 monorepo 结构迁移；
- 没有业务依据的可配置项。

## 稳定页面骨架

管理页面默认理解为：

```text
PageContainer
  Header: title / description / primary action
  Optional filters or context
  Workspace
  Optional page/form footer
```

Header 负责定向，不承载全部工具。标题说明“这里管理什么”，description 只补必要业务边界。主操作放右侧或自然首要位置，一屏只强调一个。

Workspace 根据业务选择：

- 文档/设置页：内容自然滚动；
- 列表页：filters + summary/toolbar + table/list；
- 高频操作页：必要时占满可用高度，让 table 自身承担数据区滚动。

不要把 header、summary、filters、table 分别包成多个同等级 shadow card，导致层级碎裂。

## 连续数据工作区

高频列表页优先形成连续工作区：

```text
filters
results summary + toolbar
-------------------------
table/list
pagination
```

关键不是必须放在一个 `a-card`，而是视觉和滚动上属于同一任务。

判断标准：

- 用户从查询到操作是否需要跨多个视觉容器寻找控制；
- table 与 toolbar 是否看起来属于同一数据集；
- loading/error/empty 是否仍保留工作区上下文；
- 列表摘要是否真正帮助用户理解结果，而不是为了“有卡片”增加装饰。

## 滚动所有权与可用高度

一个主要页面只设一个主要纵向 scroll owner。

常见安全模型：

**文档型**
```text
app-content scroll
  page content grows naturally
```

**工作区型**
```text
app shell fixed height
  page header/filter fixed by flow
  data workspace min-height: 0
    table body scroll
```

出现 `page scroll + card scroll + table scroll` 三层滚动时优先重构结构，不用继续调高度 magic number。

实现工作区式高度时先使用 flex/grid `min-height: 0` 和现有 layout CSS variable；只有确实需要时才测量 header/footer，高度逻辑必须有 resize/内容变化策略。

## 筛选与查询节奏

筛选区按使用频率分层：

- 高频 1 到 3 个条件默认可见；
- 低频条件进入“更多/高级筛选”；
- Search/Reset 不与主业务 CTA 争夺视觉权重；
- 条件变化是否自动查询由请求成本和用户预期决定，不机械 `submitOnChange`；
- 快速自动查询要 debounce/cancel/latest-commit，避免旧响应覆盖。

筛选值、URL（若项目使用）、query state 与请求参数只保留一个权威来源。

## 操作层级

### 页面级

- create/import 等核心业务动作：至多一个 primary；
- refresh：icon/text secondary；
- export、bulk、其他低频能力按真实业务需要放 secondary/dropdown。

### 行级

优先：

```text
primary row action + More dropdown
```

例如 Edit 常用就直接显示，Impersonate/Reset/Delete 等低频或高风险动作进入 More，并用 permission/disabled/reason/confirm 表达边界。

不要一行并排 5 到 8 个 text button。

## 表格能力按需要增加

Motor 已有全局 density/layout/fullscreen 类能力时，不默认给每张 table 再加设置。

### Density

只有同一业务确实需要独立于全局密度调节，才提供 table density；否则服从全局 preference。

### 列设置

满足这些信号再考虑：

- 10+ 列且角色关注字段不同；
- 列宽导致频繁横向滚动；
- 用户需要长期保存自己的工作列集。

简单 5 到 8 列 CRUD 不需要 column settings。

### Fullscreen

先复用 Motor content fullscreen。只有 table 需要和页面其余元素分离全屏且存在高频价值时再新增局部能力。

## Tree + Table

部门、分类、资源组等层级筛选适合：

```text
+----------------+---------------------------+
| tree/context   | filters + toolbar + table |
+----------------+---------------------------+
```

规则：

- tree 是 query context，不复制一份独立数据权限；
- selected node 进入统一 query state；
- 左栏宽度稳定，右栏 `min-width: 0`；
- 小屏不要保留狭窄固定双栏，tree 可进入 Drawer/Popover/顶部筛选；
- 选中 tree 后结果、URL（若采用）与刷新行为要可预测。

只有业务确实存在层级上下文时采用，不为了“像 Vben”给平面列表增加 tree。

## Drawer 与长表单

Drawer 适合创建、编辑、详情这类保留列表上下文的任务。

保持：

- 打开新记录前清理旧 record/form/error state；
- edit/detail loading 与 ready 分开；
- late response 不能写入已关闭或已切换的 Drawer；
- 长表单按业务语义分 section，不按字段数量机械分卡；
- submit footer 在长表单中可 sticky，但不能挡住错误信息和最后字段；
- destructive action 与普通 Save 视觉和确认语义分开；
- 手机宽度优先全宽或接近全宽，并验证键盘/滚动。

## 视觉克制

成熟企业后台的“高级感”主要来自秩序，不来自装饰数量。

默认优先：

- 4/8 类统一 spacing scale；
- 稳定 title/body/secondary hierarchy；
- surface 通过背景层级和细边框区分；
- shadow 只表达真实 elevation；
- primary color 只强调 selection/action/focus；
- 数据对齐、数值和时间格式稳定。

审查现有 `PageContainer` 或页面局部设计时问：

- icon box 是否真的传达业务信息；
- gradient/shadow/card 去掉后层级是否仍成立；
- 多个卡片是否只是模板化包装；
- 用户第一眼能否知道“当前对象、当前状态、下一步操作”。

不要为了追求竞品视觉直接复制颜色、圆角、阴影值。Motor token 是最终来源。

## 响应式

不要把桌面 table 简单缩小。

按信息优先级选择：

1. 保留关键列并允许横向滚动；
2. 隐藏可以从详情获得的次要列；
3. 高频移动场景采用业务卡片；
4. 复杂 tree/filter 进入临时 overlay；
5. page header extra 在窄屏自然换行，primary action 仍可发现。

已有 Motor 用户/角色等页面采用 mobile card 时，优先复用其交互思想，不为了统一 table 形式删除正确的移动端体验。

## 明确不搬的东西

从 Vben/其他 Vue 后台不搬：

- `useVbenVxeGrid` 或同类 Grid abstraction；
- schema-driven Form 作为全项目默认；
- 外部 Drawer/Modal API wrapper，只因其“更统一”；
- Vben preferences 全量配置；
- 外部 Tailwind/utility CSS 体系；
- 动态 route/access 架构替代 Motor 当前 permission 投影；
- 外部 monorepo/package 分层。

先证明 Motor 当前代码存在重复且第二个真实调用方已经出现，再考虑本地小抽象。

## 页面审查清单

交付前快速检查：

- 页面是否只有一个清晰主任务和主 CTA；
- title/description/filters/toolbar/table 的层级是否连续；
- 是否存在不必要 card、icon box、shadow 或重复 preference；
- 是否只有一个主要纵向 scroll owner；
- query、pagination、mutation 是否回到同一权威状态；
- loading/error/empty/permission 是否保留页面上下文；
- 行操作是否按频率/风险分层；
- desktop、窄屏、light/dark 是否都可用；
- 是否只使用 Motor token 与 Arco Vue 原语；
- 是否借了“机制”，而没有把外部框架架构搬进项目。
