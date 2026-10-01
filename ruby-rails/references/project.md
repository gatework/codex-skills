# 项目代码范式:勘察、提炼、沉淀

每个项目都有自己的"方言":目录怎么分、service 叫什么、错误怎么表达、测试怎么写。**新代码应先与项目多数写法一致,再谈改进。** 本文给出两套可重复的方法:

- 勘察法:进入陌生项目后,按任务范围确认相关约定。
- 提炼法:把反复出现的做法抽象成可复用的"范式卡",并写进项目约定文档。

目录:一、勘察清单 · 二、信号搜索 · 三、决定"跟谁" · 四、范式提炼法 · 五、范式卡模板 · 六、沉淀为项目约定 · 七、避免的误区

## 一、勘察清单

按顺序看,每一步都产出一句结论。

1. **运行时与工具**:`.ruby-version` / `.tool-versions`、`Gemfile.lock`(Rails、RuboCop、测试框架的**实际**版本)、`config/application.rb` 里的 `config.load_defaults`、`.rubocop.yml` 及其继承(如 Omakase)。
2. **入口与门禁**:`Rakefile`、`bin/ci`、`.github/workflows/`,以及 README/CONTRIBUTING/`AGENTS.md`/`CLAUDE.md` 中的开发说明。
3. **目录与命名空间**:`app/` 下有哪些非默认目录(`services`、`queries`、`forms`、`policies`、`presenters`、`components`)?`app/models/` 下有没有按领域的命名空间和 `concerns`?
4. **加载方式**:`lib/` 是 autoload 还是手动 require?有没有自定义 inflection(缩写)?
5. **相关的同类功能**:用 `git log --stat -n 30` 或按目录找最近新增的功能,沿"路由 → 控制器 → 模型 → 任务/邮件 → 视图 → 测试"读一遍,记下每一层的落点与命名。
6. **测试风格**:Minitest 还是 RSpec?fixtures 还是 factories?request/system 测试占比?有没有共享辅助方法(登录、时间、任务)?
7. **异步与数据**:队列后端(Solid Queue/Sidekiq/…)、数据库、缓存、存储,以及多租户/权限方案。
8. **git 状态**:`git status` 看有没有他人未提交的改动,保留它们。

## 二、信号搜索

用简单搜索把"感觉"变成计数(命令按项目实际路径调整):

```bash
# 目录与命名后缀:项目实际用哪些
ls app; ls app/models | head -50
rg -o --no-filename "class [A-Z][A-Za-z:]*(Service|Query|Form|Policy|Presenter|Job)\b" app lib | sort | uniq -c | sort -rn | head

# 入口动词:call / perform / execute / 具名动作
rg -o --no-filename "def (self\.)?(call|perform|execute|run|process)\b" app | sort | uniq -c

# 控制器参数写法
rg -n "params\.(expect|require)|permit!" app | head

# 回调使用倾向
rg -n "^\s*(before|after|around)_(save|create|update|commit|validation)" app/models | head -30

# 全局/隐式上下文
rg -n "Current\." app | head -20

# 错误约定
rg -n "class [A-Za-z:]*(Error|Exception)\b" app lib | head
rg -n "rescue_from" app | head

# 测试形状
ls test spec 2>/dev/null; rg -o --no-filename "^\s*(test|it|scenario) [\"']" test spec 2>/dev/null | wc -l
```

## 三、决定"跟谁"

| 情形 | 决定 |
| --- | --- |
| 同一做法在代码库中占**明显多数** | 新代码照做 |
| 两种做法各占一半 | 看最近半年新增的代码倾向;仍不清就选与所改文件相邻代码一致的 |
| 少数派做法是**有意为之**(有注释、README、迁移记录、提交说明) | 尊重并沿用于同类场景 |
| 明显的历史遗留(与文档或 RuboCop 冲突,且在减少) | 新代码不跟,但**不因此顺手大改旧代码** |
| 项目约定与本技能建议冲突 | 项目约定优先;发现真实风险(安全、数据丢失)时在交付说明里提出,而不是静默改写 |

## 四、范式提炼法

从若干具体实现抽象出一条可复用的范式,分七步:

