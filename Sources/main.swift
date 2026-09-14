import Cocoa
import IOKit
import IOKit.ps
import ServiceManagement

// MARK: - 現在の状態を読む（プロセスを起こさずIORegistryから直読み）

enum PowerSource { case ac, battery, unknown }

enum PMState {
    /// true = スリープ無効中（蓋を閉じてもスリープしない）
    /// SLEEPGUARD_FAKE=1/0 を環境変数で渡すと見た目の確認用に状態を偽装できる
    static func sleepDisabled() -> Bool {
        if let fake = ProcessInfo.processInfo.environment["SLEEPGUARD_FAKE"] { return fake == "1" }
        let svc = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard svc != 0 else { return false }
        defer { IOObjectRelease(svc) }
        let v = IORegistryEntryCreateCFProperty(svc, "SleepDisabled" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue()
        return (v as? NSNumber)?.boolValue ?? false
    }

    static func powerSource() -> PowerSource {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(blob)?.takeRetainedValue() as String?
        else { return .unknown }
        switch type {
        case "AC Power": return .ac
        case "Battery Power": return .battery
        default: return .unknown
        }
    }
}

// MARK: - アイコン（同じ月マークに斜線を被せる＝一目で分かる）

enum Icon {
    private static let pointSize: CGFloat = 14
    private static let symbol = "moon.zzz"

    /// 2つの状態で **同じシンボル設定** を使う。これを揃えないとグリフの寸法が変わって月の位置がズレる。
    private static func base(_ color: NSColor?, _ description: String) -> NSImage? {
        var config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        if let color {
            config = NSImage.SymbolConfiguration(paletteColors: [color]).applying(config)
        }
        return NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
    }

    /// 通常時：テンプレート（メニューバーの色に自動追従）
    static func plain() -> NSImage? {
        let img = base(nil, "通常（蓋を閉じるとスリープ）")
        img?.isTemplate = true
        return img
    }

    /// スリープ無効時：同じ月マークに🚫の斜線を重ねて着色（サイズも位置も素のシンボルと同一）
    static func slashed(_ color: NSColor) -> NSImage? {
        guard let base = base(color, "スリープ無効中") else { return nil }

        let size = base.size
        let out = NSImage(size: size)
        out.lockFocus()
        defer { out.unlockFocus() }
        base.draw(in: NSRect(origin: .zero, size: size))
        guard let ctx = NSGraphicsContext.current else { return base }

        let angle: CGFloat = 60 * .pi / 180
        let half = min(size.width, size.height) * 0.80
        let dx = cos(angle) * half, dy = sin(angle) * half
        let cx = size.width / 2, cy = size.height / 2
        let path = NSBezierPath()
        path.move(to: NSPoint(x: cx - dx, y: cy - dy))
        path.line(to: NSPoint(x: cx + dx, y: cy + dy))
        path.lineCapStyle = .round

        // 斜線の下地を一度くり抜いてから線を引く（SF Symbolsのslashと同じ見え方）
        ctx.compositingOperation = .destinationOut
        path.lineWidth = 3.0
        NSColor.black.setStroke()
        path.stroke()

        ctx.compositingOperation = .sourceOver
        path.lineWidth = 1.5
        color.setStroke()
        path.stroke()

        // lockFocus で作ったビットマップは alignmentRect を持たないので、
        // 元のSFシンボルのものを引き継ぐ（これが無いとメニューバー上で月が数px下にズレる）
        out.alignmentRect = base.alignmentRect
        out.isTemplate = false
        return out
    }
}

// MARK: - 切り替え

enum Toggler {
    struct Result {
        let code: Int32
        let stderr: String
        var ok: Bool { code == 0 }
        /// ⚠️ osascript の終了コードは成功0／それ以外は全部1に潰れるので、
        /// 「ユーザーがキャンセルした」かどうかは stderr の AppleScript エラー番号 -128 で見るしかない
        var userCanceled: Bool { stderr.contains("-128") }
    }

    /// sudoers が入っていれば無音で、無ければ管理者パスワードのダイアログで切り替える
    static func set(_ disabled: Bool, completion: @escaping (_ result: Result) -> Void) {
        let value = disabled ? "1" : "0"
        DispatchQueue.global(qos: .userInitiated).async {
            let quiet = run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", value])
            if quiet.ok {
                DispatchQueue.main.async { completion(quiet) }
                return
            }
            let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
            let result = run("/usr/bin/osascript", ["-e", script])
            DispatchQueue.main.async { completion(result) }
        }
    }

    @discardableResult
    static func run(_ path: String, _ args: [String]) -> Result {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let errPipe = Pipe()
        p.standardOutput = FileHandle.nullDevice
        p.standardError = errPipe
        do { try p.run() } catch { return Result(code: -1, stderr: "\(error)") }
        // waitUntilExit の前に読み切る（パイプが詰まるとデッドロックする）
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Result(code: p.terminationStatus, stderr: String(data: data, encoding: .utf8) ?? "")
    }

