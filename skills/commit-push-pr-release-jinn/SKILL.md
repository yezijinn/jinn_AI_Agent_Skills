---
name: commit-push-pr-release-jinn
description: 安全提交、推送、创建PR与Release，含文档整理与.gitignore。Tag强制vYYYYMMDD，资产文件名纯英文，README与Release Notes中英双语。
allowed-tools:
  - Bash(git status:*)
  - Bash(git diff:*)
  - Bash(git diff --cached:*)
  - Bash(git branch:*)
  - Bash(git branch --show-current:*)
  - Bash(git log:*)
  - Bash(git add:*)
  - Bash(git commit:*)
  - Bash(git checkout --branch:*)
  - Bash(git push:*)
  - Bash(git tag:*)
  - Bash(gh repo view:*)
  - Bash(gh pr create:*)
  - Bash(gh pr view:*)
  - Bash(gh release create:*)
  - Bash(gh release upload:*)
  - Bash(gh release view:*)
---

# Commit, Push, PR, Docs, and Release（中英双语）

安全执行 Git 提交、推送、PR、Release。保留用户改动，禁止 force push，禁止空提交，禁止泄露密钥。

## 触发条件
用户要求：commit / push / PR / 更新 README/.gitignore/AGENTS.md / 创建 Release / 完整发布流程。

## 禁止事项
- 无关清理、大规模重构、改写历史、force push、合并PR、删除分支/仓库。
- 未经明确授权不得发布 Release。

---

# 安全规则

1. **保留改动**：禁止 `reset --hard`、`clean -fd`、`checkout -- .`、`restore`。只暂存明确相关的文件。
2. **范围控制**：先 `git status` + `git diff HEAD`，只 `git add <显式路径>`，禁用 `git add .` 除非明确全量。
3. **密钥保护**：提交/发布前检查暂存区及资产文件，发现 `.env`、`*.pem`、`key`、`token`、`password` 等立即中止并报告。
4. **禁止 force push**。
5. **非空提交**：若无变更则停止（除非只做 Release）。
6. **Release 需显式请求**。

---

# 工作流程

## 1. 上下文收集
```bash
git status
git diff HEAD
git branch --show-current
git log -10 --oneline
gh repo view --json nameWithOwner,defaultBranchRef --jq '{repo: .nameWithOwner, defaultBranch: .defaultBranchRef.name}'
```

## 2. 检查已有指引
查看 `AGENTS.md`、`CLAUDE.md`、`CONTRIBUTING.md`、`.github/PULL_REQUEST_TEMPLATE.md`、`README.md`、`.gitignore`。若缺 `AGENTS.md` 且用户要求，则创建简明版（含项目概述、环境、结构、构建/测试/代码规范）。

## 3. 文档审计
- **README.md**：确保对新手有用，包含简介、特性、要求、安装、用法、构建、配置、结构、开发、许可。**必须中英双语**（可分段或并列）。
- **.gitignore**：按实际项目添加构建/依赖/IDE/OS/本地环境条目，勿忽略源码或必要文件。
- 不自动创建所有文件，只创建/更新与本次范围相关的。

## 4. 变更分类
`feature|bugfix|refactor|perf|docs|test|build|ci|chore`。只包含请求的变更、文档、.gitignore。

## 5. 分支
若当前在默认分支，则新建 `feature/<描述>` 等；否则保留当前分支。

## 6. 暂存
`git add <显式路径>` → `git status` + `git diff --cached` 确认。

## 7. 验证
运行项目支持的 test/lint/build。失败则报告并停止（除非用户要求继续）。

## 8. 提交
遵循现有约定（如 Conventional Commits）。`git commit -m "<消息>"`。

## 9. 推送
`git push -u origin <分支>`。若冲突，报告，不 rebase/force。

## 10. PR
按模板填写，标题清晰，正文含 Summary、文档变更、验证。创建：
```bash
gh pr create --base <默认分支> --head <分支> --title "<标题>" --body "<正文>"
```
不合并、不启用自动合并。

---

# Release 工作流（仅显式请求时执行）

## 11. 版本号（强制日期格式）
- **Tag 必须为 `vYYYYMMDD`**（如 v20260821），以北京时间为准。
- 检查 `git tag --list v<YYYYMMDD>` 及 `gh release view v<YYYYMMDD>`，若已存在则中止，禁止覆盖。
- 忽略项目文件中的版本号，禁止用户自定义。

## 12. 发布就绪
确认工作区干净（除无关改动）、提交正确、验证通过、资产已知、无密钥。

## 13. Release Notes
根据实际变更生成，格式：
```markdown
## What's Changed / 变更内容
- ...
## Documentation / 文档
- ...
## Validation / 验证
- ...
```
**必须中英双语**。

## 14. 创建 Release
- **Release title 必须与 tag 完全一致**（如 tag 为 `v20260821`，title 也必须为 `v20260821`），禁止自定义标题。
- ```bash
  gh release create v<YYYYMMDD> --title "v<YYYYMMDD>" --notes "<说明（双语）>"
  ```
- 若需草稿则加 `--draft`。不自动发布草稿。

## 15. 上传资产（强制纯英文文件名）
- **文件名仅允许**：`a-zA-Z0-9._-`，严禁中文、全角符号。
- 上传前校验每个文件名，若含非法字符则**中止**并提示重命名为纯英文。
- **exe 可执行文件禁止直接上传**：下载可能被杀毒软件拦截，徒增用户麻烦。对于打包结果为单个 exe 的项目，必须先用 zip 压缩为标准 ZIP 格式，再上传 ZIP 文件。
  - Windows：`powershell -Command "Compress-Archive -Path <exe> -DestinationPath <名称>.zip"` 或使用系统右键"压缩为 ZIP"。
  - ZIP 文件名遵循纯英文命名（如 `myapp-v20260821-win64.zip`）。
- 上传命令：`gh release upload v<YYYYMMDD> <file1> <file2> ...`
- **中文名只能发布后在网页端二次重命名**，严禁在 `gh release upload` 阶段使用。

## 16. 验证 Release
`gh release view v<YYYYMMDD>` 确认存在、标签、**title 与 tag 完全一致**、说明、资产正确。

---

# 失败处理
- 无变更 → 停止。
- 无关改动 → 不动。
- 密钥 → 中止。
- 验证失败 → 停止，不继续 PR/Release。
- 提交/推送/PR/Release 失败 → 报告，不强行修复、不覆盖、不删标签。

---

# 最终输出
仅返回结果：
```
Commit: <hash> <msg>
Branch: <分支>
Push: origin/<分支>
Pull Request: <URL> （如有）
Release: v<YYYYMMDD>
Release URL: <URL>
Assets: <列表>
Validation: <检查结果>
```

---

# 约束重申
- 保留无关改动。
- 不丢弃改动、不提交密钥、不空提交、不 force push、不改写历史、不合并PR、不删分支/仓库、不覆盖已有 Release。
- 显式暂存，审查差异，检查资产。
- README 和 Release Notes **必须中英双语**。
- Tag 强制 `vYYYYMMDD`，**Release title 必须与 tag 完全一致**，上传资产文件名纯英文，**exe 必须压缩为 ZIP 后上传**。