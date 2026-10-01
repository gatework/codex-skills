# 项目约定(由代码证明的部分)

> 只记录已被代码证明的约定和有理由的偏离,每条附一个代表位置。过期就删。

## 运行时与工具
- Ruby:<版本>(来源:.ruby-version)
- Rails:<版本>,`load_defaults` = <x.y>
- 测试:<Minitest | RSpec>,数据:<fixtures | factories>
- Lint:<RuboCop 配置与继承>
- 质量入口:<bin/ci | rake | ...>

## 目录与命名
- 领域代码放在:<app/models/<domain>/ | app/services/<domain>/ | ...>(例:<路径>)
- 用例/服务的入口动词:<call | perform | 具名动作>
- 命名后缀:<Query | Form | Policy | Presenter | ...>(例:<路径>)
- 缩写(inflection):<API, SSL, ...>

## 请求与授权
- 参数:<params.expect | require.permit>
- 授权范围:<Current.user.xxx.find | policy scope>(例:<路径>)
- 错误映射:<rescue_from 位置>

## 数据与任务
- 迁移约定:<版本基类、并发索引、回填方式>
- 异步:<队列后端>,幂等手法:<pending 状态 | 幂等键>,重试策略:<位置>
- 回调使用准则:<允许 / 不允许>

## 测试
- 目录与命名:<路径>
- 登录/时间/任务辅助方法:<位置>
- 必跑门禁:<命令>

## 有意的偏离
- <偏离本技能或框架默认的做法> — 原因:<...> — 位置:<...>

## 范式卡索引
- <范式名> — <一句话> — <文档位置>
