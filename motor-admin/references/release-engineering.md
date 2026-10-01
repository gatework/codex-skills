# CI、制品与 Release Engineering

处理 GitHub Actions、Docker production image、GHCR/GitHub Release、依赖升级、供应链安全、tag/version、release smoke 和发布准备时读取本文件。

## 目录

- [发布不是 CI 全绿](#发布不是-ci-全绿)
- [PR 与主分支门禁](#pr-与主分支门禁)
- [Build Once](#build-once)
- [Production Image](#production-image)
- [Release Pipeline](#release-pipeline)
- [Migration 与上一版本升级](#migration-与上一版本升级)
- [Actions 与供应链安全](#actions-与供应链安全)
- [Release Smoke](#release-smoke)
- [发布权限与控制面](#发布权限与控制面)
- [失败、并发与回滚](#失败并发与回滚)
- [Release 证据台账](#release-证据台账)

## 发布不是 CI 全绿

区分四类证据：

1. source gate：lint/unit/request/security/build；
2. artifact gate：真正 production image/package 被构建并检查；
3. runtime gate：刚构建的 artifact 启动后完成 migration/smoke/E2E；
4. publish gate：远端 registry/release 的 digest、attestation、asset 被读回验证。

前一层通过不能替代后一层。尤其不能用 dev Docker target 或源码测试证明 production image 可发布。

## PR 与主分支门禁

- CI workflow、Makefile、package scripts 是当前执行事实源；
- required checks 必须稳定命名，避免多个 workflow 产生同名模糊 check；
- 关键分支应通过 branch protection/ruleset 要求必要 checks 通过后合并；
- 若使用 merge queue，检查 workflow 是否覆盖当前 GitHub 所需事件；
- 不通过 path filter 让 required workflow 在常见 PR 上永久 Pending/Skipped；
- CI 默认最小 `contents: read`，写权限按 job 局部提升。

branch protection/ruleset 属于 GitHub 控制面，不因“仓库代码整改”自动修改；需要当前用户明确授权和可用权限。

## Build Once

发布核心原则：

`build candidate once -> test that exact artifact -> promote/publish the same digest`

禁止：

`CI build A -> tests pass -> release job重新 build B -> publish B`

如果 registry/tag promotion 需要重新标记，应基于已验证 digest，不重新解释 Dockerfile/lockfile 构建另一个未知 artifact。

## Production Image

Backend/frontend image 至少检查：

- multi-stage builder/runtime；
- runtime 不携带不必要 build toolchain；
- production dependency group 正确，不能先安装全部 dev/test 再仅靠运行时变量“排除”；
- final runtime 使用非 root 用户，除非基础镜像/平台有已证明的等价隔离；
- frozen lockfile；
- secret 不通过 ARG/layer 固化；
- health/readiness 能代表应用状态，不只是进程存活；
- Web 与 Sidekiq 可复用同一 backend digest、不同 command；
- frontend final image 只带运行静态资源所需内容并保持 SPA fallback。

## Release Pipeline

目标顺序根据当前仓库能力调整，但长期语义保持：

```text
release candidate ref/tag
  -> full source verification
  -> build production artifacts
  -> vulnerability/metadata checks
  -> migration/fresh-install smoke
  -> full-stack runtime smoke
  -> critical browser journey
  -> provenance/SBOM when publishing artifacts
  -> promote exact digest/version
  -> verify remote artifact
  -> create/finalize GitHub Release
```

GitHub Release 是验证完成后的发布结果，不是“先发布再开始测试”的触发点。

不要把 production deployment 自动串在 Release 后面，除非当前 `deploy/`、migration/backup/rollback/readiness 已在代表性环境验证且用户明确要求自动部署。

## Migration 与上一版本升级

有 schema 变更的 release 至少验证 fresh schema。建立首个 stable release 后，高价值路径是：

`previous stable artifact -> representative old schema/data -> candidate migrate -> candidate boot -> smoke`

检查：

- 旧 web/worker 与过渡 schema 的兼容窗口；
- migration 是否可重复/失败后恢复；
- queued old job 是否仍能执行；
- destructive contract step 是否应延后一个 release；
- rollback app 前旧版本能否读取当前 schema。

## Actions 与供应链安全

高权限 workflow 特别检查：

- 第三方/GitHub Action 是否 pin 到完整 commit SHA；
- Dependabot/维护机制是否仍能更新这些 pin；
- `permissions` 是否 job-level 最小化；
- `pull_request_target`、fork secret、脚本拼接是否引入不可信代码执行；
- release 使用的 base image、Ruby/Node/pnpm、lockfile 与当前项目事实一致；
- 发布 container/package 时生成并保留适用的 SBOM/provenance/attestation；
- 远端 artifact 通过 digest/manifest/attestation 读回，不以 release 页面文字或文件大小代替内容验证。

不要为了供应链“更现代”无条件引入新扫描 SaaS；先使用 GitHub/Docker/现有依赖生态原语。

## Release Smoke

Release smoke 测“最终制品拼起来能工作”，不重复整套 unit tests。Motor 关键路径优先：

- DB migration/boot；
- Rails readiness；
- frontend Nginx + SPA fallback；
- login/current identity；
- 至少一个 permission-protected API；
- Redis/Sidekiq boot 与最小 job path；
- Cable 若当前 release 涉及实时能力；
- logout/session revoke；
- 关键页面浏览器 smoke。

浏览器 E2E 只覆盖 release-critical journey，优先 user-visible locator/assertion；不要把全部 CRUD 细节搬到 E2E。

## 发布权限与控制面

将权限按 job 分离：

- verify：只读；
- package/push：仅 registry 所需写权限；
- attestation：仅证明所需 OIDC/attestation 权限；
- release：仅 contents/release 所需权限。

禁止 `write-all`。GitHub branch protection、ruleset、environment protection、repository secrets 属于外部控制面，修改前必须确认会话中已有明确授权，并在修改后读回状态。

## 失败、并发与回滚

- release workflow 使用 concurrency，避免同一 lane/version 并行发布；
- 任何 gate 失败都不得创建“看起来成功”的 stable Release；
- 已推 candidate image 失败时保留或清理策略明确，不将 candidate tag 当 stable；
- application 通过 immutable digest 回滚；
- migration 需要 forward-fix/restore 策略，不能假设 app rollback 自动回滚 schema；
- 网络/API 失败后读回远端状态再判断成功/失败。

## Release 证据台账

发布结论至少记录：

- source ref/tag/commit；
- required CI status；
- backend/frontend artifact digest；
- build/runtime/migration/browser smoke 结果；
- vulnerability/security gate；
- SBOM/provenance/attestation（若适用）；
- remote registry/release readback；
- rollout lane；
- rollback target；
- 未验证项和明确 blocker。

只有这些证据闭环后才使用“可发布/已发布”措辞。
