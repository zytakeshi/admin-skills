# admin-skills

[English](README.md) | [日本語](README.ja.md) | **[中文](README.zh.md)**

---

一套面向 Claude Code 的系统管理和 DevOps 技能集。一个 `/命令` 搞定部署、git 工作流和代码审查。

## 为什么用这些技能？

- **`/deploy`** — 零停机部署，强制备份、差异检测、自动清理缓存。再也不会忘记回滚方案。
- **`/commit-push`** — 分析 diff，生成规范的 commit message，安全推送。告别 "fix stuff" 提交。
- **`/create-pr`** — 创建 PR 后自动由 [OpenAI Codex](https://chatgpt.com/codex) 审查。审查完成后，Claude 自动读取反馈、修复认可的问题、推送修复，然后询问你是否合并 — 全流程端到端自动化。
- **`/html-specialist`** — 生成**单文件、自包含、带动画**的 HTML 讲解页（暗色滚动叙事、CJK 字体兼容、零依赖），用于讲解概念、系统、数据或产品。
- **`/codex`** — 桥接 OpenAI Codex CLI，用于代码审查、设计咨询、Bug 调查、安全审计与第二意见。流式推送事件，最终回答按调用 ID 存储到独立结果文件，超越 diff 本身发现跨层集成问题。
- **`/codexloop`** — 用 Codex 做迭代审查＋修复循环：Codex 审查 → Claude 修复认可的问题 → 再审查 → 直到代码干净或双方达成"诚实的分歧"。无固定迭代上限。
- **`/codex-test`** — 把无头/无人值守的浏览器冒烟或 e2e 测试卸载给 Codex CLI。它驱动隔离的 Playwright 浏览器（仅在需要时接入已登录的 Chrome 会话），可修改代码并重跑直到流程通过，流式推送进度，并报告 PASS/FAIL 结论及所做改动。
- **`/fleet-review`** — 派出 10〜15 个只读子代理并行扫描代码库，输出按严重度排序的审计报告。语言无关。纯计划阶段——零文件改动。
- **`/team`** — 编排代理团队并行实施计划、规格或多文件任务。自动拆解工作、在 tmux 面板里生成带作用域的队员、整合各方输出。
- **`/finish-translation`** — 自动检测项目的 i18n 框架（ARB、JSON/i18next、.strings、.xcstrings、gettext、YAML/Rails、Android XML、.resx），并执行翻译传播、审计或硬编码字符串扫描。

> **注意（2026年3月31日起）：** Codex 代码审查现已计入常规 Codex 使用额度，不再享有独立配额。频繁使用代码审查可能会更快达到 Codex 整体限额。详见 [OpenAI 公告](https://chatgpt.com/codex)。

## 安装

```bash
npx skills add zytakeshi/admin-skills
```

安装特定技能：

```bash
npx skills add zytakeshi/admin-skills@deploy
npx skills add zytakeshi/admin-skills@commit-push
npx skills add zytakeshi/admin-skills@create-pr
npx skills add zytakeshi/admin-skills@html-specialist
npx skills add zytakeshi/admin-skills@codex
npx skills add zytakeshi/admin-skills@codexloop
npx skills add zytakeshi/admin-skills@codex-test
npx skills add zytakeshi/admin-skills@fleet-review
npx skills add zytakeshi/admin-skills@team
npx skills add zytakeshi/admin-skills@finish-translation
```

## 可用技能

| 技能 | 描述 |
|------|------|
| [deploy](skills/deploy/) | 通过 SSH/SCP 部署到远程服务器，自带备份、差异检测、缓存清理和冒烟测试 |
| [commit-push](skills/commit-push/) | 分析改动，生成 commit message，一键暂存、提交、推送 |
| [create-pr](skills/create-pr/) | PR 全生命周期自动化：提交、推送、创建 PR、等待 Codex 审查、修复问题、合并 |
| [html-specialist](skills/html-specialist/) | 生成单文件动画 HTML 讲解页 — 滚动叙事、CJK 兼容、零依赖 |
| [codex](skills/codex/) | 桥接 OpenAI Codex CLI，做代码审查、设计咨询、安全审计与第二意见，带进度流式推送 |
| [codexloop](skills/codexloop/) | 用 Codex 做迭代审查＋修复循环，直到代码干净或双方达成诚实分歧 |
| [codex-test](skills/codex-test/) | 把无头/无人值守的浏览器冒烟或 e2e 测试卸载给 Codex CLI — Playwright 优先（隔离浏览器），可改代码并重跑，报告 PASS/FAIL |
| [fleet-review](skills/fleet-review/) | 派出 10〜15 个只读子代理并行审计代码库，纯计划阶段、语言无关 |
| [team](skills/team/) | 编排代理团队并行实施：拆解 → tmux 面板生成队员 → 整合输出 |
| [finish-translation](skills/finish-translation/) | 自动检测 i18n 框架，传播 / 审计 / 扫描全部 locale 的翻译与硬编码字符串 |

## 使用方法

安装后，在 Claude Code 中使用以下技能：

- `/deploy` — 执行部署工作流
- `/commit-push` — 分析改动、提交、推送
- `/create-pr` — 创建 PR 并自动接入 Codex 代码审查
- `/html-specialist` — 生成单文件动画 HTML 讲解页
- `/codex` — 调用 OpenAI Codex CLI 做审查 / 咨询
- `/codexloop` — Codex 迭代审查＋修复循环
- `/codex-test` — 把无头浏览器冒烟 / e2e 测试卸载给 Codex
- `/fleet-review` — 用 10〜15 个并行子代理审计代码库
- `/team` — 启动代理团队实施多文件任务
- `/finish-translation` — 同步 / 审计所有 locale 的翻译

## 相关项目

- [sing-box-skills](https://github.com/zytakeshi/sing-box-skills) — sing-box 源码构建 + 将 v2ray/clash 订阅转换为 Sing-box 配置的技能集
- [statusline4claudecode](https://github.com/zytakeshi/statusline4claudecode) — Claude Code 自定义状态栏，实时显示 token 用量、费用和模型信息
