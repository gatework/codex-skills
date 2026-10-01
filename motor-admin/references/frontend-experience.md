# Motor 前端体验基线

本文件用于 Motor 管理端的页面视觉打磨、截图纠偏、组件样式、微交互、登录与认证页面体验，以及明确要求参考或复刻 Vben Admin 的任务。

设计依据先读 [Arco 设计基础](arco-design-foundations.md)。本文件负责将其落实到 Motor 的 Vue 3、Arco Design Vue 和 `--motor-*` Token 体系，检查层级、控件与真实渲染。Vben 仅用于明确指定或已有组件无法解决的体验机制参考，不作为 Motor 默认视觉目标。

## 目录

- [适用边界](#适用边界)
- [事实与参考顺序](#事实与参考顺序)
- [体验主张](#体验主张)
- [页面布局](#页面布局)
- [视觉层级](#视觉层级)
- [组件语言](#组件语言)
- [动效与反馈](#动效与反馈)
- [登录与认证页面](#登录与认证页面)
- [响应式](#响应式)
- [无障碍与本地化](#无障碍与本地化)
- [工程映射](#工程映射)
- [浏览器验收](#浏览器验收)
- [禁止事项](#禁止事项)

## 适用边界

以下任务读取本文件：

- 页面显得空、乱、重、松散、主次不清或组件不协调；
- 用户提供截图并要求修复视觉、布局或交互问题；
- 新建或重构管理页面、登录页、工具条、筛选区、Drawer、表格工作区；
- 调整颜色、深浅主题、图标、hover、focus、press、展开收起或页面切换动效；
- 用户明确要求 Vben 风格、Vben 同款或 1:1 交互效果。

不因普通后端、数据模型、任务队列或 API 工作加载本文件。纯业务 correctness 仍由对应领域 reference 决定。

## 事实与参考顺序

视觉任务也必须先读取当前事实，顺序如下：

1. 用户当前截图、录屏和明确反馈；
2. Motor 当前运行页面、同类页面、共享组件与 `--motor-*` Token；
3. Arco 设计规范与当前 Arco Design Vue 组件语义；
4. Arco Design Pro Vue 的同类场景；
5. 有明确参考需要时，再读 Vben 当前运行页面和对应源码或其他成熟 Vue 3 管理产品。

当前截图优先于历史截图，真实浏览器优先于静态推断。用户说“1:1”“完全一致”时，必须同时检查参考页面的最终画面和对应源码，记录尺寸、结构、状态、时长、缓动、触发方式与降级路径，不凭训练记忆或单帧截图近似。

Vben 版本会变化。只有 Motor 已经采纳并验证的体验基线可以长期保留；声称“与当前 Vben 完全一致”前必须重新读取当时的实际源码。

## 体验主张

Motor 的前端气质是克制、紧凑、可信赖的企业网络运维工作台：

- 信息密度优先，但不拥挤；
- 层级来自位置、排版、背景层次和细边框，不依赖卡片堆叠；
- 主色只强调当前状态、主要动作和焦点；
- 工具控件安静、尺寸统一、含义明确；
- 动效解释状态变化，不作为装饰；
- 页面始终让用户知道当前对象、当前状态和下一步操作。

判断“像 Vben”时优先识别机制：稳定页面骨架、连续工作区、轻量辅助工具条、清晰图标语义、短反馈、状态收敛和自然响应式。不要把某个配色、字体、阴影或 Tailwind class 当成风格本身。

## 页面布局

### 管理数据页

默认骨架：

```text
PageContainer
  Header: title / short description / primary action
  Context or filters
  Workspace
    summary + secondary toolbar
    table / tree-table / list
    pagination
  Optional drawer or page footer
```

保持一个主要纵向 scroll owner。筛选、摘要、工具条和数据结果应看起来属于同一任务，不要分别包成多个同等级阴影卡片。

Header 负责定向，不承载全部工具。页面通常只有一个 primary CTA；刷新、导出、列设置、更多操作按频率降级。行操作优先“一个常用操作 + More”，高风险动作不与普通编辑并列强调。

### 设置与详情页

按业务语义分 section，不按字段数量机械分卡。相邻设置共享对齐线和节奏，标题只解释该区域的决策范围。长表单使用稳定 action footer，不能遮挡最后字段或错误信息。

### Tree + Workspace

树是查询上下文，右侧是唯一工作区。左栏宽度稳定，右栏必须 `min-width: 0`；窄屏将树转为 Drawer、Popover 或顶部上下文选择，不保留不可用的窄双栏。

## 视觉层级

### Surface

- 页面背景、工作区背景、浮层背景使用 Motor 已有层级 Token；
- border 只分隔真实边界，默认使用细边框；
- shadow 只表达真实 elevation，例如 Dropdown、Popover、Drawer，不给普通内容块统一加阴影；
- 同一区域避免“外层胶囊 + 内层按钮底色 + 选中环”形成双层或三层表面；
- 圆角随组件职责变化，不能为了柔和把所有容器都做成大圆角卡片。

### 排版

- 页面标题说明对象，description 只补必要业务边界；
- 小范围内最多保持标题、正文、辅助信息三种文字角色；
- 不通过缩小字号解决换行，优先精简文案、调整可用宽度或明确响应式策略；
- 数据、IP、时间、端口、序列号等保持稳定对齐和可扫描性；
- 登录页与工具条短文案默认不跨行，长语言环境需实测。

### 颜色

- `--motor-primary` 用于主操作、选择、焦点和少量品牌强调；
- 中性色承担大多数结构，避免大面积高饱和色抢夺数据；
- 状态不能只靠颜色表达，还需 icon、label、形状或可读文案；
- light/dark 中保持相同信息层级，不把暗色简单处理成纯黑反相。

## 组件语言

> **快照说明**：本节与“动效与反馈”中的具体数值（像素、时长、缓动）是 Motor 某一时点采纳 Vben 机制后的适配结果，属于运行时事实，不是永久规格。用于新任务时，先对照当前源码与运行页面复核；与现有实现冲突时以当前源码为准，并在同一变更里更新本文件。

### 辅助图标工具条

登录页、页面角落或低频偏好入口可使用 Vben 式轻量工具条。适配到 Motor 时采用以下基线：

- 工具条高度约 `40px`，单层柔和背景，`border-radius: 999px`；
- 多按钮组使用约 `4px 12px` 内边距，按钮之间默认不额外加装饰分隔；
- 图标按钮热区 `32px × 32px`，普通线性图标视觉尺寸 `16px`；
- 主题 morph 图标可使用 `18px`，但不能比相邻图标更重；
- 按钮默认透明，仅 hover 提供一层轻背景；
- 不同时叠加外框、内底色、阴影、状态点和 halo；
- 图标必须来自同一视觉家族，统一 `viewBox`、stroke、linecap、linejoin 和光学尺寸。

这些数值只用于紧凑辅助工具条，不作为所有页面按钮的全局尺寸。

### 颜色预设面板

Motor 登录页已采纳的 Vben 适配模式（数值为快照，使用前复核）：

- 触发器位于末端，颜色轨道向其一侧连续展开；
- 轨道从 `width: 0` 到 `width: 240px`，使用 `500ms ease-out`；
- 七个颜色按钮各占 `32px × 32px` 热区，内部色点为 `20px` 单层圆面；
- 当前项只显示高对比勾选，不加同色外环、白环或复合阴影；
- hover 只将色点放大到约 `1.1`，不移动整组；
- 指针离开作用域后自然收起，选择颜色时只更新权威主题偏好，不引入第二份状态；
- 键盘焦点必须能展开并选择，`prefers-reduced-motion` 时取消过渡；
- 空间不足的移动端隐藏颜色与布局入口，保留语言和主题等核心能力。

只有这种有明确边界、低频且短距离的披露控件才允许动画宽度。普通页面布局不得用 width/height 动画制造抖动。

### 布局切换

- 触发器显示当前布局图标，而不是始终显示通用 `layout` 符号；
- 左、中、右使用 PanelLeft、InspectionPanel、PanelRight 一类面板语义图标，不使用文本对齐图标代替页面布局；
- Dropdown 每项同时显示图标和短 label，当前项还需有可读选中状态；
- 选择后立即持久化并让页面收敛到同一布局状态；
- 入口尺寸和视觉重量与语言、主题按钮一致。

### Dropdown、Popover 与 Tooltip

- Dropdown/Popover 负责“选择或操作”，Tooltip 只负责解释无法单凭图标理解的静态动作；
- 点击后已经出现选择菜单时，不再在菜单上方保留重复 Tooltip；
- 登录辅助工具条中的颜色、布局、语言和主题图标在语义清楚时不显示 Tooltip，但必须保留 `aria-label`；
- 同一 hover 不同时触发提示、展开面板和按钮动画三种反馈；
- 浮层位置要避开触发器、表单标题和相邻浮层，打开后焦点、Escape 与外部点击行为使用 Arco 原语。

### 表单

- label、control、help/error 形成稳定纵向节奏；
- required、disabled、loading、error 不改变整页骨架；
- 输入前缀 icon 视觉重量低于输入内容；
- 主要提交按钮清晰唯一，辅助链接不与其争夺；
- 错误说明“发生什么、下一步做什么”，不要展示传输层异常对象。

### Table、Drawer 与状态组件

- toolbar 与 table 共享工作区边界；
- loading、error、empty、success、mutating 保持结构稳定；
- Drawer 打开新对象前清空旧状态，关闭后不接受晚到响应；
- 空状态不伪装成真实零值，失败状态提供可见 retry；
- 窄屏优先保留关键字段、横向滚动或业务卡片，不压缩到不可读。

## 动效与反馈

动效先回答“它解释了什么状态变化”。没有明确答案就不增加。

### 时长与缓动

- press feedback：约 `120ms` 到 `180ms`；
- hover 或颜色变化：约 `160ms` 到 `220ms`；
- Dropdown/Popover 进入退出：约 `150ms` 到 `240ms`；
- 小范围披露：约 `240ms` 到 `500ms`，只在用户能感知空间来源时使用；
- 页面主题扩散：`450ms ease-in`，仅用于低频主题切换。

不用 `transition: all`。显式声明 color、background-color、border-color、opacity、transform 或经过验证的单一布局属性。

### 按钮反馈

- 可操作控件应有可感知的按下反馈，优先保留 Arco 原生 active 状态；不默认给表格和工具条按钮增加 scale；
- 高频操作不使用长动画；
- hover 不能替代 focus-visible；
- 同一按钮只保留一个主反馈，不同时旋转、发光、弹跳和扩散；
- 动画中的图标不能改变按钮占位尺寸。

### 主题切换

Motor 登录页采用 Vben 式 View Transition：

1. 从 pointer click 的 `clientX/clientY` 计算起点；
2. 终点半径覆盖视口最远角；
3. 在 `document.startViewTransition` callback 中切换 Motor 的主题权威状态并等待 Vue `nextTick`；
4. 切入亮色时对 `::view-transition-new(root)` 从零圆扩散；
5. 切入暗色时对 `::view-transition-old(root)` 反向裁剪；
6. 使用 `450ms ease-in`，结束后释放 transition；
7. 不支持 View Transition、键盘触发或 `prefers-reduced-motion: reduce` 时直接切换。

主题按钮使用 sun/moon mask morph 时保持 SVG 内部过渡，不替换成两个视觉重量不同的现成实心 icon。主题切换必须调用现有 app store，不直接操作一套平行的 DOM theme state。

## 登录与认证页面

登录页是产品入口，不是营销首页，也不是普通 CRUD 页面。

桌面可采用 story + form panel：story 解释产品职责，form panel 专注身份验证。左、中、右布局偏好改变两者关系，但不能复制表单状态或重建认证流程。

保持：

- 品牌、标题、表单和主 CTA 是第一视觉路径；
- 工具条位于表单上方或页面角落，不能抢过登录标题；
- story 文案短、专业、可扫描，功能点说明真实能力；
- 表单宽度稳定，Captcha、MFA、session expired、disabled account 等状态不破坏整体节奏；
- 中心布局在小屏以表单优先，装饰 story 可以隐藏；
- 主题色只改变既有 Token，不能让验证码、错误状态或可访问性失真；
- 登录布局偏好与认证 credential state 分离。

## 响应式

至少检查 desktop、约 768px 到 1120px 的中间状态和 `375px` 手机宽度。

- desktop 保持标题、筛选、工具条和数据区的自然对齐；
- 中间宽度先收敛次要内容，不直接把桌面双栏压窄；
- mobile 保留认证、主要操作、语言和主题能力，隐藏低价值装饰与复杂外观入口；
- 页面 `scrollWidth` 不得大于 `clientWidth`；
- 触控目标不能因图标视觉尺寸较小而同步缩小；
- 安全区域、虚拟键盘、Footer 和长语言文本不能遮挡表单操作。

## 无障碍与本地化

- icon-only button 必须有准确 `aria-label`；Tooltip 不是 accessible name 的替代品；
- toggle 使用可读的当前/目标状态，选择项使用 `aria-pressed`、radio 或 Arco 原生选中语义；
- keyboard 可以打开、选择、关闭并返回触发器；
- focus-visible 清晰但不形成第二层永久装饰；
- `prefers-reduced-motion` 下禁用非必要动画；
- 中文与英文 key 同步，短标签优先，不能依赖 ellipsis 隐藏关键动作；
- 对比度、错误信息、disabled 状态不能只在一种主题中成立。

## 工程映射

从 Vben 到 Motor 的翻译规则：

- Tailwind utility -> Motor scoped Less + `--motor-*` Token；
- Shadcn button/dropdown -> 现有 `HeaderIconButton`、Arco Dropdown/Popover/Button；
- Vben preferences -> Motor app store 和既有 preference 持久化；
- Lucide icon -> 项目已有同家族 icon，确需精确轮廓时使用最小本地 SVG，不为少量图标增加第二套 UI library；
- Vben auth layout -> Motor 当前 login orchestration，不替换认证 API、Captcha、MFA 或 session 语义；
- Vben Grid/Form abstraction -> 不迁移，继续使用 Motor 的 API、状态和 Arco 组件边界。

先比较行为契约，再映射组件。不能复制 class 名后猜测 Motor 中的效果，也不能为了 1:1 视觉复制 Vben 的 package、monorepo、router、permission 或 preferences 架构。

组件抽取条件仍是出现第二个真实调用方或存在独立生命周期。一次页面微调优先局部实现，已经稳定的共享组件不能为单页效果被全局破坏。

## 浏览器验收

自动化门禁通过不等于视觉完成。UI 交付至少形成以下证据：

### 页面矩阵

- desktop light；
- desktop dark；
- `375px` mobile；
- 中文和英文或最容易溢出的 locale；
- loading、error、empty、success、mutating 中与改动相关的状态；
- keyboard focus 与 reduced motion。

### 交互矩阵

- before、during、after 三个动画阶段；
- hover、press、focus-visible、selected、disabled；
- Dropdown 打开时 Tooltip 是否重复；
- 快速重复操作是否产生竞态、残影或多层浮层；
- 刷新后 preference 是否从同一权威状态恢复。

### 数值证据

涉及尺寸、对齐、溢出或动画时，用浏览器读取：

- `getBoundingClientRect()`；
- `getComputedStyle()`；
- `scrollWidth/clientWidth`；
- Web Animations timing、pseudoElement 和 keyframes；
- 可见 Tooltip、Dropdown、Popover 数量；
- console error。

截图应覆盖最终状态，动画机制还需中间帧或运行时记录。交付时区分“源码映射一致”“自动门禁通过”“真实浏览器已验证”和“受环境限制未验证”。

## 禁止事项

- 不把 Vben 的 Tailwind、Shadcn、Grid、schema form、preferences 或 monorepo 全量搬入 Motor；
- 不用通用 Admin Template 皮肤覆盖 Motor 的业务信息架构；
- 不用多个同等级 card、shadow、gradient 和大圆角制造虚假层级；
- 不让辅助工具条、设置按钮、Tooltip 或动效抢占主任务；
- 不使用文本对齐图标表达面板布局，不混用线性、实心和不同 stroke 家族图标；
- 不在 Dropdown 打开时保留重复 Tooltip；
- 不用复合色环、边框和阴影重复表达一个颜色选中态；
- 不用整屏黑白遮罩近似 View Transition 的圆形扩散；
- 不只看最终截图就宣称动画、键盘、移动端或主题切换完成；
- 不把某次 Vben 的具体实现永久宣称为“当前 Vben”，需要 1:1 时重新验证源码。
