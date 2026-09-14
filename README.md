# SleepGuard

MacBookの蓋を閉じてもスリープさせない設定（`pmset -a disablesleep`）を、メニューバーから1クリックで切り替えるアプリ。
今どっちの状態かがアイコンで一目で分かる。

参考: https://qiita.com/shge/items/ae2f725be8009f786122

## アイコンの見方

同じ月マーク（`moon.zzz`）に、🚫と同じ斜線を被せるかどうかで区別する。

| 表示 | 状態 |
|---|---|
| 🌙 モノクロの月（斜線なし） | 通常。蓋を閉じるとスリープする |
| 🌙 **オレンジの月＋斜線** | スリープ無効中。蓋を閉じても起きたまま |
| 🌙 **赤の月＋斜線** | スリープ無効中 **かつバッテリー駆動** ＝電池が減り続ける警告 |

斜線はSF Symbolsに `moon.zzz.slash` が無いので自前で描いている（[Sources/main.swift](Sources/main.swift) の `Icon.slashed`）。

- 左クリック: 切り替え
- 右クリック（またはCtrl+クリック）: メニュー（状態表示・ログイン時に起動・文字ラベル表示・終了）

## アプリアイコン

メニューバーと同じ「月＋斜線」を、紺のグラデーションのタイルに載せたもの。作り直すときは:

```bash
./scripts/make-icon.sh   # Resources/AppIcon.icns を再生成
```

斜線の太さは `pointSize` に対する比率で持っていて、メニューバー側（[Sources/main.swift](Sources/main.swift) の `Icon`）と同じ値。アイコン用だけウェイトを `.medium` にして、小さいサイズでも潰れにくくしている。

## ビルドとインストール

```bash
./build.sh --install   # ビルドして /Applications に入れて起動（中間物は消す）
./build.sh             # build/SleepGuard.app に作るだけ
```

⚠️ **`build/SleepGuard.app` を残すとLaunchpadに同じアプリが2つ並ぶ** 。中間物もLaunch Servicesに登録されるため。`--install` は後始末（`lsregister -u` ＋削除）までやる。手で消すときは:

```bash
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u build/SleepGuard.app
rm -rf build/SleepGuard.app
```

## パスワード入力を不要にする（任意・推奨）

`pmset` はroot権限が要るので、何もしないと切り替えのたびに管理者パスワードを聞かれる。
**初回起動時に自動でセットアップを提案する** （メニューの「パスワード不要にする…」からも実行可）。
1回だけ管理者パスワードを入れれば、以降はクリックだけで切り替わる。

やっていること: `/etc/sudoers.d/sleepguard-<ユーザー名>` に、この2コマンドだけをNOPASSWD許可する行を書く。 **許可は許可でユーザー単位なので、ファイル名にもユーザー名を入れている** （共用Macで別アカウントが「設定済み」と誤認するのを防ぐ）。許可する相手はアプリが自分のユーザー名を明示的に渡す＝ **管理者が代わりにパスワードを入れても、許可されるのはアプリを使っている本人** 。

```
<ユーザー名> ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0
```

取り消しはアプリの右クリックメニュー「パスワード不要の設定を取り消す…」からもできる（スクリプトはアプリに同梱している）。

`visudo -cf` で構文チェックを通したファイルだけを設置する。許可されるのはこの2コマンドだけで、
`sudo pmset -a sleep 0` や `sudo ls` は従来どおりパスワードを要求する（確認済み）。ターミナルからやるなら:

```bash
sudo bash scripts/install-sudoers.sh     # 設定
sudo bash scripts/uninstall-sudoers.sh   # 取り消し
```

## 注意

- `disablesleep 1` は **AC電源に繋いでいなくてもスリープしなくなる** 。バッテリー駆動のまま蓋を閉じると電池が減り続けて発熱する（アプリは赤アイコンで警告するが、自動では戻さない）。
- この設定は **再起動しても残る** 。アプリを終了しても設定自体は生きている。
- 状態は `ioreg -n IOPMrootDomain -r -d 1 | grep SleepDisabled` でも確認できる。

## 仕組み

