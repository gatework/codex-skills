# 测试、CI 与交付证据

用于选择测试、证明并发语义、匹配 CI、验证 UI，以及评估生产就绪程度。

## 目录

- [测行为，不测实现形状](#测行为不测实现形状)
- [后端测试矩阵](#后端测试矩阵)
- [确定性并发测试](#确定性并发测试)
- [前端竞态测试](#前端竞态测试)
- [身份收敛测试](#身份收敛测试)
- [业务生命周期测试](#业务生命周期测试)
- [测试分层与跨栈验收](#测试分层与跨栈验收)
- [CI 与本地门禁](#ci-与本地门禁)
- [防止 Hollow Green](#防止-hollow-green)
- [UI 证据](#ui-证据)
- [Migration 交付](#migration-交付)
- [Release Artifact 验证](#release-artifact-验证)
- [生产就绪矩阵](#生产就绪矩阵)
- [证据语言](#证据语言)
- [回归测试质量门](#回归测试质量门)

## 测行为，不测实现形状

优先证明用户/系统可观察行为：

- 成功路径；
- 参数错误；
- 未认证；
- 已认证无权限；
- credential type 不允许；
- 资源不存在/隔离；
- conflict；
- retry/idempotency；
- 并发；
- loading/error/empty/success；
- 身份变化后的收敛。

避免只断言“某 private method 被调用”。

## 后端测试矩阵

| 变更 | 最低证据 |
| --- | --- |
| Model/constraint | model spec + DB constraint 行为 |
| API | request spec + 权限/失败状态 |
| serializer | contract/response spec 或调用方断言 |
| Service | transaction、失败、回滚、幂等 |
| JWT/API Token/MFA | credential matrix + revocation/replay |
| Sidekiq / Active Job | enqueue 抛错/false/延迟提交、success、expected failure、retry、duplicate |
| Webhook | HTTPS、SSRF、timeout、non-2xx、header |
| Migration | migrate/schema + rollout/rollback reasoning |
| `UserSettings` 聚合 | 两类并发 mutation + secret 保留 + size/schema |
| 生命周期/保留任务 | notice、durable deadline、grace、fail-closed、最终 action |

## 确定性并发测试

不要写“启动 10 个线程，希望碰到 race”的概率测试。

数据库竞态优先：

1. 使用两个独立 DB connection/transaction；
2. 用显式阶段信号协调竞争入口、持锁与释放；
3. 正确锁会挡住第二个执行，不在锁内要求双方同时到达 barrier；
4. 观察数据库阻塞或明确阶段，再由主线程放行，超时应令测试失败；
5. 断言最终不变量和每个结果；
6. 验证旧实现能失败，新实现稳定通过。

适用于：最后管理员、集合替换、一次性 challenge、claim、状态机跃迁。具体设计与项目定位见 [code-patterns.md](code-patterns.md) 的 T1。

## 前端竞态测试

使用 controllable/deferred Promise：

1. 发请求 A；
2. 发请求 B；
3. 让 B 先成功；
4. 断言页面提交 B；
5. 再让 A 成功；
6. 断言 A 不覆盖 B，也不错误关闭 B 的 loading/error 状态。

如果 hook 的真实调用方式会在 request callback 内写 reactive state，测试也必须覆盖这种使用方式，不能只测试返回值被丢弃。形状示例见 [code-patterns.md](code-patterns.md) 的 T2。

## 身份收敛测试

role switch、impersonation、logout、session revoke 后覆盖：

- store 当前用户和 permissions；
- 当前 route 是否仍可访问；
- tabs/cache；
- Cable subscription；
- 旧身份请求晚到；
- API 返回 401/403 后的统一行为。

## 业务生命周期测试

对 Motor 特有流程，不要只测单个 service/action 成功：

### `users.settings`

- 同时更新 preferences 与 notification channel，最终两边都保留；
- 两个 worker 更新同一渠道时结果符合既定锁/last-write 语义；
- 未回显 secret 在普通编辑后仍保留，空值不会意外清除；
- 超过容量、非法 schema/渠道配置被拒绝；
- public response 不出现 webhook URL、签名密钥或敏感 header。

### 账户生命周期与数据保留

使用可控 `now`/时钟验证：

1. 未到提醒阈值不动作；
2. reminder/provider 失败时不写入可执行 deadline，或保持当前设计的 fail-closed 证据；
3. 第一次成功提醒只建立 durable notice/deadline，不同轮执行 destructive action；
4. grace 未结束不执行；
5. deadline 到达后重新检查当前业务资格；
6. 最后管理员/无可通知管理员等安全条件阻止 destructive action；
7. job 重试或重复扫描不提前执行，也不会制造非法重复 durable state；
8. 批量清理只影响满足条件的数据。

如果 refactor 把外部 I/O 从锁内移出，必须新增并发/崩溃窗口测试，证明不会因为 duplicate notice、provider success + DB failure 或两个 worker 同时推进而提前执行破坏动作。


## 测试分层与跨栈验收

优先让测试落在最小能证明不变量的层：

- pure/model/composable：边界和状态转换；
- request/service：权限、事务、错误、serializer contract；
- job/integration：commit boundary、retry、idempotency、真实依赖协议；
- browser E2E：只覆盖跨前后端且 release-critical 的用户旅程；
- release smoke：只验证最终 production artifact 的组合运行，不重复整套 unit tests。

E2E 不作为所有 CRUD 细节的默认测试层。需要浏览器自动化时优先测试用户可见行为和稳定语义，不依赖 DOM 实现细节或固定 sleep。若项目尚无浏览器测试框架，只有存在持续跨栈回归或 release smoke 需求时才引入。

### Contract 变更

修改 route、permission key、JSON 字段/error code、env/config、job class、queue 或持久 identifier 时，测试不仅断言新行为，还要证明兼容策略：

- old caller/old worker 是否仍需支持；
- persisted data/key 如何迁移；
- 何时可以安全删除兼容层；
- 前后端是否在同一 release 原子变化。

## CI 与本地门禁

每次执行前读取当前 `Makefile`、`package.json`、CI，不在 skill 固化未来可能变化的命令细节。

项目长期总入口通常包含：

```bash
make lint
make test
make audit
make package
```

前端完成前确认 `pnpm check` 当前脚本真实覆盖 format/lint/style/type/test/build 哪些步骤。

不要说“CI 会测”，如果当前 workflow 并没有对应 job。


### 防止 Hollow Green

一个 gate 只有真正执行目标路径才算通过：

- 不接受全部 case skipped、空输入、early-return/no-op 后仍返回 0；
- build 成功不能代替运行 production artifact；
- migration spec 通过不能代替实际 migrate/schema/兼容窗口检查；
- 浏览器未打开不能写“视觉已验证”；
- release workflow 页面 success 不能代替远端 digest/asset/attestation 读回。

验证失败先区分 setup/tooling failure 与产品断言失败，不把 runner/network/bootstrap 问题误判成业务 bug。

## UI 证据

涉及 UI 时，build/typecheck 不等于完成。

真实浏览器至少检查相关状态：

- 桌面常用宽度；
- 窄屏/移动端；
- light/dark；
- loading；
- error + retry；
- empty；
- success；
- submitting/disabled；
- no-permission/read-only；
- keyboard/focus；
- 长文本和中英文。

无法打开真实浏览器时明确写“运行时视觉未验证”，不要写“UI 已确认正常”。

## Migration 交付

验证的不只是 migration 能执行：

- 旧版本代码在 rollout 窗口是否还能工作；
- 大表锁时间；
- backfill 批次；
- 新旧字段兼容；
- schema 是否更新；
- rollback 是否真的安全；
- destructive contract step 是否必须下一版本再执行。


## Release Artifact 验证

发布任务额外读取 `references/release-engineering.md`。核心证据链：

`source ref -> full gate -> production artifact -> exact artifact runtime smoke -> same digest publish -> remote readback`

如果测试时和发布时发生重新 build，必须把后者视为新的未验证 artifact。

## 生产就绪矩阵

应用测试全绿后继续检查：

| 维度 | 典型证据 |
| --- | --- |
| 镜像 | 多阶段、最小 runtime、非 root、健康检查 |
| DB | migration、连接池、备份、恢复、回滚 |
| Redis | Sidekiq/Cable/cache/rate-limit 拓扑与隔离 |
| Storage | Active Storage 是否支持实际 replica/持久化需求 |
| Web | TLS、Host、CORS、trusted proxy/IP、静态资源 |
| Worker | queue、retry、dead job、scheduler、shutdown |
| Cable | origin、Redis、ticket、reconnect |
| Secrets | 显式注入、无危险生产 fallback |
| Logs | stdout/file 策略、结构化、轮替、告警、脱敏 |
| Ops | health、metrics、backup restore drill、runbook |

项目当前 deploy 目录若明确标注为未完成，就不能用应用 CI 推断 production-ready。

## 证据语言

只报告当前会话真正执行或读取到的证据：

- “已运行 X，结果通过”需要实际命令输出；
- 只读代码推断时写“基于源码阅读”；
- GitHub CI 需说明具体 ref/run；
- 未执行浏览器、并发压测或生产部署时明确列为 gap。

## 回归测试质量门

修 bug 时优先让新测试在旧实现上失败、修复后通过。

尤其对 race/retry/idempotency：

- 测试要命中真正失败序列；
- 不能只测 helper 返回值而忽略调用方副作用；
- 不能以 sleep 大小决定是否通过；
- 不能只跑一次概率线程测试；
- 修复后搜索同形 sibling pattern。
