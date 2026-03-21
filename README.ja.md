# admin-skills

[English](README.md) | **[日本語](README.ja.md)** | [中文](README.zh.md)

---

Claude Code 向けのシステム管理・DevOps スキル集です。デプロイ、git ワークフロー、コードレビューを `/コマンド` 一つで自動化します。

## このスキルを使うメリット

- **`/deploy`** — バックアップ必須のゼロダウンタイムデプロイ。差分検出と自動キャッシュクリア付き。ロールバック忘れの心配なし。
- **`/commit-push`** — diff を分析して conventional commit メッセージを生成し、安全にプッシュ。「fix stuff」コミットとはお別れ。
- **`/create-pr`** — PR を作成し、[OpenAI Codex](https://chatgpt.com/codex) が自動レビュー。Codex レビューは ChatGPT サブスクリプションの**専用枠**を使用し、通常の Codex タスク制限を消費しません。すべての PR で無料の高品質 AI コードレビューを実現。レビュー完了後、Claude がフィードバックを読み取り、同意した指摘を修正してプッシュし、マージを提案 — エンドツーエンドで完全自動化。

## インストール

```bash
npx skills add zytakeshi/admin-skills
```

特定のスキルのみインストール:

```bash
npx skills add zytakeshi/admin-skills@deploy
npx skills add zytakeshi/admin-skills@commit-push
npx skills add zytakeshi/admin-skills@create-pr
```

## 利用可能なスキル

| スキル | 説明 |
|--------|------|
| [deploy](skills/deploy/) | SSH/SCP でリモートサーバーにデプロイ。バックアップ、差分検出、キャッシュクリア、スモークテスト付き |
| [commit-push](skills/commit-push/) | 変更を分析し、コミットメッセージを生成、ステージ・コミット・プッシュを一括実行 |
| [create-pr](skills/create-pr/) | PR の全ライフサイクルを自動化: コミット、プッシュ、PR 作成、Codex レビュー待機、修正、マージ |

## 使い方

インストール後、Claude Code で以下のスキルを使用できます:

- `/deploy` — デプロイワークフローを実行
- `/commit-push` — 変更を分析、コミット、プッシュ
- `/create-pr` — Codex コードレビュー付き PR を作成

## 関連プロジェクト

- [statusline4claudecode](https://github.com/zytakeshi/statusline4claudecode) — Claude Code 用カスタムステータスライン。トークン使用量、コスト、モデル情報をリアルタイム表示
