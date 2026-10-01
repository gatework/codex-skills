# Netdisco Web、API 与交互方法

**目录**：技术栈与组合 · 插件与输出契约 · 片段生命周期 · 转义 · 布局 · 案例与验证

源码路径相对 `$ND`，基线见 [source-map.md](source-map.md)。前端变化快，以 `package.json`、`share/views/layouts/main.tt`、当前静态脚本和 `xt/js/` 共同确认实际能力，不凭历史依赖清单实现新功能。

## 技术栈与组合

当前 checkout 使用 Dancer v1、DBIx::Class、Template Toolkit、Bootstrap、原生 JavaScript、DataTables、HTMX 和 force-graph。`package.json` 是 vendored 清单，没有应用构建 scripts。已移除的 jQuery、jQuery UI、jsTree、toastr、floatThead 与旧日期控件不应重新引入；不能照搬旧版插件示例。

`share/views/layouts/main.tt` 加载公共资源、导航、tenant/用户控件和插件资源；body 的 `data-nd-*` 提供页面配置。页面由外壳、侧栏表单和结果片段组成。沿用这套组合方式，而不是复制完整外壳或把后端模板改为 SPA。

| 责任 | 当前扩展点 | 实现约束 |
|---|---|---|
| 标签、报表、导航、详情行、端口列 | `Web/Plugin.pm` 注册接口 | 复用公共排序、外壳与权限规则 |
| 页面行为 | `netdisco.js` 的 `ndPages`，如 `netdisco-admin.js` | 公共调度只认识生命周期，页面模块注册自身行为 |
| 表格渲染与 callback | `netdisco-tables.js` 的 `ndTables` | 模板声明数据和注册名，静态脚本实现行为 |
| 非 HTMX 请求与字段序列化 | `netdisco-request.js` 的 `ndRequest` | 保留 AJAX header、参数编码和失败处理 |
| 用户反馈 | `netdisco-toast.js` 的 `ndToast` | 复用 Bootstrap toast，不重新依赖 toastr |
| SNMP 树与固定表头 | 服务端树标记、CSS sticky | 不恢复 jsTree 或 floatThead |

每个扩展点的参数以当前实现为准；表格注册名、模板属性和 callback 必须一起验证。

## 插件与输出契约

站点扩展使用 `App::NetdiscoX::Web::Plugin::*`，注册模板路径、标签、报表或资源。新增之前先判断 JSONB 自定义字段或配置式通用报表是否足够；选择方法见 [functional-capabilities.md](functional-capabilities.md)。

请求内使用 `schema(vars->{tenant})`。生成链接用 tenant 感知的 URI helper，不能只让页面 URL 含 tenant 而查询默认库。登录与角色守卫在服务端执行，按钮可见性不是授权。

同一报表可能提供 HTMX/AJAX HTML、非 AJAX CSV 和 API forwarding。追踪实际 route 的分支与 header，不假设每个接口都同构。Swagger、输入验证、HTTP 状态、content type、字段形状和权限属于同一功能契约。

设备控制排队执行，通过任务日志呈现完成结果。Node/ARP 导入复用 offline Worker；页面接受请求不代表设备或库存更新成功。

## 片段生命周期：让一个机制拥有一种行为

侧栏表单用当前版本的 HTMX 属性声明目标、header、indicator 与请求同步；参考 `share/views/device.tt`。不要再给同一 submit 安装第二套手工请求链。

- URL 由响应 `HX-Push-Url` / `HX-Replace-Url` 驱动，片段携带 title 与 pane chrome。`Web.pm` 的响应 hook 和相关 helper 负责一致生成；CSV/API 不应混入这些 HTML。
- 当前 `netdisco.js` 配置 `htmx.config.history = 'reload'`，避免历史遍历把外壳脚本再次插入执行。不要恢复手写 pushState/popstate，也不要复制 HTMX 旧版已移除的配置项。
- `ndPages` 与公共片段初始化负责替换后的行为；全局事件使用已有的委托机制，局部对象按生命周期初始化和销毁。验证重复切换后没有重复监听、遗留 popover 或 DataTable 重复初始化。
- 新行为放静态 JS，模板传 `data-*` 或序列化数据。既有残留模板脚本是兼容面，不是新增代码模板；查看 `xt/js/no-fragment-scripts.test.js` 的允许范围。
- 手工请求优先用 `ndRequest`；HTMX 错误响应遵循公共 noSwap 与错误反馈，失败后仍应能重试。
- `do_search` 是带弃用诊断的站点兼容桥，不作为新功能入口。移除旧接口前运行站点模板诊断，说明迁移方式。

