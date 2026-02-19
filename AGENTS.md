# AGENTS.md

このファイルは、このリポジトリで作業するエージェント/開発者向けの実行ルールです。

## 目的

- FlutterアプリをiOS優先で開発する
- iOSの体験品質を最優先で担保する
- Androidは当面、機能互換と安定動作を優先する

## 優先順位

1. iOS UI/UX
2. iOS実機/シミュレータでの再現性
3. CIを壊さない変更
4. Android/Web互換

## 実装ポリシー

- iOS中心の設計を採用する
- 必要な箇所のみプラットフォーム分岐する
- 不要なAndroid専用最適化は先行実装しない
- 既存Lint/CIを通ることをマージ条件にする

## 必須チェック（ローカル）

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## CI

- Workflow: `.github/workflows/ci.yml`
- 実行内容:
  - format check
  - analyze
  - test

## 実行コマンド

### iOS Simulator

```bash
open -a Simulator
flutter devices
flutter run -d <ios_simulator_device_id>
```

### iOS実機

```bash
flutter devices
flutter run -d <ios_device_id>
```

補足: 初回のみXcodeで署名設定（Team/Bundle Identifier）が必要。

### Android（必要時）

```bash
flutter run -d <android_device_id>
```

### Web（必要時）

```bash
flutter run -d chrome
```

## 禁止/注意

- CIを壊す変更をそのままpushしない
- iOS優先方針に反する大規模なAndroid最適化を先行しない
- 依存追加時は影響範囲（iOS/Android/Web）を明記する

## Available Agents

- Librarian Agent: `/Users/iocomk/flutter-yfinance/.agents/librarian-agent.md`
- Tech Research Agent: `/Users/iocomk/flutter-yfinance/.agents/tech-research-agent.md`

## Shared Whiteboard

- Path: `/Users/iocomk/flutter-yfinance/.agents/whiteboard.md`
- 目的: メインエージェントとサブエージェント間の情報共有
- ルール:
  - 作業開始前に必ず最新内容を読む
  - 共有が必要な決定事項、調査結果、未解決課題を追記する
  - 追記は時系列で行い、日付と担当エージェント名を明記する
  - 古い情報を消さず、必要なら `Superseded` として上書き理由を残す
