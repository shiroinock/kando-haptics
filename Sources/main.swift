import AppKit
import Foundation

enum Feedback: String { case hover, selection, submenu }

/// A menu transition fires once, with a short cooldown for boundary jitter.
struct FeedbackRouter {
    var hoveredPath: [Int]?
    var lastHoverTime = -Double.infinity

    mutating func route(_ event: String, path: [Int], time: Double) -> Feedback? {
        switch event {
        case "openMenu", "closeMenu", "hoverCenter", "hoverParent", "closeSubmenu":
            hoveredPath = nil
            return nil
        case "hoverButton", "hoverSubmenu":
            guard hoveredPath != path else { return nil }
            hoveredPath = path
            guard time - lastHoverTime >= 0.04 else { return nil }
            lastHoverTime = time
            return .hover
        case "selectButton":
            return .selection
        case "openSubmenu":
            hoveredPath = nil
            return .submenu
        default:
            return nil
        }
    }
}

struct ConnectionInfo: Decodable { let port: Int; let apiVersion: Int }
struct Interaction: Decodable {
    let type: String
    let interaction: String
    let path: [Int]
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var enabledCheckbox: NSButton?
    private var selectionCheckbox: NSButton?
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var router = FeedbackRouter()
    private var window: NSWindow?
    private var details: NSTextField?
    private var connection = "接続待ち"
    private var lastEvent = "まだ受信していません"
    private var eventCount = 0
    private var feedbackCount = 0
    private var enabled = true
    private var selectionEnabled = true
    private let defaults = UserDefaults.standard
    private let diagnosticOnly = CommandLine.arguments.contains("--diagnostics-only")

    private var infoURL: URL {
        if let index = CommandLine.arguments.firstIndex(of: "--ipc-info"),
           CommandLine.arguments.indices.contains(index + 1) {
            return URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/kando/ipc-info.json")
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true
        selectionEnabled = defaults.object(forKey: "selectionEnabled") as? Bool ?? true
        refreshUI()
        connect()
        if CommandLine.arguments.contains("--show-diagnostics") { showDiagnostics() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDiagnostics()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        reconnectTask?.cancel()
        receiveTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
    }

    private func connect() {
        reconnectTask?.cancel()
        do {
            let info = try JSONDecoder().decode(ConnectionInfo.self, from: Data(contentsOf: infoURL))
            guard info.apiVersion == 2 else {
                setConnection("API \(info.apiVersion) は未対応（Kando 3.x用）")
                scheduleReconnect()
                return
            }
            guard (1...65535).contains(info.port) else {
                setConnection("接続情報のポートが不正です")
                scheduleReconnect()
                return
            }
            let url = URL(string: "ws://127.0.0.1:\(info.port)")!
            let task = URLSession.shared.webSocketTask(with: url)
            socket = task
            task.resume()
            setConnection("Kandoに接続中…")
            receiveTask = Task { [weak self] in
                do {
                    try await task.send(.string("{\"type\":\"start-observing\"}"))
                    guard let self, self.socket === task, !Task.isCancelled else { return }
                    self.setConnection("Kandoに接続済み")
                    while !Task.isCancelled {
                        let message = try await task.receive()
                        guard self.socket === task, !Task.isCancelled else { return }
                        let data: Data
                        switch message {
                        case .string(let value): data = Data(value.utf8)
                        case .data(let value): data = value
                        @unknown default: continue
                        }
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           json["type"] as? String == "error" {
                            self.setConnection("Kando APIエラー: \(json["reason"] as? String ?? "unknown")")
                            task.cancel(with: .normalClosure, reason: nil)
                            self.socket = nil
                            self.scheduleReconnect()
                            return
                        }
                        if let event = try? JSONDecoder().decode(Interaction.self, from: data),
                           event.type == "menu-interaction" {
                            self.handle(event)
                        }
                    }
                } catch {
                    guard let self, self.socket === task, !Task.isCancelled else { return }
                    self.socket = nil
                    task.cancel(with: .goingAway, reason: nil)
                    self.setConnection("接続が切れました。再接続します")
                    self.scheduleReconnect()
                }
            }
        } catch {
            setConnection("Kandoを起動してください（接続情報待ち）")
            scheduleReconnect()
        }
    }

    private func scheduleReconnect() {
        reconnectTask?.cancel()
        reconnectTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.connect()
        }
    }

    private func handle(_ event: Interaction) {
        eventCount += 1
        lastEvent = "\(event.interaction)  \(event.path)"
        if let feedback = router.route(event.interaction, path: event.path, time: ProcessInfo.processInfo.systemUptime),
           enabled, feedback == .hover || selectionEnabled {
            feedbackCount += 1
            if !diagnosticOnly {
                let pattern: NSHapticFeedbackManager.FeedbackPattern = feedback == .hover ? .alignment : .generic
                NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
            }
            print("FEEDBACK \(feedback.rawValue) \(event.path)")
            fflush(stdout)
        }
        refreshUI()
    }

    private func setConnection(_ value: String) {
        connection = value
        print("STATUS \(value)")
        fflush(stdout)
        refreshUI()
    }

    private func refreshUI() {
        enabledCheckbox?.state = enabled ? .on : .off
        selectionCheckbox?.state = selectionEnabled ? .on : .off
        details?.stringValue = diagnosticText
    }

    private var diagnosticText: String {
        "\(connection)\n\n受信イベント: \(eventCount)\n触覚リクエスト: \(feedbackCount)\n最後のイベント: \(lastEvent)\n\n\(infoURL.path)\n\n項目を跨ぐと alignment、選択・階層移動で generic を要求します。\nリクエスト数は、実際に振動した回数ではありません。\n\nテストを選んだら、3秒以内に指をTrackpadに置いてください。\nmacOS側の判断で触覚が抑制される場合があります。\n\nKando 3.x / WebSocket API v2用の独立した試作です。"
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        defaults.set(enabled, forKey: "enabled")
        router = FeedbackRouter()
        refreshUI()
    }

    @objc private func toggleSelection() {
        selectionEnabled.toggle()
        defaults.set(selectionEnabled, forKey: "selectionEnabled")
        refreshUI()
    }

    @objc private func testHaptic() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !diagnosticOnly {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            feedbackCount += 1
            refreshUI()
        }
    }

