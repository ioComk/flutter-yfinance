# flutter_yfinance

FlutterでiOSを優先して開発するアプリプロジェクトです。  
GitHub CI（Lint/Analyze/Test）を導入済みです。

## 開発方針

- iOSのUI/UXを最優先で実装する
- Androidは当面「動作保証（クラッシュしない）」を最低ラインにする
- 必要が出るまでAndroid固有のUI最適化は後回し
- Web対応は可能だが、主対象はiOS

## 前提環境（このリポジトリで確認済み）

- Flutter: `3.41.1`（stable）
- Dart: `3.11.0`
- Xcode: `26.2`
- CocoaPods: `1.16.2`
- Ruby: `3.3.6`（rbenv）

## セットアップ

```bash
flutter pub get
```

## 実行方法

### iOS Simulator（推奨）

```bash
open -a Simulator
flutter devices
flutter run -d <ios_simulator_device_id>
```

### iOS実機

1. `ios/Runner.xcworkspace` をXcodeで開く
2. `Signing & Capabilities` で `Team` を設定
3. `Bundle Identifier` を一意に設定
4. 初回ビルド後、CLIで実行

```bash
flutter devices
flutter run -d <ios_device_id>
```

### Android Emulator（必要時のみ）

```bash
flutter devices
flutter run -d <android_device_id>
```

### Web

```bash
flutter run -d chrome
flutter build web
```

## 品質管理

ローカル確認:

```bash
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test
```

## CI

GitHub Actionsで以下を実行します。

- `dart format --output=none --set-exit-if-changed .`
- `flutter analyze`
- `flutter test`

ワークフロー: `.github/workflows/ci.yml`

## リポジトリ

- GitHub: [ioComk/flutter-yfinance](https://github.com/ioComk/flutter-yfinance)