    static let sudoersPath = "/etc/sudoers.d/sleepguard"

    /// ⚠️ `sudo -n -l <cmd>` は使えない：管理者ユーザーは元々そのコマンドを「実行してよい」ので、
    /// NOPASSWD が無くても、直前にターミナルで sudo を叩いてタイムスタンプが生きていれば 0 を返す。
    /// ここは設定ファイルの有無だけを見て、実際に効くかは切り替え時の `sudo -n` の結果で判断する。
    static var sudoersInstalled: Bool {
        FileManager.default.fileExists(atPath: sudoersPath)
    }
}

// MARK: - アプリ本体

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private let menu = NSMenu()
    private var headerItem = NSMenuItem()
    private var warnItem = NSMenuItem()
    private var toggleItem = NSMenuItem()
    private var loginItem = NSMenuItem()
    private var labelItem = NSMenuItem()
    private var sudoersItem = NSMenuItem()
    private var removeSudoersItem = NSMenuItem()
    private var disabled = false
    private var busy = false
    private var sudoersReady = false
    private var lastIconKey = ""

    private var showLabel: Bool {
        get { UserDefaults.standard.bool(forKey: "ShowLabel") }
        set { UserDefaults.standard.set(newValue, forKey: "ShowLabel"); render() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        buildMenu()
        sudoersReady = Toggler.sudoersInstalled
        refresh()
        offerSetupOnFirstRun()
        let tick = Timer(timeInterval: 2.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(tick, forMode: .common)   // メニュー展開中やモーダル中も止めない
        timer = tick
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(refreshFromNotification),
            name: NSWorkspace.didWakeNotification, object: nil)
    }

    // MARK: メニュー

    private func buildMenu() {
        menu.delegate = self
        headerItem.isEnabled = false
        warnItem.isEnabled = false
        toggleItem.target = self
        toggleItem.action = #selector(toggle)
        loginItem.target = self
        loginItem.action = #selector(toggleLoginItem)
        loginItem.title = "ログイン時に起動"
        labelItem.target = self
        labelItem.action = #selector(toggleLabel)
        labelItem.title = "メニューバーに文字を出す"
        sudoersItem.target = self
        sudoersItem.action = #selector(installSudoers)
        removeSudoersItem.target = self
        removeSudoersItem.action = #selector(removeSudoers)
        removeSudoersItem.title = "パスワード不要の設定を取り消す…"

        menu.addItem(headerItem)
        menu.addItem(warnItem)
        menu.addItem(.separator())
        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(loginItem)
        menu.addItem(labelItem)
        menu.addItem(sudoersItem)
        menu.addItem(removeSudoersItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
    }

    func menuWillOpen(_ menu: NSMenu) {
        recheckSudoers()
        refresh()
    }

    private func recheckSudoers() {
        let ready = Toggler.sudoersInstalled
        if ready != sudoersReady {
            sudoersReady = ready
            render()
        }
    }
    func menuDidClose(_ menu: NSMenu) {
        DispatchQueue.main.async { [weak self] in self?.statusItem.menu = nil }
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        let rightish = event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true
        if rightish {
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        } else {
            toggle()
        }
    }

    // MARK: 状態反映

    @objc private func refreshFromNotification() { refresh() }

    private func refresh() {
        disabled = PMState.sleepDisabled()
        render()
    }

    private func render() {
        let onBattery = PMState.powerSource() == .battery
        guard let button = statusItem.button else { return }

        // 見た目が変わるときだけ作り直す（2秒ごとの再描画でチラつかせない）
        let iconKey = "\(disabled)-\(onBattery)-\(showLabel)"
        if iconKey != lastIconKey {
            lastIconKey = iconKey
            // バッテリー駆動中は赤＝電池が減り続けている警告
            button.image = disabled ? Icon.slashed(onBattery ? .systemRed : .systemOrange) : Icon.plain()
            button.title = showLabel ? (disabled ? " 無効" : " 通常") : ""
            button.imagePosition = showLabel ? .imageLeading : .imageOnly
        }
        button.toolTip = disabled
            ? "スリープ無効中：蓋を閉じてもスリープしません（クリックで戻す）"
            : "通常：蓋を閉じるとスリープします（クリックで無効化）"

        headerItem.title = disabled ? "● スリープ無効中（蓋を閉じても起きたまま）" : "○ 通常（蓋を閉じるとスリープ）"
        warnItem.isHidden = !(disabled && onBattery)
        warnItem.title = "⚠️ バッテリー駆動中：電池が減り続けます"
        toggleItem.title = busy ? "切り替え中…" : (disabled ? "スリープを有効に戻す" : "スリープを無効にする")
        toggleItem.isEnabled = !busy
        labelItem.state = showLabel ? .on : .off
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        sudoersItem.title = sudoersReady ? "パスワード不要：設定済み ✓" : "パスワード不要にする…"
        sudoersItem.isEnabled = !sudoersReady
        removeSudoersItem.isHidden = !sudoersReady
    }

    // MARK: アクション

    @objc private func toggle() {
        guard !busy else { return }
        busy = true
        render()
        let target = !disabled
        Toggler.set(target) { [weak self] result in
            guard let self else { return }
            self.refresh()
            // busy はアラートを閉じるまで下ろさない（モーダル中のアイコンクリックで二重起動しないように）
            defer { self.busy = false; self.render() }
            guard self.disabled != target, !result.userCanceled else { return }
            self.alert("切り替えに失敗しました",
                       "メニューの「パスワード不要にする…」を実行するか、ターミナルで\nsudo pmset -a disablesleep \(target ? 1 : 0)\nを試してください。")
        }
    }

    /// 初回起動時だけ、パスワード不要化をこちらから提案する
    private func offerSetupOnFirstRun() {
        guard ProcessInfo.processInfo.environment["SLEEPGUARD_FAKE"] == nil else { return }
        let key = "SetupOfferedV1"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        if sudoersReady {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        UserDefaults.standard.set(true, forKey: key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.installSudoers() }
    }

    @objc private func toggleLabel() { showLabel.toggle() }

    @objc private func toggleLoginItem() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
                // 例外は出ないが「ユーザーの承認待ち」で止まることがある
                if SMAppService.mainApp.status == .requiresApproval {
                    alert("承認が必要です",
                          "システム設定 →「一般」→「ログイン項目と機能拡張」で SleepGuard をオンにしてください。")
                }
            }
        } catch {
            alert("ログイン項目を変更できませんでした",
                  "システム設定 →「一般」→「ログイン項目と機能拡張」から手動で追加してください。\n\(error.localizedDescription)")
        }
        render()
    }