    @objc private func showDiagnostics() {
        if window == nil {
            let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
                                 styleMask: [.titled, .closable], backing: .buffered, defer: false)
            panel.title = "Kando Haptics — 動作状況"
            panel.isReleasedWhenClosed = false
            let label = NSTextField(wrappingLabelWithString: diagnosticText)
            label.frame = NSRect(x: 24, y: 110, width: 512, height: 326)
            label.font = .systemFont(ofSize: 13)
            label.isSelectable = true
            panel.contentView?.addSubview(label)
            let enabledControl = NSButton(checkboxWithTitle: "触覚フィードバックを有効にする", target: self, action: #selector(toggleEnabled))
            enabledControl.frame = NSRect(x: 24, y: 78, width: 400, height: 24)
            panel.contentView?.addSubview(enabledControl)
            enabledCheckbox = enabledControl
            let selectionControl = NSButton(checkboxWithTitle: "選択・サブメニューでも触覚を返す", target: self, action: #selector(toggleSelection))
            selectionControl.frame = NSRect(x: 24, y: 52, width: 400, height: 24)
            panel.contentView?.addSubview(selectionControl)
            selectionCheckbox = selectionControl
            let test = NSButton(title: "触覚をテスト（3秒後）", target: self, action: #selector(testHaptic))
            test.bezelStyle = .rounded
            test.frame = NSRect(x: 24, y: 12, width: 210, height: 32)
            panel.contentView?.addSubview(test)
            let quit = NSButton(title: "終了", target: NSApp, action: #selector(NSApplication.terminate(_:)))
            quit.bezelStyle = .rounded
            quit.frame = NSRect(x: 446, y: 12, width: 90, height: 32)
            panel.contentView?.addSubview(quit)
            panel.center()
            window = panel
            details = label
        }
        refreshUI()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

func runSelfTests() {
    var router = FeedbackRouter()
    let cases: [(String, [Int], Double, Feedback?)] = [
        ("openMenu", [], 0, nil),
        ("hoverButton", [0], 0.1, .hover),
        ("hoverButton", [0], 0.2, nil),
        ("hoverButton", [1], 0.21, .hover),
        ("hoverButton", [0], 0.22, nil),
        ("hoverCenter", [], 0.23, nil),
        ("hoverButton", [0], 0.3, .hover),
        ("selectButton", [0], 0.31, .selection),
        ("openSubmenu", [2], 0.32, .submenu),
        ("hoverSubmenu", [2, 1], 0.4, .hover),
        ("closeMenu", [], 0.5, nil),
        ("hoverButton", [2, 1], 0.6, .hover),
        ("unknown", [], 0.7, nil),
    ]
    for (event, path, time, expected) in cases {
        precondition(router.route(event, path: path, time: time) == expected, "Failed: \(event)")
    }
    print("PASS: 13 routing cases (deduplication, cooldown, selection, reset, submenus)")
}

if CommandLine.arguments.contains("--self-test") {
    runSelfTests()
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