- 状態の読み取り: IORegistryの `IOPMrootDomain.SleepDisabled` をアプリ内から直読み（2秒ポーリング＋スリープ復帰時＋メニュー展開時に更新）。ターミナルで `sudo pmset` を叩いて変えた場合も追従する。
- 切り替え: `sudo -n pmset -a disablesleep 0|1`。sudoers未設定なら管理者パスワードのダイアログにフォールバック。

## 実装メモ（ハマりどころ）

- **アイコンを自前で描くと `alignmentRect` が落ちてメニューバー上で位置がズレる** 。`lockFocus` で作ったビットマップは元のSFシンボルが持つ `alignmentRect` を引き継がないので、月が **実測4px（2pt）下にズレていた（`SymbolConfiguration` を揃えた後の値＝この4pxは `alignmentRect` 単独の効果）** 。`out.alignmentRect = base.alignmentRect` で解消（実測：斜線がかからない左3/5/7列の上端が 32/30/29 → 32/30/29 で一致）。あわせて2状態で **同じ `SymbolConfiguration`** を使う（`.semibold` と `.regular` を混ぜると 17×19pt と 16×18pt になって1ptズレる）。
- **`sudo -n -l <cmd>` は「パスワード不要か」の判定には向かない** 。`man sudoers` の `listpw` 既定値は `any` ＝ NOPASSWD 行が1つでもあれば `sudo -l` 自体がパスワード無しで通るので、 **別の用途で入れた NOPASSWD 行があると誤判定する** 。`/etc/sudoers.d/sleepguard-<ユーザー名>` の有無で判定する方が単純で確実。
  - ⚠️ **訂正の記録** ：当初これを「管理者は元々そのコマンドを実行してよいので常に exit 0 を返す＝初回の提案ダイアログが出なかった原因」と書いたが **間違い** 。`sudo -n -l pmset…` が exit 0 を返した測定は **sudoersファイルが出来た後（17:53）** に取ったもので、ファイル作成前の挙動ではない。ファイルのmtimeは17:51＝ **提案ダイアログは最初からちゃんと出ていて、それを承認した結果** 。「画面にダイアログが見えない」→「判定バグに違いない」と決め打ちして、 **測定した時刻と因果の順序を確かめなかった** のが誤りの原因。
- **LSUIElementのアプリはダイアログが裏に隠れうる** 。モーダルの間だけ `setActivationPolicy(.regular)` に切り替えるようにしてある（ただし ⚠️ **上記のとおり「隠れていた」事実は観測できていない** ＝予防的な対処）。
- **`osascript` の終了コードは成功0／失敗は全部1に潰れる** 。内側のシェルの終了コード（3でも127でも）もユーザーのキャンセル（-128）も区別できない。→ キャンセル判定は stderr の `(-128)` を見る、インストール成否は `/etc/sudoers.d/sleepguard-<ユーザー名>` が出来たかで見る。実測：`osascript -e 'error number -128'` → stderr `... (-128)` / exit 1、`osascript -e 'do shell script "exit 3"'` → stderr `... (3)` / exit 1。
- **`Timer.scheduledTimer` は `.default` モードにしか入らない** ＝メニューを開いている間・モーダル表示中は止まる。`RunLoop.main.add(timer, forMode: .common)` で登録し直している。
- 見た目の確認用に `SLEEPGUARD_FAKE=1` を環境変数で渡すと、実際の設定を変えずにスリープ無効時のアイコンを表示できる。

## 配布について

ダウンロードページ: https://hiroki-soeno.github.io/sleepguard/ （`docs/` をGitHub Pagesで公開）

- **Developer ID署名・公証は付けていない** （Apple Developer Program＝年99米ドルが必要）。そのため **ダウンロードした人は初回だけ「システム設定 → プライバシーとセキュリティ → このまま開く」が要る** 。macOS 15 Sequoia以降、Control+クリックの抜け道は使えない
- 手元で `./build.sh` したものには `com.apple.quarantine` が付かないので警告は出ない
- 公証を付けるなら `CODESIGN_IDENTITY="Developer ID Application: ..." ./build.sh` → `xcrun notarytool submit` → `xcrun stapler staple`（Hardened Runtimeは build.sh が付ける）
- ⚠️ **ad-hoc署名はビルドのたびに識別子が変わりうる** ＝ログイン項目の承認がアップデートで外れることがある。継続配布するならDeveloper ID署名が要る
- ⚠️ **UIは日本語のみ** 。英語話者に配るなら要ローカライズ
