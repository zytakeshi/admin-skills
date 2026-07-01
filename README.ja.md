# admin-skills

[English](README.md) | **[日本語](README.ja.md)** | [中文](README.zh.md)

---

Claude Code 向けのシステム管理・DevOps スキル集です。デプロイ、git ワークフロー、コードレビューを `/コマンド` 一つで自動化します。

## このスキルを使うメリット

- **`/deploy`** — バックアップ必須のゼロダウンタイムデプロイ。差分検出と自動キャッシュクリア付き。ロールバック忘れの心配なし。
- **`/commit-push`** — diff を分析して conventional commit メッセージを生成し、安全にプッシュ。「fix stuff」コミットとはお別れ。
- **`/create-pr`** — PR を作成し、[OpenAI Codex](https://chatgpt.com/codex) が自動レビュー。レビュー完了後、Claude がフィードバックを読み取り、同意した指摘を修正してプッシュし、マージを提案 — エンドツーエンドで完全自動化。
- **`/html-specialist`** — コンセプト、システム、データ、プロダクトを解説する**単一ファイルのアニメーション HTML**（ダークモード・スクロールテリング・CJK 対応・依存ゼロ）を生成。
- **`/codex`** — OpenAI Codex CLI への橋渡し。コードレビュー、設計相談、バグ調査、セキュリティ監査、セカンドオピニオン用。イベントをストリーミングで通知し、最終回答を実行ごとの結果ファイルに保存。diff の外側の cross-cutting な統合問題も指摘。
- **`/codexloop`** — Codex を使った反復レビュー＆修正ループ。Codex がレビュー → 合意した指摘を Claude が修正 → 再レビュー → きれいになるか正直な合意不能点に到達するまで継続。回数制限なし。
- **`/codex-test`** — ヘッドレス/無人のブラウザ・スモーク/e2e テストを Codex CLI にオフロード。隔離された Playwright ブラウザを操作（必要な場合のみログイン済み Chrome セッションに接続）し、フローが通るまでコードを修正して再実行可能。進捗をストリーミングし、PASS/FAIL の判定と加えた変更を報告。
- **`/fleet-review`** — 10〜15 体の読み取り専用サブエージェントを並列展開し、コードベース全体をスキャンしてランク付き監査レポートを生成。言語非依存。純粋な計画フェーズ — ファイルは一切変更しない。
- **`/team`** — エージェントチームを編成して計画書・仕様書・大規模タスクを並列実装。作業を分解し、スコープ付きチームメイトを tmux ペインで起動し、成果物を統合。
- **`/finish-translation`** — プロジェクトの i18n フレームワーク（ARB・JSON/i18next・.strings・.xcstrings・gettext・YAML/Rails・Android XML・.resx）を自動検出し、翻訳の伝播・監査・ハードコード文字列検出を実行。
- **`/ask-grok`** — 既存の X Premium / SuperGrok サブスクリプション（APIキー不要）で Grok（xAI）にリアルタイムの Web・X/Twitter 情報を照会。「最新の〜は？」「速報」「ツールの最新バージョン」「Xで〜について何と言われている？」を公式 Grok CLI 経由で Grok にルーティングし、回答をソースリンク付きでそのまま表示。
- **`/cdp-chrome`** — Chrome 136+ で Chrome DevTools（CDP）ブラウザ自動化を**無人で**実行。専用のログイン済み Chrome インスタンスに `--browserUrl` で接続するため、「Allow remote debugging?」のネイティブ許可ダイアログが一切出ず、`chrome-devtools-mcp` / Puppeteer / Playwright が接続時にハングしなくなる。`cdp-chrome` ヘルパー（start / reseed / status / config）を同梱。macOS。
- **`/fable5`** — フロンティア級モデル（Claude の Fable 5 など）のセッションを有効に使うためのガイド。ある作業が "one-way door"（後戻りにコストがかかる決定）としてフロンティア級を使う価値があるか判断し、セッション前にコンテキストを圧縮し、フロンティアモデルに統治アーティファクト（PRD・API契約・データモデル・検証ルーブリック）を書かせてから、実装を `/codex`、検証を `/codexloop` に引き継ぐ。

> **注意（2026年3月31日）:** Codex コードレビューは専用枠ではなく、通常の Codex 使用量にカウントされるようになりました。コードレビューを多用すると、Codex の全体制限に早く達する場合があります。詳細は [OpenAI の告知](https://chatgpt.com/codex)を参照してください。

## インストール

```bash
npx skills add zytakeshi/admin-skills
```

特定のスキルのみインストール:

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
npx skills add zytakeshi/admin-skills@ask-grok
npx skills add zytakeshi/admin-skills@cdp-chrome
npx skills add zytakeshi/admin-skills@fable5
```

## 利用可能なスキル

| スキル | 説明 |
|--------|------|
| [deploy](skills/deploy/) | SSH/SCP でリモートサーバーにデプロイ。バックアップ、差分検出、キャッシュクリア、スモークテスト付き |
| [commit-push](skills/commit-push/) | 変更を分析し、コミットメッセージを生成、ステージ・コミット・プッシュを一括実行 |
| [create-pr](skills/create-pr/) | PR の全ライフサイクルを自動化: コミット、プッシュ、PR 作成、Codex レビュー待機、修正、マージ |
| [html-specialist](skills/html-specialist/) | 単一ファイルのアニメーション HTML 解説ページを生成 — スクロールテリング、CJK 対応、依存ゼロ |
| [codex](skills/codex/) | OpenAI Codex CLI へのブリッジ。コードレビュー・設計相談・セキュリティ監査・セカンドオピニオン、進捗ストリーミング付き |
| [codexloop](skills/codexloop/) | Codex を使った反復レビュー＆修正ループ。きれいになるか正直な合意不能点まで継続 |
| [codex-test](skills/codex-test/) | ヘッドレス/無人のブラウザ・スモーク/e2e テストを Codex CLI にオフロード — Playwright 優先（隔離ブラウザ）、コード修正＆再実行可、PASS/FAIL を報告 |
| [fleet-review](skills/fleet-review/) | 10〜15 体の読み取り専用サブエージェントを並列展開し、コードベース全体を監査。純粋な計画フェーズで、言語非依存 |
| [team](skills/team/) | エージェントチームを編成して並列実装。作業分解 → tmux ペインでチームメイト起動 → 成果物統合 |
| [finish-translation](skills/finish-translation/) | i18n フレームワークを自動検出し、全ロケールへの翻訳伝播・監査・ハードコード文字列検出を実行 |
| [ask-grok](skills/ask-grok/) | 公式 Grok CLI（サブスク OAuth、APIキー不要）で Grok（xAI）にリアルタイム Web・X/Twitter 情報を照会 — 最新リリース、速報、Xの反応を、ソースリンク付きでそのまま表示 |
| [cdp-chrome](skills/cdp-chrome/) | Chrome 136+ で Chrome DevTools（CDP）自動化を無人実行 — `--browserUrl` で専用のログイン済み Chrome に接続し、「Allow remote debugging?」ダイアログを根絶。`cdp-chrome` ヘルパー（start / reseed / status / config）同梱。macOS |
| [fable5](skills/fable5/) | フロンティア級モデルのセッションを有効に使うためのガイド — one-way-door 判定、コンテキストパック圧縮、サブエージェントとして呼び出して戻す運用、`/codex` + `/codexloop` への引き継ぎ |

## 使い方

インストール後、Claude Code で以下のスキルを使用できます:

- `/deploy` — デプロイワークフローを実行
- `/commit-push` — 変更を分析、コミット、プッシュ
- `/create-pr` — Codex コードレビュー付き PR を作成
- `/html-specialist` — 単一ファイルのアニメーション HTML 解説ページを構築
- `/codex` — OpenAI Codex CLI を呼んでレビュー / 相談
- `/codexloop` — Codex 反復レビュー＆修正ループ
- `/codex-test` — ヘッドレスのブラウザ・スモーク / e2e テストを Codex にオフロード
- `/fleet-review` — 10〜15 体の並列サブエージェントでコードベース監査
- `/team` — エージェントチームを起動してマルチファイルタスクを実装
- `/finish-translation` — 全ロケールの翻訳を同期 / 監査
- `/ask-grok` — Grok からライブ Web・X 情報を取得し、ソース付きでそのまま表示
- `/cdp-chrome` — 無人の Chrome DevTools 自動化をセットアップ（専用のログイン済み Chrome、許可ダイアログなし）
- `/fable5` — その作業がフロンティア級モデルのセッションに値するか判断し、有効に使う

## 関連プロジェクト

- [sing-box-skills](https://github.com/zytakeshi/sing-box-skills) — sing-box のソースビルド + v2ray/clash 購読を Sing-box 設定に変換するスキル
- [statusline4claudecode](https://github.com/zytakeshi/statusline4claudecode) — Claude Code 用カスタムステータスライン。トークン使用量、コスト、モデル情報をリアルタイム表示
