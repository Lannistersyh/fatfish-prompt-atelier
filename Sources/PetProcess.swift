import Foundation

/// 1080P 桌宠子进程：由提示词工坊 App 在启动时拉起，退出时回收。
/// 桌宠本身是 Python/PySide6 运行时（~/Library/Application Support/dafeiyu1080/runtime），
/// 这里只负责进程生命周期，不参与其渲染与交互。
final class PetProcess {
    /// 子进程非预期退出（用户点了桌宠菜单里的「退出」，或崩溃）时回调。
    /// 2合1 的语义是「一个 App」：桌宠没了就整体退出，下次启动再一起拉起。
    var onUnexpectedExit: (() -> Void)?

    private var process: Process?
    private var stopping = false
    private let runtimeURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/dafeiyu1080/runtime", isDirectory: true)
    private let logURL = URL(fileURLWithPath: "/tmp/dafeiyu1080.log")
    private let logLimit: UInt64 = 5 * 1024 * 1024

    var isRunning: Bool { process?.isRunning ?? false }

    func start() {
        guard process == nil else { return }
        let python = runtimeURL.appendingPathComponent(".venv/bin/python")
        guard FileManager.default.isExecutableFile(atPath: python.path) else {
            NSLog("PetProcess: 找不到桌宠运行时 %@", python.path)
            return
        }
        let p = Process()
        p.executableURL = python
        p.arguments = ["-m", "pet"]
        p.currentDirectoryURL = runtimeURL
        var env = ProcessInfo.processInfo.environment
        env["PET_FRAMESEQ"] = "0"            // 1080P 帧序列缓存会占几十 GB
        env["DAFEIYU_WORKSHOP_NOTIFY"] = "1" // 点击桌宠 → 通知工坊开关面板
        p.environment = env
        p.standardOutput = logHandle()
        p.standardError = p.standardOutput
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                guard let self else { return }
                let expected = self.stopping
                self.process = nil
                NSLog("PetProcess: 桌宠退出 status=%d expected=%d", proc.terminationStatus, expected ? 1 : 0)
                if !expected { self.onUnexpectedExit?() }
            }
        }
        do {
            try p.run()
            process = p
            NSLog("PetProcess: 桌宠已启动 pid=%d", p.processIdentifier)
        } catch {
            NSLog("PetProcess: 启动失败 %@", error.localizedDescription)
        }
    }

    /// 退出 App 时调用；先 SIGTERM，3 秒不退再 SIGKILL。
    func stop() {
        stopping = true
        guard let p = process, p.isRunning else { process = nil; return }
        p.terminate()
        let deadline = Date().addingTimeInterval(3)
        while p.isRunning && Date() < deadline { usleep(100_000) }
        if p.isRunning {
            NSLog("PetProcess: SIGTERM 超时，强杀 pid=%d", p.processIdentifier)
            kill(p.processIdentifier, SIGKILL)
        }
        process = nil
    }

    /// stdout/stderr 走同一个文件；超过 5 MB 先滚动一次，避免无限增长。
    private func logHandle() -> FileHandle? {
        let fm = FileManager.default
        if let size = try? fm.attributesOfItem(atPath: logURL.path)[.size] as? UInt64, size > logLimit {
            let backup = URL(fileURLWithPath: logURL.path + ".1")
            try? fm.removeItem(at: backup)
            try? fm.moveItem(at: logURL, to: backup)
        }
        if !fm.fileExists(atPath: logURL.path) {
            fm.createFile(atPath: logURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: logURL) else { return nil }
        handle.seekToEndOfFile()
        return handle
    }
}
