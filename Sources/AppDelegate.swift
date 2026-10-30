import AppKit
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pet: PetWindow!
    private var panel: PanelWindow!
    private var bridge: Bridge!
    private var hotkey: HotkeyManager?
    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var screenObserver: NSObjectProtocol?

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(handleExternalShow),
            name: Notification.Name("ai.local.fatfish.showPanel"), object: nil)

        panel = PanelWindow()
        pet = PetWindow()
        bridge = Bridge(panel: panel, pet: pet)

        panel.webView.configuration.userContentController.add(bridge, name: "fish")
        panel.loadUI()
        pet.loadUI()

        bridge.onTogglePanel = { [weak self] in self?.togglePanel() }
        bridge.onHidePanel = { [weak self] in self?.hidePanel() }
        bridge.onPin = { [weak self] on in self?.panel.level = on ? .floating : .normal }

        pet.roamingEnabled = UserDefaults.standard.object(forKey: "pet.roaming") as? Bool ?? true
        pet.soundEnabled = UserDefaults.standard.object(forKey: "pet.sound") as? Bool ?? true
        pet.onClick = { [weak self] in self?.togglePanel() }
        pet.onMoveEnd = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(NSStringFromRect(self.pet.frame), forKey: "pet.frame")
        }
        pet.menuBuilder = { [weak self] in self?.petMenu() ?? NSMenu() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.pet.place(at: self.pet.frame.origin)
            if self.panel.isVisible { self.positionPanel() }
        }

        setupStatusItem()

        hotkey = HotkeyManager(keyCode: UInt32(kVK_ANSI_P),
                               modifiers: UInt32(optionKey | shiftKey)) { [weak self] in
            self?.togglePanel()
        }
        if hotkey == nil {
            print("HOTKEY: ⌥⇧P 注册失败，可用菜单栏图标")
            fflush(stdout)
        }

        restorePetPosition()
        pet.orderFrontRegardless()

        // 自测钩子：PET_WALK_DIR=left|right 时立刻走两步，方便截图核对朝向
        if ProcessInfo.processInfo.environment["PET_WALK_DIR"] != nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.pet.walkNow()
            }
        }

        if CommandLine.arguments.contains("--demo") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.runDemo()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        UserDefaults.standard.set(NSStringFromRect(pet.frame), forKey: "pet.frame")
        panel.webView.configuration.userContentController.removeScriptMessageHandler(forName: "fish")
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        DistributedNotificationCenter.default().removeObserver(self)
    }

    // MARK: - Dock / 菜单栏

    /// 点 Dock 图标（或 Finder 双击已在运行的 App）时，把面板叫出来。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    /// 右键 Dock 图标的快捷菜单。
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: panel.isVisible ? "收起提示词工坊" : "打开提示词工坊",
                     action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "让大肥鱼说句话", action: #selector(petSpeak), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func handleExternalShow() {
        DispatchQueue.main.async { [weak self] in
            if #available(macOS 14.0, *) {
                NSApp.activate()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
            self?.showPanel()
        }
    }

    /// 常规 App 必须有主菜单：否则 ⌘Q 失灵，输入框里的 ⌘V 也收不到。
    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 大肥鱼提示词工坊",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "打开提示词工坊", action: #selector(togglePanel), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 大肥鱼提示词工坊",
                        action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "退出 大肥鱼提示词工坊",
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "编辑")
        edit.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }

    // MARK: - 窗口

    private func restorePetPosition() {
        if let saved = UserDefaults.standard.string(forKey: "pet.frame"), !saved.isEmpty {
            let rect = NSRectFromString(saved)
            if rect.width > 100, rect.origin.x.isFinite, rect.origin.y.isFinite {
                pet.place(at: PetGeometry.migratedOrigin(rect))
                return
            }
        }
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        pet.place(at: NSPoint(x: visible.maxX - pet.frame.width - 20, y: visible.minY + 20))
    }

    @objc func togglePanel() {
        if panel.isVisible { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        positionPanel()
        panel.orderFrontRegardless()
        panel.makeKey()
        panel.webView.evaluateJavaScript(
            "window.__fish && window.__fish.onShow && window.__fish.onShow();",
            completionHandler: nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            self.panel.makeFirstResponder(self.panel.webView)
        }
    }

    func hidePanel() {
        panel.orderOut(nil)
    }

    private func positionPanel() {
        guard let screen = pet.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        let petFrame = pet.frame
        let size = panel.frame.size

        var x = petFrame.minX - size.width - 14
        if x < visible.minX + 12 { x = petFrame.maxX + 14 }
        x = min(max(visible.minX + 12, x), visible.maxX - size.width - 12)

        var y = petFrame.minY - 40
        y = min(max(visible.minY + 12, y), visible.maxY - size.height - 12)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    // MARK: - 桌宠菜单

    private func petMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: panel.isVisible ? "收起提示词工坊" : "打开提示词工坊",
                     action: #selector(togglePanel), keyEquivalent: "")
        menu.addItem(withTitle: "让大肥鱼说句话", action: #selector(petSpeak), keyEquivalent: "")
        menu.addItem(withTitle: "走两步", action: #selector(petWalk), keyEquivalent: "")
        menu.addItem(.separator())

        let roam = NSMenuItem(title: "自由漫游", action: #selector(toggleRoaming(_:)), keyEquivalent: "")
        roam.state = pet.roamingEnabled ? .on : .off
        menu.addItem(roam)
        let sound = NSMenuItem(title: "点击音效", action: #selector(toggleSound(_:)), keyEquivalent: "")
        sound.state = pet.soundEnabled ? .on : .off
        menu.addItem(sound)

        menu.addItem(.separator())
        menu.addItem(withTitle: "查 DeepSeek 余额", action: #selector(checkBalance), keyEquivalent: "")
        menu.addItem(withTitle: pet.isVisible ? "隐藏桌宠" : "显示桌宠", action: #selector(togglePet), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "")
        menu.items.forEach { $0.target = self }
        return menu
    }

    @objc private func petWalk() {
        pet.walkNow()
    }

    @objc private func toggleRoaming(_ sender: NSMenuItem) {
        pet.roamingEnabled.toggle()
        sender.state = pet.roamingEnabled ? .on : .off
        UserDefaults.standard.set(pet.roamingEnabled, forKey: "pet.roaming")
    }

    @objc private func toggleSound(_ sender: NSMenuItem) {
        pet.soundEnabled.toggle()
        sender.state = pet.soundEnabled ? .on : .off
        UserDefaults.standard.set(pet.soundEnabled, forKey: "pet.sound")
        if pet.soundEnabled { NSSound(named: "Tink")?.play() }
    }

    @objc private func checkBalance() {
        pet.bubble("查一下余额…", seconds: 2)
        BalanceService.fetch { [weak self] text in
            self?.pet.bubble(text, seconds: 6)
        }
    }

    @objc private func petSpeak() {
        pet.setState("success")
        pet.bubble("写提示词我最拿手，戳我！", seconds: 4)
    }

    @objc private func togglePet() {
        if pet.isVisible {
            pet.orderOut(nil)
            petIsHidden = true
        } else {
            pet.orderFrontRegardless()
            petIsHidden = false
        }
        statusMenu?.item(at: 2)?.title = pet.isVisible ? "隐藏桌宠" : "显示桌宠"
    }

    private var petIsHidden = false

    @objc private func togglePin() {
        let next = panel.level != .normal
        panel.level = next ? .normal : .floating
        statusMenu?.item(at: 1)?.state = next ? .off : .on
    }

    @objc private func openProjectFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Users/admin/科研项目/肥鱼提示词工坊"))
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: "fish.fill", accessibilityDescription: "大肥鱼")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "大肥鱼提示词工坊（⌥⇧P 打开/收起）"
        }

        let menu = NSMenu()
        menu.addItem(withTitle: "打开 / 收起提示词工坊　⌥⇧P", action: #selector(togglePanel), keyEquivalent: "")
        let pin = NSMenuItem(title: "面板取消置顶", action: #selector(togglePin), keyEquivalent: "")
        menu.addItem(pin)
        menu.addItem(withTitle: "隐藏桌宠", action: #selector(togglePet), keyEquivalent: "")
        menu.addItem(withTitle: "查 DeepSeek 余额", action: #selector(checkBalance), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开项目文件夹", action: #selector(openProjectFolder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        menu.item(at: 2)?.target = self
        statusMenu = menu
        statusItem?.menu = menu
    }

    // MARK: - 自测

    private func runDemo() {
        showPanel()
        let text = "帮我给一个 macOS 小工具写个提示词：把它每周的文献速览整理成一页表格，别太长，只要最近 7 天的，保留标题和链接"
        guard let data = try? JSONSerialization.data(withJSONObject: ["text": text]),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.panel.webView.evaluateJavaScript(
                "window.__fishDemoFill && window.__fishDemoFill(\(json));", completionHandler: nil)
            self?.pollIdle(attempt: 0)
        }
    }

    private func pollIdle(attempt: Int) {
        guard attempt < 160 else {
            print("DEMO: TIMEOUT")
            fflush(stdout)
            return
        }
        panel.webView.evaluateJavaScript("document.getElementById('card').classList.contains('busy')") { [weak self] result, _ in
            guard let self else { return }
            if let busy = result as? Bool, busy == false, attempt > 4 {
                self.runChecks()
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.pollIdle(attempt: attempt + 1)
                }
            }
        }
    }

    private func runChecks() {
        let js = """
        (function(){
          document.getElementById('btnCopy').click();
          var out = {
            chars: document.getElementById('output').innerText.length,
            meta: document.getElementById('outMeta').textContent
          };
          return JSON.stringify(out);
        })();
        """
        panel.webView.evaluateJavaScript(js) { result, _ in
            print("DEMO PANEL:", result ?? "nil")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                let clip = NSPasteboard.general.string(forType: .string) ?? ""
                print("DEMO CLIPBOARD:", clip.count, "head:", clip.prefix(24))
                self.petStateForDebug { state in
                    print("DEMO PET STATE:", state)
                    fflush(stdout)
                }
            }
        }
    }

    private func petStateForDebug(completion: @escaping (String) -> Void) {
        completion(pet.animationState)
    }
}
