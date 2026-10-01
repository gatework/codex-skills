# 认证、授权与安全

处理 JWT、API Token、RBAC、MFA、用户代入、验证挑战、RailsAdmin、限流、加密、上传和外部 HTTP 时读取本文件。

## 目录

- [先画凭证矩阵](#先画凭证矩阵)
- [Access context 是统一身份语义](#access-context-是统一身份语义)
- [权限能力模型](#权限能力模型)
- [防提权](#防提权)
- [会话与撤销](#会话与撤销)
- [MFA 与一次性挑战](#mfa-与一次性挑战)
- [用户代入](#用户代入)
- [API Token](#api-token)
- [Rate Limit](#rate-limit)
- [密钥与加密配置](#密钥与加密配置)
- [外部 HTTP 与 SSRF](#外部-http-与-ssrf)
- [上传](#上传)
- [日志与错误脱敏](#日志与错误脱敏)
- [安全测试矩阵](#安全测试矩阵)


## 先画凭证矩阵

不要把“已登录”当成单一状态。至少区分：

| 凭证 | 服务端权威 | 典型能力 | 关键限制 |
| --- | --- | --- | --- |
| 浏览器 JWT | UserSession + token/version + 当前角色 | 正常管理端和账户能力 | 需支持撤销、轮换、角色收敛 |
| API Token | token digest + 用户 + 绑定角色 + scope | 长期 API 调用 | scope ∩ 当前角色权限，不得获得账户安全能力 |
| 用户代入 JWT | 来源 session + impersonated session | 管理员观察目标用户 | 默认只读，actor 与 target 分离 |
| RailsAdmin HTML session | Devise 管理员会话 | 运维后台 | 仅有效超级管理员 |
| Cable ticket | 短期、会话绑定票据 | 建立实时连接 | 长期 JWT 不进入 URL |

任何新增敏感接口先回答“允许哪些 credential type”。

## Access context 是统一身份语义

先读取当前 ref 中承担 access/authentication context 的实际类名与调用链，保持身份解析集中：

- credential type；
- current user；
- actor；
- active role；
- user session；
- impersonation；
- effective permissions。

不要在 controller/page 各自重新推导一套 active role 或 permission。

## 权限能力模型

Motor 后端路由/action 是权限权威。

检查链路：

`route/action -> Motor::Permission -> credential_types -> current access context permission_names -> controller authorize -> API -> frontend permission projection`

规则：

- API Token effective permission = token scope ∩ token 绑定角色当前权限；
- 普通用户使用 active role，不把全部角色权限合并；
- admin bypass 只在项目明确允许的真实浏览器会话边界内生效；
- browser-only 权限不因为 token 持有同名字符串就自动开放；
- 新 action 判断是否需要独立权限键，不复用语义不同的旧权限；
- 前端 route/menu/button 只是体验镜像。

## 防提权

修改用户、角色、权限关系时同时检查：

- 当前 actor 能否操作 target；
- actor 当前活动角色是否有该动作权限；
- 能否授予高于自身有效权限的角色/能力；
- 能否修改超级管理员；
- API Token 是否错误获得用户/角色管理能力；
- 并发角色变化后旧请求是否仍能写入。

## 会话与撤销

高风险身份变化必须形成完整收敛链：

`业务动作 -> DB credential/session state -> JWT/token version -> 旧凭证拒绝 -> Redis/在线投影清理 -> 前端身份刷新 -> route/tabs/subscriptions 收敛 -> audit`

重点动作：

- 密码修改/重置；
- 用户禁用；
- MFA 安全变化；
- 全量注销；
- API Token 撤销；
- role switch；
- impersonation start/stop。

Redis 在线状态失败不能恢复数据库已撤销的会话。

## MFA 与一次性挑战

TOTP、recovery code、邮箱/手机号验证码、reset challenge 都按 credential 处理：

- 有明确有效期；
- 有尝试次数和 rate limit；
- 与用户、目标地址、reset token 或业务 scope 绑定；
- 明文只在必要时短时存在；
- recovery code/一次性 challenge 成功后原子消费；
- 两个并发消费请求最多一个成功；
- 失败信息不泄漏账号是否存在或 challenge 内部状态。

## 用户代入

- 仅允许项目规定的高权限浏览器会话发起；
- 禁止代入自己和超级管理员；
- 来源 session 失效时派生代入也失效；
- 默认仅 GET/HEAD 等只读行为，写操作只开放明确的退出/身份生命周期动作；
- audit 同时记录 actor 和 target；
- 前端明显展示代入状态，并在退出后刷新身份、权限、路由、tabs 和实时订阅。

## API Token

- 存储摘要，不存明文；
- 明文只在创建响应中展示一次；
- token 有 role、scope、过期和撤销边界；
- token permission 永远不独立于绑定角色当前权限；
- 不允许操作 MFA、密码、角色切换、代入、会话或其他长期凭证管理能力，除非项目明确设计并重新审查威胁模型；
- 使用记录不能泄露 token 本身。

## Rate Limit

根据攻击面组合 key：

- IP；
- 用户名/邮箱等账号标识的摘要；
- challenge/reset token 摘要；
- session；
- endpoint 风险等级。

不要只依赖 IP 限流，也不要把原始敏感值直接作为 Redis key 或日志字段。

生产环境优先将安全限流状态与可随意清空的普通缓存隔离，避免缓存 flush/eviction 意外削弱认证保护。

## 密钥与加密配置

- 使用 Active Record Encryption 等项目既有边界；
- 生产 encryption keys、JWT secret、SMTP secret、provider secret 不提供危险默认值；
- serializer/API 不返回完整密钥、secret URL、连接串；
- 日志、异常通知和 audit 先脱敏再持久化或发送；
- 配置 key 使用稳定机器标识，不使用可翻译展示文本。

## 外部 HTTP 与 SSRF

Webhook/飞书等用户可配置出站 HTTP 保持：

- HTTPS-only；
- DNS 解析后阻断 loopback、private、link-local、reserved 地址；
- 防 DNS rebinding，需要时固定已验证地址；
- connect/read/write timeout；
- 危险 header allow/deny 策略；
- 明确 redirect 策略，不能自动跟随到未重新校验地址；
- 非 2xx 明确失败并进入可重试流程；
- secret URL 不进入公开错误或完整日志。

## 上传

- 前端 `accept` 只改善 UX；
- 服务端验证文件大小、内容类型、允许扩展和必要的图像/文件解析；
- 生成公开 URL 时确认 host/proxy 配置；
- 不让用户文件名直接形成服务器路径；
- Active Storage 的生产持久化策略和备份必须与部署模式匹配。

## 日志与错误脱敏

至少过滤：password、token、Authorization、Cookie、captcha、verification code、TOTP、secret、key、salt、configuration、provider URL 中的敏感部分。

API 公开错误不返回：

- stack trace；
- SQL；
- 内部主机名；
- 第三方完整响应；
- credential；
- 可被用于用户枚举的差异化细节。

## 安全测试矩阵

身份/权限变更至少覆盖：

- 未认证；
- 正确 JWT；
- API Token；
- API Token scope 不足；
- 绑定角色后来失权；
- disabled user；
- revoked/old session；
- impersonation；
- 普通用户对高权限目标；
- admin；
- 并发消费/撤销场景；
- 日志与错误不泄密。
