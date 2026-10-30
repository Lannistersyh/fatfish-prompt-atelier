import AppKit

// 单实例：第二个进程唤醒已有实例后直接退出，不创建任何窗口。
guard SingleInstance.acquire() else {
    SingleInstance.handOffToRunningInstance()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// 常规 App：Dock 有图标、⌘Tab 可见、Finder 双击可启动
app.setActivationPolicy(.regular)
app.run()