1. **采样**:选择相关独立实例并记录样本范围；少量样本不足以声称全仓惯例，但显式项目规范不需要靠凑数量证明。
2. **对齐**:并排比较它们做了什么、按什么顺序、用了什么名字。
3. **命名**:给这个范式起名,名字要是领域动词/名词而不是技术堆砌(如"授权范围内查找"、"提交后入队"、"原子领取")。
4. **提取不变量**:哪些点在所有实例里都成立?——这是范式的本体。(例:"查找总是从 `current_user` 的关联开始"。)
5. **标出变化点**:哪些点每个实例不同?——这是参数或扩展点。(例:"查询的关联名"。)
6. **找反例与边界**:有没有实例故意偏离?为什么?它们划出了范式的适用边界。(例:"公开页面没有 current_user,不适用。")
7. **写成 when / do / don't / verify**:何时用、怎么做、不要怎么做、如何验证。写不出"如何验证"的范式暂不沉淀。

抽象层次的自检:

- 范式应回答"**为什么**这样做",而不只是"这里长这样"。缺少理由的模板会被机械照抄。
- 一条范式只管一件事;一个范式里出现"并且……并且……"就该拆。
- 如果范式只是某个框架特性的复述(Rails Guides 已经写清),引用文档即可,不重复沉淀。
- 范式要能被**否证**:给出"什么情况下这条范式不成立"。

## 五、范式卡模板

```markdown
### <范式名>(领域动词/名词)

**何时用**:<触发场景,一句话>
**不变量**:<在所有实例中都成立的规则>
**做法**:
1. <步骤或代码骨架>
**变化点**:<每次要替换的部分>
**不要**:<常见误用与反例>
**验证**:<测试或检查如何证明遵守了范式>
**依据**:<至少 3 个代码位置 / 文档 / 决策记录>
**边界**:<不适用的情形与原因>
```

示例(从 Rails 项目中常见做法提炼):

```markdown
### 授权范围内查找

**何时用**:控制器按 ID 读取或修改属于某个用户/租户的对象。
**不变量**:查找永远从当前主体的授权范围开始,找不到即 404,不先全表查再补检查。
**做法**:
1. `@order = Current.user.orders.find(params[:id])`
2. 批量、导出、任务与附件下载复用同一范围方法(如 `Order.visible_to(user)`)。
**变化点**:主体(用户/租户/组织)、关联名。
**不要**:`Order.find(params[:id])` 之后再 `authorize`;在 Serializer 里过滤字段代替授权。
**验证**:request 测试同时造可见与不可见记录,确认不可见记录返回 404 且详情入口也拒绝。
**依据**:orders_controller#show, exports_controller#create, downloads_controller#show
**边界**:公开只读页面(无当前主体)不适用,需另设公开范围。
```

## 六、沉淀为项目约定

仅当任务包含规范沉淀，或本次行为变更需要同步文档时，把结论写进项目；普通勘察只用于当前任务，不自动修改 AGENTS.md 或新建规范：

- 位置优先级:项目已有的约定文件(`AGENTS.md`、`CLAUDE.md`、`CONTRIBUTING.md`、`docs/conventions.md`)> 新建 `docs/conventions.md`。模板见 [`assets/project-conventions.template.md`](../assets/project-conventions.template.md)。
- 内容只写**已被代码证明**的约定和**有理由**的偏离,每条附一个代表位置;不写愿望清单。
- 保持短:约定文档是索引和判断依据,不是教程。超过一屏的内容拆成范式卡。
- 变更约定要走评审;过期条目及时删除。

## 七、避免的误区

- **只看一个文件就下结论。** 按风险对照相关实例与项目指令。
- **把"最新写法"当作"团队约定"。** 新语法要先确认最低 Ruby 版本与团队意愿。
- **把个人偏好写成规则。** 规则要能指出它保护的契约或成本。
- **为了统一而改旧代码。** 新代码跟随多数;旧代码随相关业务修改渐进调整。
- **提炼过度。** 不要把个别经验推广成通用要求；说明观察范围与例外。
- **忽略反例。** 反例通常正好说明了范式的边界。
