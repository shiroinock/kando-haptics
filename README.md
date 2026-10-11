# Kando Haptics

Kandoの円形メニューにMagic Trackpadの触覚フィードバックを追加する、独立したmacOSバックグラウンドアプリの試作。MIT License。

Kando本体の改造は不要です。ローカルWebSocketでメニュー操作を購読し、Appleの公開AppKit APIで触覚を要求します。Kandoの公式製品ではありません。

## 起動

1. [Kando](https://kando.menu/) 3.xを起動します。この試作はWebSocket API v2専用です。
2. `Kando Haptics.app`を開きます。
3. アプリを再度開くと設定・診断画面が表示されます。接続済みになったことを確認します。
   メニューバーやDockにはアイコンを表示しません。画面を閉じても触覚処理は継続し、停止するときは画面内の「終了」を押します。
4. Magic Trackpadに指を置き、Kandoのメニューの項目を跨ぎます。

Kandoの接続情報は通常 `~/Library/Application Support/kando/ipc-info.json` にあります。起動順は自由で、Kandoの終了・再起動後は2秒間隔で再接続を試みます。ポータブル構成など別の保存先を使う場合は、実行ファイルへ `--ipc-info /absolute/path/ipc-info.json` を渡せます。

## 動作

- 項目のホバー切り替え: `.alignment`
- 選択・サブメニューを開く: `.generic`（設定で無効化できます）
- 中央・親へのホバー、メニューを閉じる: 発火せずホバー状態をリセット
- 同一項目の重複通知と40ms未満のホバー連発を抑制
- 「触覚をテスト」は3秒後に発火。その間に指をTrackpadへ戻してください。

本アプリ自体はAccessibility権限もグローバル入力監視も使用しません。Kandoが必要とする権限は別途Kando側で設定してください。

## 検証範囲と制約

このApple Silicon Macでビルドと13ケースのイベントルーティングテストが通過しました。さらに、ローカルの模擬WebSocketサーバーで購読要求、イベント受信、重複通知の抑制、接続情報の遅延生成、切断後の再接続を検証しました。

2026-10-12、Nixで導入したKando 3.0.0とのライブ連携を確認しました。診断画面の「接続済み」、実際のメニュー操作からの56件のイベント受信、53回の触覚リクエストを確認しました。ユーザーによるMagic Trackpadの実機確認でも、項目を跨ぐ際の「カチッ」という触覚を感じることを確認できました。診断画面の表示も確認済みです。他の機種・接続方式・macOSバージョンでの互換性やレイテンシは未測定です。

AppKitは触覚の「要求」を送るAPIです。macOSの判断や指の接触状態により要求が抑制されるため、診断画面のリクエスト数は実際に振動した回数を表しません。公開APIで振動の強度・波形・対象デバイスを指定していません。常駐アプリからの要求が安定して出るかが、この試作の主要な確認事項です。

接続・イベント受信が正常でも振動しない場合は、「触覚をテスト」で切り分けます。外部アプリからの発火が成立しなければ、KandoのmacOSネイティブアドオンへ組み込む方式を次の候補とします。

このローカルビルドはad-hoc署名です。公開配布用のDeveloper ID署名・公証は行っていません。macOS 13以降を対象にしていますが、他のOSバージョンやIntel Macでは未検証です。

## ソースからビルド

Xcode Command Line Toolsが必要です。外部パッケージ依存はありません。

```sh
git clone https://github.com/shiroinock/kando-haptics.git
cd kando-haptics
bash build.sh
open "Kando Haptics.app"
```

連携テストはビルド後に `python3 Tests/mock_ipc_test.py` で実行できます。Python 3の標準ライブラリだけを使用し、実際の触覚は要求しません。

`build.sh` は13ケースのルーティングテストも実行します。`--diagnostics-only` は触覚を要求せず、イベントの処理結果だけを表示する開発用オプションです。

## 調査元

Kando commit `ee064d3a2077095cd172344f6ca439888f583f2e`、WebSocket API v2。

- [Kando WebSocket API](https://kando.menu/ipc-interface/)
- [IPC Observer](https://github.com/kando-menu/kando/blob/ee064d3a2077095cd172344f6ca439888f583f2e/src/common/ipc/ipc-observer-client.ts)
- [メニューのホバー処理](https://github.com/kando-menu/kando/blob/ee064d3a2077095cd172344f6ca439888f583f2e/src/menu-renderer/menu.ts#L793)