这里的原则是明确状态所有者：URL 归响应和 HTMX，表格增强归 `ndTables`，页面行为归注册模块。不要为一次交互再实现第二套状态同步。

## 最终输出上下文与数据形状

Template AutoFilter 默认开启。文本/属性使用 HTML 转义，URL 参数使用 URI 编码；`uri_for` 生成路径也要考虑最终 HTML 属性上下文。仅对已安全的标记或明确处理过的数据使用 `none`，不能用它消除报错。

脚本数据使用现有集中转义 helper，CSV 关注字段边界与公式风险，JSON 使用序列化接口；三者不可互换。`Web.pm` 和 `Web/Util` 是定位入口。

**键存在性也是接口。** `Web.pm` 的模板处理按 `exists $tokens->{results}` 决定 API 结果分支。`results => []` 与没有 results 键不同；通用 hook 不应为方便添加这个键。

**在序列化边界缩小暴露面。** Result 的 `serializable_columns` 与列元数据决定 JSON 输出，Device 排除 `snmp_comm`。不要由每个路由临时删除凭据，也不要让同名关系方法替代列值。源码与测试入口：`DB/Result.pm`、`DB/Result/Device.pm::serializable_columns`、`xt/78-device-serializable-columns.t`。

## 布局与依赖维护

复用现有导航、侧栏、标签、紧凑表格、Bootstrap 状态色与 `nd_*` 类。尺寸从当前 CSS 和页面读取；历史测量值不构成禁止调整布局的契约。检查长设备名/端口名、空结果、大表格、溢出、键盘焦点、展开层级与窄视口。

升级依赖时同时检查源版本、vendored 文件、layout 引用、`package.json`、MANIFEST 和测试。不要直接修改第三方压缩产物；检查目标仓库实际提供的升级方式。

## 案例与验证

**新增 tenant 报表。** 若仅有只读 SQL、列声明和参数，先采用通用报表；需要可复用领域查询再用 ResultSet/Virtual Result。参考 `Web/GenericReport.pm`：按显式外部 database 或当前 tenant 选 schema，按配置顺序 bind 参数，并复用注册及输出路径。测试同一个过滤条件在 HTML、CSV 和 API 中含义一致，非默认 tenant 不串库，空结果保持合法结构，拒绝访问不返回数据。

**新增表格行为。** 模板声明 `ndTables` 注册名，静态脚本实现 renderer/callback；用 `xt/js/tables-registry.test.js` 查注册闭合，再通过行为测试检查格式化结果。只查字符串存在不能证明浏览器初始化成功。

**验证按风险选择：**

- 纯 helper：运行对应 Node 行为测试或 Perl 单元测试。
- 公共契约：参考 `xt/44-results-token-escaping.t`、`xt/53-ports-csv-arity.t` 和 `xt/78-device-serializable-columns.t`，断言实际响应/序列化结构。
- 模板：运行 `xt/40-template-snapshots.t`；有意变化用 `xt/bin/regenerate-snapshots` 生成并审查差异。
- 机制守卫：`xt/js/history-ownership.test.js`、`page-registry.test.js`、`no-jquery.test.js`、`no-fragment-scripts.test.js` 约束结构；不把通过守卫称作交互验收。
- 页面改动：浏览器验证请求、替换、重复切换、前进后退、错误后重试、tenant、角色和响应式布局。

Node 显式列出实际测试文件，完整门禁取自当前 `.github/workflows/frontend-tests.yml`；仅改 skill 不需要为此启动产品或连接生产数据库。
