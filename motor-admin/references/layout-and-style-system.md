# 样式与布局方法论

编写或审查页面布局、滚动、间距、排版、状态区、响应式和样式代码时读取本文件。它把分散在 Arco 设计基础、页面模式与体验基线中的判断，收敛为一套可推导的方法和可复用的配方。

分工：设计依据（价值观、原则、色彩、文案）见 [arco-design-foundations.md](arco-design-foundations.md)；页面骨架与工作区的取舍见 [frontend-ui-patterns.md](frontend-ui-patterns.md)；组件语言、动效与浏览器验收见 [frontend-experience.md](frontend-experience.md)。本文件负责“怎么落成样式和结构”。

**使用边界**：下面的类名、`--motor-*` 变量名和组件 props 均为形状示例。实现前到 `src/assets/style/`、`PageContainer` 与同类页面里找到现有 Token 和写法并沿用；Arco Vue 的组件 API 以当前 `@arco-design/web-vue` 官方文档为准。

## 目录

- [三个所有权](#三个所有权)
- [信息优先级决定结构](#信息优先级决定结构)
- [页面骨架配方](#页面骨架配方)
- [数据工作区与可用高度](#数据工作区与可用高度)
- [Tree + Table 双栏](#tree--table-双栏)
- [工具条与操作层级](#工具条与操作层级)
- [状态区：不让页面跳动](#状态区不让页面跳动)
- [排版、数字与截断](#排版数字与截断)
- [表面、间距与视觉克制](#表面间距与视觉克制)
- [响应式策略](#响应式策略)
- [动效与降级](#动效与降级)
- [样式代码规范](#样式代码规范)
- [布局审查清单](#布局审查清单)

## 三个所有权

大多数布局问题（双滚动条、内容被撑破、高度魔法数字）都是“谁负责什么”没说清。对每个页面回答三个问题：

| 所有权 | 问题 | 原则 |
| --- | --- | --- |
| **滚动所有权** | 谁负责主要的纵向滚动？ | 一个页面只有一个主要纵向 scroll owner。出现“页面滚动 + 卡片滚动 + 表格滚动”三层时，重构结构，不再调高度 |
| **尺寸所有权** | 谁决定这个区域的宽高？ | 父级决定可用空间，子级在其中收缩或增长；用 flex/grid 表达，不用测量出来的固定数值 |
| **间距所有权** | 谁负责元素之间的留白？ | 由容器用 `gap` 统一负责，子元素不各自加 `margin`；组内紧密、组间适当分离 |

结论式规则：能用布局关系表达的，不写死数值；必须写数值时，来自 Token 或间距刻度（4/8 系列），并说明来源。

## 信息优先级决定结构

结构先按用户扫描顺序排，再谈视觉：

1. **对象与范围**：当前在管理什么、范围是什么；
2. **状态与风险**：数据是否新鲜、有无异常；
3. **可执行操作**：一个主 CTA，其余降级；
4. **数据本身**：表格/列表/详情；
5. **辅助工具**：刷新、导出、列设置、设置入口，安静、统一尺寸、不抢视觉中心。

“第一眼能否知道当前对象、当前状态和下一步操作”是最终验收问题。

## 页面骨架配方

```vue
<template>
  <!-- PageContainer 的 props/slot 以当前源码为准 -->
  <PageContainer title="…" description="只补必要的业务边界">
    <template #extra><a-button type="primary">主操作（一屏只强调一个）</a-button></template>

    <section class="workspace">
      <header class="workspace__filters">…高频 1~3 个条件默认可见，低频进入“更多”…</header>
      <div class="workspace__toolbar">
        <span class="workspace__summary">结果摘要（范围要和筛选对得上）</span>
        <span class="workspace__tools">…次要工具…</span>
      </div>
      <div class="workspace__body">
        <!-- loading / error / empty / success 共用这个区域，保持骨架稳定 -->
      </div>
      <footer class="workspace__pager">…</footer>
    </section>

    <!-- create / edit / detail 使用 Drawer，保留列表上下文 -->
  </PageContainer>
</template>
```

- Header 负责定向，不承载全部工具；标题说明“管理什么”，description 只补必要边界。
- filters、summary、toolbar、table 在视觉与滚动上属于同一个任务，不各自包成同等级的阴影卡片。
- 设置/详情页按业务语义分 section，不按字段数量机械分卡；相邻设置共享对齐线与节奏。

## 数据工作区与可用高度

工作区型页面（高频操作，让表格自身承担滚动）用 flex 链传递“可用高度”，链上**每一环**都要 `min-height: 0`：

```less
.workspace {
  display: flex;
  flex-direction: column;
  min-height: 0;                          // 允许子级收缩：flex 子项默认 min-height:auto，会把内容撑破
  border: 1px solid var(--motor-border-color);   // 细边框分组；Token 名以现有样式表为准
  &__filters, &__toolbar, &__pager { flex: none; }
  &__body { flex: 1 1 auto; min-height: 0; overflow: auto; }   // 唯一的纵向滚动发生在这里
}
```

文档型页面（设置、说明）不需要这套：让 app-content 滚动，页面内容自然增长。

要点：

- 先用 flex/grid 与 `min-height: 0` 与现有布局 CSS 变量解决；只有确实需要时才测量 header/footer，且测量逻辑必须处理 resize 与内容变化；
- Arco Table 的内部滚动（如 `scroll.y`）依赖确定的高度，先在真实容器里验证行为再决定是否需要测量；
- 高度魔法数字（`calc(100vh - 217px)`）是结构问题的症状，先修结构。

## Tree + Table 双栏

树是**查询上下文**，右侧是唯一的工作区：

```less
.split {
  display: grid;
  grid-template-columns: var(--aside-width, 240px) minmax(0, 1fr);   // 右栏 minmax(0,1fr)：等价于 min-width:0，防止长内容撑破
  gap: 16px;                                                          // 间距取自现有刻度
  min-height: 0;
}
@media (max-width: 767px) {
  .split { grid-template-columns: minmax(0, 1fr); }   // 窄屏不保留狭窄双栏；树转入 Drawer / Popover / 顶部筛选
}
```

选中的树节点进入统一的 query state，不复制一份独立的数据权限；刷新后的行为（URL 若采用）要可预测。只有业务确实存在层级上下文时才用 tree，不为了“像某个后台”给平面列表加树。

## 工具条与操作层级

- **页面级**：至多一个 primary（create/import）；刷新为次要；导出、批量等低频能力放 secondary 或 dropdown。
- **行级**：`一个常用操作 + More`。Edit 直接显示；Reset、Impersonate、Delete 等低频或高风险动作进 More，用 permission / disabled / reason / confirm 表达边界。不要一行并排 5~8 个文字按钮。
- **危险操作**与普通保存在视觉和确认语义上分开；是否需要确认取决于影响程度，可逆动作不逐个加确认。
- **图标**：优先沿用项目已有图标家族和大众可识别的隐喻，不为差异化自创图标；icon-only 控件必须有 `aria-label`（Tooltip 不能替代）；选择菜单已打开时不重复显示 Tooltip。

## 状态区：不让页面跳动

每个数据面覆盖 loading、可见 error + retry、empty、success、mutating、只读/无权限、窄屏与必要的深浅主题。

```less
.state { min-height: 240px; display: flex; flex-direction: column; align-items: center; justify-content: center; }
// 各状态共用同一个占位容器，切换时区域高度不变，用户不会看到页面抖动
```

- **loading**：保留工作区上下文（筛选、工具条不消失）；局部加载不让整页跳动。
- **error**：说明失败对象、影响与下一步，提供可见的 retry；刷新失败时保留已有内容并显示失败提示，不清空。
- **empty**：区分“没有数据”与“筛选后无结果”，后者提供清除筛选；缺失值不显示成真实的 0。
- **mutating**：行级独立 submitting/disabled，一个按钮不能让整张表不可用。
- **无权限/只读**：说明原因，不只是隐藏。

## 排版、数字与截断

- 字体、字号、字重、行高先取现有 Token；一个小范围内最多保持“标题 / 正文 / 辅助”三种文字角色。
- 关键可读信息 12px 为最低设计参考；不通过继续缩小字号解决换行，而是精简文案、调整可用宽度或改变响应式策略。
- 数量、时间、百分比使用等宽数字对齐（`font-variant-numeric: tabular-nums`）和 locale-aware 格式化；IP、序列号、端口、ID 按原值显示，不加千分位。
- 截断关键标识时必须提供完整查看或复制路径：

```less
.cell-ellipsis { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
// 配合 title / Tooltip / 复制按钮；表格、按钮、长文本不共用一个强制行高
```

- 缺失、未知、零值分别处理：缺失显示占位符，不显示成 0。

## 表面、间距与视觉克制

- **表面**：页面背景、工作区背景、浮层背景使用现有层级 Token；用背景层级和细边框分组。阴影只表达真实的 elevation（Dropdown、Popover、Drawer），不给普通内容块统一加阴影。
- **间距**：使用统一的 4/8 系列刻度，不在页面里另建刻度；对齐线与阅读顺序比堆叠容器更重要。
- **颜色**：主色只强调选择、主要动作和焦点；中性色承担大多数结构；状态色跨页语义一致，且配有文字或图标，不只依赖颜色。深浅主题保持同一信息层级，不把暗色处理成纯黑反相。
- **圆角与装饰**：圆角随组件职责变化，不把所有容器做成大圆角卡片；避免装饰性渐变、厚边框、强阴影、营销页式布局。
- **辅助入口**：设置、关闭、工具按钮不得抢占视觉中心。用位置、分组、轻微颜色、hover、分隔线建立层级，而不是放大尺寸或加重色块。
- **交付前比较**：把新元素放回同屏，与相邻元素比较视觉重量和信息密度；显得突兀、过大、过重或破坏密度，就先收敛再交付。

## 响应式策略

不要把桌面表格简单缩小。按信息优先级选择策略：

| 情况 | 策略 |
| --- | --- |
| 关键列少、信息可横向扫描 | 保留关键列并允许表格内横向滚动（页面本身不出现横向滚动） |
| 次要列可从详情获得 | 窄屏隐藏次要列 |
| 高频移动场景 | 业务卡片视图 |
| 复杂 tree / 筛选 | 进入临时 overlay（Drawer / Popover / 顶部选择） |
| Header extra 过多 | 自然换行，主操作仍可发现 |

至少检查三档：桌面、约 768~1120px 的中间宽度、375px 手机宽度。页面的 `scrollWidth` 不得大于 `clientWidth`；触控目标不因图标视觉小而缩小热区；安全区域、虚拟键盘、Footer、长语言文本不能遮挡操作。容器查询、逻辑属性等较新的 CSS 能力，先对照项目的浏览器支持策略再采用。

## 动效与降级

动效先回答“它解释了什么状态变化”，答不出就不加。

| 场景 | 参考时长 |
| --- | --- |
| 按压反馈 | 约 120~180ms |
| hover / 颜色变化 | 约 160~220ms |
| Dropdown / Popover 进出 | 约 150~240ms |
| 小范围披露（能感知空间来源时） | 约 240~500ms |

这是设计参考区间，不是硬规格，最终以现有组件和浏览器实测为准。

```less
.control { transition: color 0.18s, background-color 0.18s, border-color 0.18s; }   // 显式属性，不写 transition: all
@media (prefers-reduced-motion: reduce) {
  .control { transition: none; }
}
```

- 同一个控件只保留一个主反馈，不同时旋转、发光、弹跳和扩散；动画中的图标不能改变按钮占位尺寸。
- 只有边界明确、低频、短距离的披露控件才允许动画宽度；普通页面布局不用 width/height 动画。
- 键盘触发、`prefers-reduced-motion` 或不支持某能力（如 View Transition）时，直接切换状态。
- `hover` 不能替代 `:focus-visible`；焦点样式清晰但不成为永久装饰。

## 样式代码规范

- 使用 scoped Less 与 `--motor-*` Token；页面只定义局部布局，不重新定义主题变量，不固定覆盖 Arco 的圆角、字体而绕过用户偏好。
- 状态成套验证：hover / active / focus-visible / disabled / selected；深浅主题（含暗色侧栏、顶栏）都检查对比度。
- 覆盖 Arco 内部样式用最小范围 `:deep()` 并写明原因；避免 `!important`。
- 命名沿用同目录已有风格（如 BEM 风格的 `block__element`），不在同一文件混用两种。
- 不使用 `transition: all`；不用 `z-index: 9999` 解决层叠问题，遵从既有层级约定。
- 一次页面微调优先局部实现；已稳定的共享组件不为单页效果而被全局破坏。
- 不引入 utility CSS 体系、第二套 UI 库或外部布局框架。

## 布局审查清单

- 是否只有一个清晰的主任务和一个主 CTA？
- 是否只有一个主要纵向 scroll owner？flex 链上每一环都有 `min-height: 0` 吗？
- filters → summary → toolbar → table 是否在视觉上连续，而不是碎成多个同级卡片？
- loading / error / empty / permission 是否保留页面上下文，且切换时结构不跳动？
- 行操作是否按频率和风险分层？
- 长文本、长标识是否可截断且可完整查看？数字是否对齐？
- 桌面、中间宽度、375px、light/dark 是否都可用？`scrollWidth ≤ clientWidth` 吗？
- 是否只使用 Motor Token 与 Arco Vue 原语？借的是机制，不是外部框架？
- 是否在真实浏览器里验证过（不是仅 build 通过）？验收矩阵见 [frontend-experience.md](frontend-experience.md#浏览器验收)。
