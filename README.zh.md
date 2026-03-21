# admin-skills

[English](README.md) | [日本語](README.ja.md) | **[中文](README.zh.md)**

---

一套面向 Claude Code 的系统管理和 DevOps 技能集。一个 `/命令` 搞定部署、git 工作流和代码审查。

## 为什么用这些技能？

- **`/deploy`** — 零停机部署，强制备份、差异检测、自动清理缓存。再也不会忘记回滚方案。
- **`/commit-push`** — 分析 diff，生成规范的 commit message，安全推送。告别 "fix stuff" 提交。
- **`/create-pr`** — 创建 PR 后自动由 [OpenAI Codex](https://chatgpt.com/codex) 审查。Codex 审查使用 ChatGPT 订阅的**独立配额**，不消耗正常的 Codex 任务额度。每个 PR 都能获得免费的高质量 AI 代码审查。审查完成后，Claude 自动读取反馈、修复认可的问题、推送修复，然后询问你是否合并 — 全流程端到端自动化。

## 安装

```bash
npx skills add zytakeshi/admin-skills
```

安装特定技能：

```bash
npx skills add zytakeshi/admin-skills@deploy
npx skills add zytakeshi/admin-skills@commit-push
npx skills add zytakeshi/admin-skills@create-pr
```

## 可用技能

| 技能 | 描述 |
|------|------|
| [deploy](skills/deploy/) | 通过 SSH/SCP 部署到远程服务器，自带备份、差异检测、缓存清理和冒烟测试 |
| [commit-push](skills/commit-push/) | 分析改动，生成 commit message，一键暂存、提交、推送 |
| [create-pr](skills/create-pr/) | PR 全生命周期自动化：提交、推送、创建 PR、等待 Codex 审查、修复问题、合并 |

## 使用方法

安装后，在 Claude Code 中使用以下技能：

- `/deploy` — 执行部署工作流
- `/commit-push` — 分析改动、提交、推送
- `/create-pr` — 创建 PR 并自动接入 Codex 代码审查

## 相关项目

- [statusline4claudecode](https://github.com/zytakeshi/statusline4claudecode) — Claude Code 自定义状态栏，实时显示 token 用量、费用和模型信息
