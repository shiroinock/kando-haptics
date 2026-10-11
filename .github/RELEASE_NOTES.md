Kandoの円形メニューにMagic Trackpadの触覚フィードバックを追加するmacOS補助アプリです。

## インストール

1. `Kando-Haptics-*-macOS-arm64.zip` をダウンロードして展開します。
2. `Kando Haptics.app` をApplicationsへ移動します。
3. Kando 3.xとKando Hapticsを起動します。

Apple Silicon向け、macOS 13以降を対象とするビルドです。Intel版は配布していません。KandoのWebSocket API v2を使用します。

メニューバーやDockにはアイコンを表示しません。Kando Hapticsを再度開くと、設定・接続状況・触覚テスト・終了を操作できます。

## 署名と検証

ad-hoc署名です。Developer ID署名・Appleの公証は未実施です。初回起動については[Appleの案内](https://support.apple.com/ja-jp/102445)を参照してください。

GitHub Actionsでビルドし、13ケースのルーティングテスト、配布ZIPを展開したアプリの署名検証、模擬WebSocketサーバーでの購読・重複抑制・接続情報待ち・再接続テストを実行しています。CIでは実際の触覚は検証できません。

ZIPと `SHA256SUMS.txt` を同じフォルダに置き、`shasum -a 256 -c SHA256SUMS.txt` で照合できます。アプリ内にMITライセンスを同梱しています。