    @objc private func installSudoers() {
        guard let script = Bundle.main.path(forResource: "install-sudoers", ofType: "sh") else {
            alert("スクリプトが見つかりません", "アプリを再ビルドしてください。")
            return
        }
        let a = NSAlert()
        a.messageText = "パスワード入力を不要にします"
        a.informativeText = """
        /etc/sudoers.d/sleepguard に、次の2つのコマンドだけをパスワードなしで許可する設定を書き込みます。

          pmset -a disablesleep 1
          pmset -a disablesleep 0

        この後、管理者パスワードを1回だけ聞かれます。
        """
        a.addButton(withTitle: "続ける")
        a.addButton(withTitle: "キャンセル")
        a.window.level = .floating
        guard frontmost({ a.runModal() }) == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let apple = "do shell script \"/bin/bash \" & quoted form of \"\(script)\" with administrator privileges"
            let result = Toggler.run("/usr/bin/osascript", ["-e", apple])
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recheckSudoers()
                self.render()
                // osascript の終了コードは信用できないので、設定ファイルが出来たかどうかで判定する
                if self.sudoersReady {
                    self.alert("完了", "これ以降はパスワードなし・クリックだけで切り替わります。")
                } else if !result.userCanceled {
                    self.alert("設定できませんでした",
                               "ターミナルで次を実行すると、失敗した理由が表示されます：\nsudo bash \(script)")
                }
            }
        }
    }

    /// LSUIElement のアプリはそのままだとダイアログが他のウインドウの裏に隠れる。
    /// 一時的に通常アプリ扱いにして最前面に出す。
    @discardableResult
    private func frontmost<T>(_ body: () -> T) -> T {
        let previous = NSApp.activationPolicy()
        if previous != .regular { NSApp.setActivationPolicy(.regular) }
        NSApp.activate(ignoringOtherApps: true)
        let result = body()
        if previous != .regular { NSApp.setActivationPolicy(previous) }
        return result
    }

    @objc private func removeSudoers() {
        guard let script = Bundle.main.path(forResource: "uninstall-sudoers", ofType: "sh") else {
            alert("スクリプトが見つかりません", "アプリを再ビルドしてください。")
            return
        }
        let a = NSAlert()
        a.messageText = "パスワード不要の設定を取り消します"
        a.informativeText = "この後、切り替えるたびに管理者パスワードを聞かれるようになります。\nいま管理者パスワードを1回入力してください。"
        a.addButton(withTitle: "取り消す")
        a.addButton(withTitle: "やめる")
        a.window.level = .floating
        guard frontmost({ a.runModal() }) == .alertFirstButtonReturn else { return }

        DispatchQueue.global(qos: .userInitiated).async {
            let apple = "do shell script \"/bin/bash \" & quoted form of \"\(script)\" with administrator privileges"
            let result = Toggler.run("/usr/bin/osascript", ["-e", apple])
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.recheckSudoers()
                self.render()
                if self.sudoersReady && !result.userCanceled {
                    self.alert("取り消せませんでした", "もう一度お試しください。")
                }
            }
        }
    }

    private func alert(_ title: String, _ body: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "OK")
        a.window.level = .floating
        frontmost { a.runModal() }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
