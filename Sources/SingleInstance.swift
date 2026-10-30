import AppKit
import Darwin

/// 单实例保护：用文件锁保证「同一时间只有一个进程」，并把第二次启动转交给已在运行的实例。
///
/// 三条防线：
/// 1. `LSMultipleInstancesProhibited`（Info.plist）：LaunchServices 层禁止 `open -n` 再开副本；
/// 2. 本文件的 `flock`：直接执行二进制也挡得住；
/// 3. 转交：第二次启动会唤醒已有实例并打开面板，然后自己退出。
enum SingleInstance {
    private static var lockFD: Int32 = -1

    private static var lockPath: String {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FatFishPrompt", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        return support.appendingPathComponent("instance.lock").path
    }

    /// 拿到锁返回 true；已有实例在跑返回 false。
    /// `--demo` 自测模式放行，避免自动化测试被正在运行的正式实例挡住。
    static func acquire() -> Bool {
        if CommandLine.arguments.contains("--demo") { return true }

        let fd = open(lockPath, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else { return true }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            close(fd)
            return false
        }
        lockFD = fd
        return true
    }

    /// 把「显示面板」的请求转交给已有实例，并把它带到前台。
    static func handOffToRunningInstance() {
        DistributedNotificationCenter.default().post(
            name: Notification.Name("ai.local.fatfish.showPanel"), object: nil)

        let others = NSRunningApplication
            .runningApplications(withBundleIdentifier: "ai.local.fatfish.pet")
            .filter { $0.processIdentifier != getpid() }
        if let other = others.first {
            if #available(macOS 14.0, *) {
                other.activate()
            } else {
                other.activate(options: [.activateIgnoringOtherApps])
            }
        }

        NSLog("大肥鱼提示词工坊已在运行，本次启动已转交给现有实例并退出")
    }
}
