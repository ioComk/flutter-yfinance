# Shared Whiteboard

このファイルは、メインエージェントとサブエージェント間で共有する作業メモです。

## Usage Rules

- 作業開始前に必ず読む
- 共有すべき情報のみ簡潔に追記する
- 各エントリに日付（YYYY-MM-DD）と担当を明記する
- 既存情報を削除せず、更新時は `Superseded` を残す

## Decisions

- 2026-02-19 | Main Agent | iOS UI/UXを優先し、Androidは当面動作保証を優先する
- 2026-02-19 | Main Agent | Lint + GitHub Actions CI（format/analyze/test）を導入する
- 2026-02-20 | Main Agent | ダッシュボードUIを「ミニマル + スタイリッシュ」方針へ更新（背景演出を抑制し、カード/配色を統一）

## Tech Notes

- 2026-02-19 | Main Agent | Flutter 3.41.1 / Dart 3.11.0 / Xcode 26.2 / CocoaPods 1.16.2
- 2026-02-19 | Main Agent | iOSシミュレータ確認済み（`flutter devices` で検出）
- 2026-02-20 | Main Agent | `dart format --output=none --set-exit-if-changed .` / `flutter analyze` / `flutter test` を実行し全て成功

## Open Questions

- (none)

## Handoffs

- 2026-02-19 | Main Agent -> Librarian Agent | 実装変更時のREADME/AGENTS追従チェックを担当
- 2026-02-19 | Main Agent -> Tech Research Agent | 依存更新、Xcode互換、CI改善候補の継続調査を担当
